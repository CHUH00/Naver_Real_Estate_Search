import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var sessionID: String?
    @Published var listings: [Listing] = []
    @Published var rowCount: Int = 0
    @Published var errorMessage: String?
    @Published var isLoadingListings = false

    let logger = WebSocketLogger()

    init() {
        // 서버 응답을 기다리지 않고, 기기에 저장된 마지막 매물 목록을 바로 보여준다.
        let cached = ListingsCache.load()
        if !cached.listings.isEmpty {
            listings = cached.listings
            rowCount = cached.listings.count
        }
    }

    private var sessionKey: String { "session_id::" + APIClient.shared.baseURLString }

    func ensureSession() async {
        guard sessionID == nil else { return }

        if let saved = UserDefaults.standard.string(forKey: sessionKey), !saved.isEmpty {
            sessionID = saved
            RelayClient.shared.start(sessionID: saved)
            return
        }

        do {
            let sid = try await APIClient.shared.newSession()
            sessionID = sid
            UserDefaults.standard.set(sid, forKey: sessionKey)
            RelayClient.shared.start(sessionID: sid)
        } catch APIError.badURL {
            // 서버 주소를 아직 설정하지 않은 상태 — 설정 탭에서 입력할 때까지 조용히 기다린다.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 설정 탭에서 서버 주소를 바꿨을 때 호출 — 기존 릴레이 연결을 끊고 새(또는 저장된) 세션으로 다시 연결.
    func restartSession() async {
        RelayClient.shared.stop()
        sessionID = nil
        await ensureSession()
        await refreshListings()
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

    /// 서버 목록을 새로고침한다. 서버가 (재시작 등으로) 빈 목록을 돌려주더라도
    /// 이미 화면/기기에 있는 목록은 사용자가 직접 지우기 전까지 그대로 유지한다.
    func refreshListings() async {
        guard let sid = sessionID else { return }
        isLoadingListings = true
        defer { isLoadingListings = false }
        do {
            let preview = try await APIClient.shared.excelPreview(sid)
            if preview.rows.isEmpty && !listings.isEmpty {
                // 서버 쪽 데이터가 사라진 것으로 보임 (Render 재시작 등) — 기기 캐시를 그대로 유지.
                return
            }
            listings = preview.rows.enumerated().map { Listing(id: $0.offset, headers: preview.headers, row: $0.element) }
            rowCount = preview.total
            ListingsCache.save(headers: preview.headers, rows: preview.rows)
        } catch {
            errorMessage = error.localizedDescription
            // 네트워크 오류 시에도 기존(캐시) 목록은 그대로 둔다.
        }
    }

    /// 매물 탭에서 체크한 매물만 골라서 삭제.
    func deleteListings(articleNos: Set<String>) async {
        guard !articleNos.isEmpty else { return }
        listings.removeAll { articleNos.contains($0.articleNo) }
        rowCount = listings.count
        persistCache()
        guard let sid = sessionID else { return }
        do {
            try await APIClient.shared.deleteListings(sessionID: sid, articleNos: Array(articleNos))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistCache() {
        guard let first = listings.first else {
            ListingsCache.clear()
            return
        }
        let headers = Array(first.fields.keys)
        // Listing은 [String: String] dict라 원래 헤더 순서를 모른다 — 헤더/값을 짝지어 그대로 저장.
        let rows = listings.map { listing in headers.map { listing[$0] } }
        ListingsCache.save(headers: headers, rows: rows)
    }

    /// 매물 탭의 "지우기" — 서버와 기기 캐시 양쪽에서 모두 삭제.
    func clearAllListings() async {
        listings = []
        rowCount = 0
        ListingsCache.clear()
        guard let sid = sessionID else { return }
        do {
            try await APIClient.shared.resetSession(sid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetSession() async {
        await clearAllListings()
        logger.clear()
    }
}
