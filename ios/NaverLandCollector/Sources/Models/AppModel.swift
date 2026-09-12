import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var sessionID: String?
    @Published var listings: [Listing] = []
    @Published var rowCount: Int = 0
    @Published var errorMessage: String?
    @Published var isLoadingListings = false

    let logger = WebSocketLogger()

    func ensureSession() async {
        guard sessionID == nil else { return }
        do {
            let sid = try await APIClient.shared.newSession()
            sessionID = sid
            RelayClient.shared.start(sessionID: sid)
        } catch APIError.badURL {
            // 서버 주소를 아직 설정하지 않은 상태 — 설정 탭에서 입력할 때까지 조용히 기다린다.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 설정 탭에서 서버 주소를 바꿨을 때 호출 — 기존 릴레이 연결을 끊고 새 세션으로 다시 연결.
    func restartSession() async {
        RelayClient.shared.stop()
        sessionID = nil
        listings = []
        rowCount = 0
        await ensureSession()
    }

    func runRegionScrape(regions: [String], filters: ScrapeFilters) async {
        await ensureSession()
        guard let sid = sessionID else { return }
        logger.clear()
        do {
            let jobID = try await APIClient.shared.scrapeRegion(sessionID: sid, regions: regions, filters: filters)
            logger.start(jobID: jobID)
            await waitAndRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runURLScrape(urls: [String], filters: ScrapeFilters) async {
        await ensureSession()
        guard let sid = sessionID else { return }
        logger.clear()
        do {
            let jobID = try await APIClient.shared.scrapeURLs(sessionID: sid, urls: urls, filters: filters)
            logger.start(jobID: jobID)
            await waitAndRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 완료(isRunning == false)될 때까지 짧게 폴링한 뒤 목록을 새로고침.
    private func waitAndRefresh() async {
        while logger.isRunning {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        await refreshListings()
    }

    func refreshListings() async {
        guard let sid = sessionID else { return }
        isLoadingListings = true
        defer { isLoadingListings = false }
        do {
            let preview = try await APIClient.shared.excelPreview(sid)
            listings = preview.rows.enumerated().map { Listing(id: $0.offset, headers: preview.headers, row: $0.element) }
            rowCount = preview.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetSession() async {
        guard let sid = sessionID else { return }
        do {
            try await APIClient.shared.resetSession(sid)
            listings = []
            rowCount = 0
            logger.clear()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
