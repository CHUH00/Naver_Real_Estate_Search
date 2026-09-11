import Foundation

enum APIError: LocalizedError {
    case badURL
    case server(String)
    case decode

    var errorDescription: String? {
        switch self {
        case .badURL: return "서버 주소가 올바르지 않습니다. 설정에서 확인해 주세요."
        case .server(let msg): return msg
        case .decode: return "서버 응답을 해석할 수 없습니다."
        }
    }
}

struct ScrapeJobResponse: Decodable { let job_id: String }
struct SessionResponse: Decodable { let session_id: String }
struct ExcelInfoResponse: Decodable { let rows: Int }
struct ExcelPreviewResponse: Decodable { let headers: [String]; let rows: [[String]]; let total: Int }

final class APIClient {
    static let shared = APIClient()
    private init() {}

    /// 예: https://your-tunnel.trycloudflare.com
    var baseURLString: String {
        get { UserDefaults.standard.string(forKey: "api_base_url") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "api_base_url") }
    }

    private func url(_ path: String, query: [String: String] = [:]) throws -> URL {
        let base = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.hasPrefix("http://") || base.hasPrefix("https://") else { throw APIError.badURL }
        guard var comps = URLComponents(string: base + path) else { throw APIError.badURL }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let u = comps.url else { throw APIError.badURL }
        return u
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["error"] as? String {
                throw APIError.server(msg)
            }
            throw APIError.server("서버 오류 (코드 \(http.statusCode))")
        }
        return data
    }

    private func postJSON(_ path: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    // MARK: - Session

    func newSession() async throws -> String {
        var req = URLRequest(url: try url("/api/session/new"))
        req.httpMethod = "POST"
        let data = try await send(req)
        return try JSONDecoder().decode(SessionResponse.self, from: data).session_id
    }

    func resetSession(_ sessionID: String) async throws {
        var req = URLRequest(url: try url("/api/session/reset", query: ["session_id": sessionID]))
        req.httpMethod = "POST"
        _ = try await send(req)
    }

    func excelInfo(_ sessionID: String) async throws -> Int {
        let req = URLRequest(url: try url("/api/excel/info", query: ["session_id": sessionID]))
        let data = try await send(req)
        return try JSONDecoder().decode(ExcelInfoResponse.self, from: data).rows
    }

    func excelPreview(_ sessionID: String, limit: Int = 500) async throws -> ExcelPreviewResponse {
        let req = URLRequest(url: try url("/api/excel/preview", query: ["session_id": sessionID, "limit": String(limit)]))
        let data = try await send(req)
        return try JSONDecoder().decode(ExcelPreviewResponse.self, from: data)
    }

    /// 엑셀 파일을 로컬 임시 경로로 다운로드하고 그 경로를 반환 (공유 시트에 사용).
    func downloadExcel(_ sessionID: String) async throws -> URL {
        let req = URLRequest(url: try url("/api/excel/download", query: ["session_id": sessionID]))
        let (tmp, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.server("다운로드 실패 (코드 \(http.statusCode))")
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("네이버_부동산_매물.xlsx")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    // MARK: - Scraping

    func scrapeRegion(sessionID: String, regions: [String], filters: ScrapeFilters) async throws -> String {
        let body: [String: Any] = [
            "session_id": sessionID,
            "regions": regions,
            "max_count": 500,
            "filters": filters.toPayload(),
        ]
        let data = try await postJSON("/api/scrape/region", body: body)
        return try JSONDecoder().decode(ScrapeJobResponse.self, from: data).job_id
    }

    func scrapeURLs(sessionID: String, urls: [String], filters: ScrapeFilters) async throws -> String {
        let body: [String: Any] = [
            "session_id": sessionID,
            "urls": urls,
            "filters": filters.toPayload(),
        ]
        let data = try await postJSON("/api/scrape/urls", body: body)
        return try JSONDecoder().decode(ScrapeJobResponse.self, from: data).job_id
    }

    /// http(s) base URL을 ws(s) 스킴으로 바꾼 웹소켓 URL.
    func websocketURL(jobID: String) -> URL? {
        guard var comps = URLComponents(string: baseURLString + "/ws/\(jobID)") else { return nil }
        if comps.scheme == "https" { comps.scheme = "wss" }
        else if comps.scheme == "http" { comps.scheme = "ws" }
        return comps.url
    }
}
