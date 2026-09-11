import Foundation

@MainActor
final class WebSocketLogger: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isRunning = false
    @Published var resultSummary: String?

    private var task: URLSessionWebSocketTask?

    func start(jobID: String) {
        guard let url = APIClient.shared.websocketURL(jobID: jobID) else {
            append("웹소켓 주소를 만들 수 없습니다.", tag: "error")
            return
        }
        isRunning = true
        resultSummary = nil
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let error):
                    self.append("연결 끊김: \(error.localizedDescription)", tag: "error")
                    self.isRunning = false
                case .success(let message):
                    self.handle(message)
                    if self.isRunning {
                        self.listen()
                    }
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

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
            isRunning = false
            task?.cancel()
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

    func stop() {
        task?.cancel()
        isRunning = false
    }

    func clear() {
        entries.removeAll()
        resultSummary = nil
    }
}
