import Foundation
import UIKit

@MainActor
final class WebSocketLogger: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isRunning = false
    @Published var resultSummary: String?

    private var task: URLSessionWebSocketTask?
    private var currentJobID: String?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 6

    func start(jobID: String) {
        currentJobID = jobID
        reconnectAttempts = 0
        resultSummary = nil
        isRunning = true
        // 수집 중 화면이 잠기면 아이폰 네트워크가 일시 중단되어 연결이 끊긴다 — 자동 잠금 방지.
        UIApplication.shared.isIdleTimerDisabled = true
        connect(jobID: jobID)
    }

    private func connect(jobID: String) {
        guard let url = APIClient.shared.websocketURL(jobID: jobID) else {
            append("웹소켓 주소를 만들 수 없습니다.", tag: "error")
            finish()
            return
        }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let error):
                    self.handleDisconnect(error: error)
                case .success(let message):
                    self.handle(message)
                    if self.isRunning {
                        self.listen()
                    }
                }
            }
        }
    }

    private func handleDisconnect(error: Error) {
        guard isRunning, let jobID = currentJobID else { return }
        reconnectAttempts += 1
        if reconnectAttempts <= maxReconnectAttempts {
            append("연결이 잠시 끊겼습니다. 재연결 시도 중… (\(reconnectAttempts)/\(maxReconnectAttempts))", tag: "dim")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard self.isRunning, self.currentJobID == jobID else { return }
                self.connect(jobID: jobID)
            }
        } else {
            append("연결 끊김: \(error.localizedDescription)", tag: "error")
            finish()
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        // 정상적으로 메시지를 받았다면 재연결 카운터를 초기화.
        reconnectAttempts = 0

        switch type {
        case "log":
            let msg = obj["msg"] as? String ?? ""
            let tag = obj["tag"] as? String ?? "dim"
            append(msg, tag: tag)
        case "done":
            let ok = obj["ok"] as? Int ?? 0
            let skip = obj["skip"] as? Int ?? 0
            let filtered = obj["filtered"] as? Int ?? 0
            resultSummary = "저장 \(ok)건 · 중복 \(skip)건 · 필터 제외 \(filtered)건"
            finish()
        case "ping":
            break
        default:
            break
        }
    }

    private func append(_ msg: String, tag: String) {
        for line in msg.split(separator: "\n", omittingEmptySubsequences: false) {
            entries.append(LogEntry(message: String(line), tag: tag))
        }
    }

    private func finish() {
        isRunning = false
        currentJobID = nil
        task?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func stop() {
        finish()
    }

    func clear() {
        entries.removeAll()
        resultSummary = nil
    }
}
