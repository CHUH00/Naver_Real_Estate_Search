import Foundation
import Network
import UIKit

/// 네이버가 클라우드 서버 IP를 차단하기 때문에, 서버(Render) 대신 이 아이폰의
/// 실제 이동통신/와이파이 네트워크로 네이버 요청을 대신 내보내주는 중계 클라이언트.
///
/// 서버(web/relay.py)가 SOCKS5 CONNECT 요청을 이 웹소켓으로 보내면, 여기서 실제
/// TCP 연결을 열어 바이트를 그대로 주고받는다.
///
/// 앱을 백그라운드로 내려도(화면 잠금, 다른 앱으로 전환) 잠시 동안은 계속
/// 수집이 이어지도록 UIBackgroundTask로 실행 시간을 연장한다. 단, 이는 iOS가
/// 허용하는 범위 내의 "연장"일 뿐이며, 앱을 완전히 종료(스와이프)하면 즉시
/// 끊긴다 — iOS 정책상 일반 앱이 무기한 백그라운드 네트워킹을 하는 것은
/// 불가능하다.
@MainActor
final class RelayClient: ObservableObject {
    static let shared = RelayClient()

    @Published var isConnected = false

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
            Task { @MainActor in self?.handleDidEnterBackground() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWillEnterForeground() }
        }
    }

    private func handleDidEnterBackground() {
        guard shouldRun, backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "naverland-relay") { [weak self] in
            self?.endBackgroundTask()
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
        shouldRun = true
        guard self.sessionID != sessionID || task == nil else { return }
        self.sessionID = sessionID
        connect()
    }

    func stop() {
        shouldRun = false
        endBackgroundTask()
        reconnectWorkItem?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
    }

    private func connect() {
        guard shouldRun, let sessionID, let url = APIClient.shared.websocketURL(path: "/ws/relay/\(sessionID)") else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        isConnected = true
        listen()
    }

    private func scheduleReconnect() {
        isConnected = false
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
        guard shouldRun else { return }
        let item = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
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

    private func openConnection(streamID: Int, host: String, port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            sendJSON(["type": "error", "stream_id": streamID, "message": "bad port"])
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connections[streamID] = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
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
        conn.start(queue: .main)
    }

    private func receiveLoop(streamID: Int, conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
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

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }
}
