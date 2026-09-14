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
        // 서버는 작업이 끝나기(done) 전까지 로그 큐를 보존하고, 아이폰↔서버 SOCKS 릴레이도
        // 끊김 시 계속 재시도하도록 되어 있음 — 로그 화면도 수집이 실제로 끝날 때까지는
        // 짧은 네트워크 끊김(와이파이/셀룰러 전환, 지하철/엘리베이터 등)에 포기하지 않고
        // 계속 재연결을 시도한다. (예전엔 6회/12초만 시도하고 포기해서, 실제로는 서버에서
        // 계속 진행 중인 작업을 화면에서 실패로 잘못 표시하는 문제가 있었음)
        let delay = min(2.0 * Double(min(reconnectAttempts, 5)), 15.0)
        append("연결이 잠시 끊겼습니다. 재연결 시도 중… (\(reconnectAttempts)번째)", tag: "dim")
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard self.isRunning, self.currentJobID == jobID else { return }
            self.connect(jobID: jobID)
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

    /// 사용자가 직접 "종료" 버튼을 눌렀을 때 — 서버에도 중단 신호를 보내고,
    /// 응답을 기다리지 않고 화면은 즉시 멈춘 것으로 표시한다.
    func cancelByUser() {
        guard isRunning, let jobID = currentJobID else { return }
        append("■ 종료 요청 중…", tag: "error")
        finish()
        Task {
            try? await APIClient.shared.cancelJob(jobID: jobID)
        }
    }

    func clear() {
        entries.removeAll()
        resultSummary = nil
    }
}
