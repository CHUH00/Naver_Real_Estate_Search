"""SOCKS5 <-> WebSocket 릴레이.

네이버 부동산이 클라우드/데이터센터 IP를 통째로 차단하기 때문에, 이 서버가 직접
네이버에 접속하는 대신 아이폰 앱(실제 이동통신/와이파이 IP)을 경유해서 접속한다.

흐름:
  Playwright(Chromium) -> 로컬 SOCKS5 서버(이 모듈) -> WebSocket -> 아이폰 앱
  아이폰 앱이 실제 TCP 연결을 열어 바이트를 그대로 중계한다.
"""

from __future__ import annotations

import asyncio
import base64
import socket
import struct

from fastapi import WebSocket, WebSocketDisconnect

# session_id -> 아이폰과 연결된 웹소켓
_phones: dict[str, WebSocket] = {}

# (session_id, stream_id) -> 수신 데이터 큐 (None 이 들어오면 스트림 종료)
_streams: dict[tuple[str, int], asyncio.Queue] = {}

# (session_id, stream_id) -> open 응답 대기용 Future
_open_waiters: dict[tuple[str, int], asyncio.Future] = {}

_next_stream_id = 0


def is_phone_connected(session_id: str) -> bool:
    return session_id in _phones


def _alloc_stream_id() -> int:
    global _next_stream_id
    _next_stream_id += 1
    return _next_stream_id


async def phone_relay_endpoint(websocket: WebSocket, session_id: str):
    """아이폰 앱이 붙는 웹소켓 엔드포인트. web/main.py 에서 라우팅.

    실제 트래픽이 뜸한 순간에도 연결이 완전히 idle 상태가 되지 않도록 주기적으로
    ping을 보낸다 — 일부 호스팅 환경의 프록시가 오래 idle인 웹소켓을 중간에
    끊어버리는 경우가 있어, 이를 예방하기 위함.
    """
    await websocket.accept()
    _phones[session_id] = websocket
    try:
        while True:
            try:
                msg = await asyncio.wait_for(websocket.receive_json(), timeout=10)
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "ping"})
                continue
            await _handle_phone_message(session_id, msg)
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        if _phones.get(session_id) is websocket:
            _phones.pop(session_id, None)
        for key in [k for k in list(_streams) if k[0] == session_id]:
            q = _streams.pop(key, None)
            if q:
                await q.put(None)
        for key in [k for k in list(_open_waiters) if k[0] == session_id]:
            fut = _open_waiters.pop(key, None)
            if fut and not fut.done():
                fut.set_result(False)


async def _handle_phone_message(session_id: str, msg: dict):
    mtype = msg.get("type")
    stream_id = msg.get("stream_id")
    key = (session_id, stream_id)

    if mtype == "opened":
        fut = _open_waiters.get(key)
        if fut and not fut.done():
            fut.set_result(True)
    elif mtype == "error":
        fut = _open_waiters.get(key)
        if fut and not fut.done():
            fut.set_result(False)
        q = _streams.get(key)
        if q:
            await q.put(None)
    elif mtype == "data":
        q = _streams.get(key)
        if q:
            await q.put(base64.b64decode(msg["data"]))
    elif mtype == "close":
        q = _streams.get(key)
        if q:
            await q.put(None)


class RelayUnavailable(Exception):
    pass


async def _open_stream(session_id: str, host: str, port: int, stream_id: int, timeout: float = 15) -> bool:
    phone = _phones.get(session_id)
    if phone is None:
        raise RelayUnavailable("phone not connected")

    key = (session_id, stream_id)
    fut: asyncio.Future = asyncio.get_event_loop().create_future()
    _open_waiters[key] = fut
    _streams[key] = asyncio.Queue()

    await phone.send_json({"type": "open", "stream_id": stream_id, "host": host, "port": port})
    try:
        ok = await asyncio.wait_for(fut, timeout=timeout)
    except asyncio.TimeoutError:
        ok = False
    finally:
        _open_waiters.pop(key, None)

    if not ok:
        _streams.pop(key, None)
    return ok


async def _send_data(session_id: str, stream_id: int, data: bytes):
    phone = _phones.get(session_id)
    if phone is None:
        return
    try:
        await phone.send_json({
            "type": "data",
            "stream_id": stream_id,
            "data": base64.b64encode(data).decode(),
        })
    except Exception:
        pass


