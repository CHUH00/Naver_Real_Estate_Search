import Foundation
import Network
import UIKit

/// 네이버가 클라우드 서버 IP를 차단하기 때문에, 서버(Render) 대신 이 아이폰의
/// 실제 이동통신/와이파이 네트워크로 네이버 요청을 대신 내보내주는 중계 클라이언트.
///
/// 서버(web/relay.py)가 SOCKS5 CONNECT 요청을 이 웹소켓으로 보내면, 여기서 실제
/// TCP 연결을 열어 바이트를 그대로 주고받는다.
///
/// 모든 실제 네트워크 처리(패킷 수신, base64/JSON 인코딩)는 전용 백그라운드
/// 큐에서 돈다 — 메인(UI) 스레드에서 처리하면 수집 중 데이터가 오갈 때마다
/// 화면이 버벅이고 버튼 반응이 늦어진다. `isConnected`(화면에 보여줄 상태)만
/// 메인 스레드로 넘긴다.
///
/// 앱을 백그라운드로 내려도(화면 잠금, 다른 앱으로 전환) 잠시 동안은 계속
/// 수집이 이어지도록 UIBackgroundTask로 실행 시간을 연장한다. 단, 이는 iOS가
/// 허용하는 범위 내의 "연장"일 뿐이며, 앱을 완전히 종료(스와이프)하면 즉시
/// 끊긴다 — iOS 정책상 일반 앱이 무기한 백그라운드 네트워킹을 하는 것은
/// 불가능하다.
final class RelayClient: ObservableObject {
    static let shared = RelayClient()

    @Published var isConnected = false

    // 아래 상태는 전부 `queue`에서만 접근한다 (락 없이 직렬화로 스레드 안전성 확보).
    private let queue = DispatchQueue(label: "com.genon.naverland.relay")
    private var task: URLSessionWebSocketTask?
    private var sessionID: String?
    private var reconnectWorkItem: DispatchWorkItem?
    private var connections: [Int: NWConnection] = [:]
    private var shouldRun = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.queue.async { self?.handleDidEnterBackground() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.queue.async { self?.handleWillEnterForeground() }
        }
    }

    private func setConnected(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in self?.isConnected = value }
    }

    private func handleDidEnterBackground() {
        guard shouldRun, backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "naverland-relay") { [weak self] in
            self?.queue.async { self?.endBackgroundTask() }
        }
    }

    private func handleWillEnterForeground() {
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func start(sessionID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = true
            guard self.sessionID != sessionID || self.task == nil else { return }
            self.sessionID = sessionID
            self.connect()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            self.endBackgroundTask()
            self.reconnectWorkItem?.cancel()
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.setConnected(false)
            for (_, conn) in self.connections { conn.cancel() }
            self.connections.removeAll()
        }
    }

    /// queue 위에서만 호출.
    private func connect() {
        guard shouldRun, let sessionID, let url = APIClient.shared.websocketURL(path: "/ws/relay/\(sessionID)") else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        setConnected(true)
        listen()
    }

    /// queue 위에서만 호출.
    private func scheduleReconnect() {
        setConnected(false)
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
        guard shouldRun else { return }
        let item = DispatchWorkItem { [weak self] in self?.queue.async { self?.connect() } }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = item
        queue.asyncAfter(deadline: .now() + 3, execute: item)
    }

    /// queue 위에서만 호출.
    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .failure:
                    self.scheduleReconnect()
                case .success(let message):
                    self.handle(message)
                    self.listen()
                }
            }
        }
    }

    /// queue 위에서만 호출.
    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              let streamID = obj["stream_id"] as? Int
        else { return }

        switch type {
        case "open":
            guard let host = obj["host"] as? String, let port = obj["port"] as? Int else { return }
            openConnection(streamID: streamID, host: host, port: port)
        case "data":
            guard let b64 = obj["data"] as? String, let bytes = Data(base64Encoded: b64) else { return }
            connections[streamID]?.send(content: bytes, completion: .contentProcessed { _ in })
        case "close":
            connections[streamID]?.cancel()
            connections.removeValue(forKey: streamID)
        default:
            break
        }
    }

    /// queue 위에서만 호출.
    private func openConnection(streamID: Int, host: String, port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            sendJSON(["type": "error", "stream_id": streamID, "message": "bad port"])
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connections[streamID] = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                switch state {
                case .ready:
                    self.sendJSON(["type": "opened", "stream_id": streamID])
                    self.receiveLoop(streamID: streamID, conn: conn)
                case .failed, .cancelled:
                    self.sendJSON(["type": "error", "stream_id": streamID, "message": "connection failed"])
                    self.connections.removeValue(forKey: streamID)
                default:
                    break
                }
            }
        }
        // 전용 백그라운드 큐에서 패킷을 처리 — 메인 스레드는 절대 건드리지 않는다.
        conn.start(queue: queue)
    }

    /// queue 위에서만 호출.
    private func receiveLoop(streamID: Int, conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let data, !data.isEmpty {
                    self.sendJSON(["type": "data", "stream_id": streamID, "data": data.base64EncodedString()])
                }
                if isComplete || error != nil {
                    self.sendJSON(["type": "close", "stream_id": streamID])
                    self.connections.removeValue(forKey: streamID)
                    return
                }
                self.receiveLoop(streamID: streamID, conn: conn)
            }
        }
    }

    /// queue 위에서만 호출.
    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }
}