async def _close_stream(session_id: str, stream_id: int):
    phone = _phones.get(session_id)
    if phone is not None:
        try:
            await phone.send_json({"type": "close", "stream_id": stream_id})
        except Exception:
            pass
    _streams.pop((session_id, stream_id), None)


async def _pump_local_to_remote(session_id: str, stream_id: int, reader: asyncio.StreamReader):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            await _send_data(session_id, stream_id, data)
    except (asyncio.CancelledError, ConnectionResetError):
        pass
    finally:
        await _close_stream(session_id, stream_id)


async def _pump_remote_to_local(session_id: str, stream_id: int, writer: asyncio.StreamWriter):
    """폰에서 오는 데이터를 로컬 소켓으로 흘려보낸다.

    폰이 앱 종료 등으로 깨끗하게 연결을 끊지 못하고 그냥 사라지는 경우
    (예: 강제 종료, 네트워크 전환), q.get()이 영원히 안 끝날 수 있다.
    이러면 이 스트림을 기다리는 Playwright의 fetch 호출도 영원히 멈추고,
    그 백그라운드 스레드 전체가 멈춰서 서버 리소스를 계속 붙잡게 된다.
    그래서 일정 시간 데이터가 없으면 죽은 것으로 보고 스트림을 닫는다.
    """
    key = (session_id, stream_id)
    q = _streams.get(key)
    if q is None:
        return
    IDLE_TIMEOUT = 45
    try:
        while True:
            try:
                chunk = await asyncio.wait_for(q.get(), timeout=IDLE_TIMEOUT)
            except asyncio.TimeoutError:
                break
            if chunk is None:
                break
            writer.write(chunk)
            await writer.drain()
    except (asyncio.CancelledError, ConnectionResetError):
        pass
    finally:
        _streams.pop(key, None)
        try:
            writer.close()
        except Exception:
            pass


async def _handle_socks_client(session_id: str, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        # ── SOCKS5 인사 (인증 없음) ──────────────────────────────────────
        greeting = await reader.readexactly(2)
        nmethods = greeting[1]
        await reader.readexactly(nmethods)
        writer.write(bytes([0x05, 0x00]))
        await writer.drain()

        # ── SOCKS5 CONNECT 요청 ─────────────────────────────────────────
        hdr = await reader.readexactly(4)
        _ver, _cmd, _rsv, atyp = hdr
        if atyp == 0x01:  # IPv4
            addr_bytes = await reader.readexactly(4)
            host = socket.inet_ntoa(addr_bytes)
        elif atyp == 0x03:  # 도메인명
            length = (await reader.readexactly(1))[0]
            host = (await reader.readexactly(length)).decode()
        elif atyp == 0x04:  # IPv6
            addr_bytes = await reader.readexactly(16)
            host = socket.inet_ntop(socket.AF_INET6, addr_bytes)
        else:
            writer.close()
            return
        port = struct.unpack(">H", await reader.readexactly(2))[0]

        stream_id = _alloc_stream_id()
        try:
            ok = await _open_stream(session_id, host, port, stream_id)
        except RelayUnavailable:
            ok = False

        if not ok:
            # 0x05 = Connection refused
            writer.write(bytes([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
            await writer.drain()
            writer.close()
            return

        writer.write(bytes([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
        await writer.drain()

        pump_out = asyncio.create_task(_pump_local_to_remote(session_id, stream_id, reader))
        pump_in = asyncio.create_task(_pump_remote_to_local(session_id, stream_id, writer))
        await asyncio.wait([pump_out, pump_in], return_when=asyncio.FIRST_COMPLETED)
        pump_out.cancel()
        pump_in.cancel()
    except (asyncio.IncompleteReadError, ConnectionResetError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


# session_id -> (asyncio.Server, port)
_socks_servers: dict[str, tuple[asyncio.AbstractServer, int]] = {}


async def get_or_start_socks_server(session_id: str) -> int:
    """세션 전용 로컬 SOCKS5 서버를 (없으면) 띄우고 포트 번호를 반환."""
    existing = _socks_servers.get(session_id)
    if existing is not None:
        return existing[1]

    async def handler(reader, writer):
        await _handle_socks_client(session_id, reader, writer)

    server = await asyncio.start_server(handler, host="127.0.0.1", port=0)
    port = server.sockets[0].getsockname()[1]
    _socks_servers[session_id] = (server, port)
    return port
