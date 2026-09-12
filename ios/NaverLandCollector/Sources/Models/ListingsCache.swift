import Foundation

/// 서버(Render 무료 플랜)가 유휴 상태에서 재시작되며 데이터를 잃는 경우를 대비해,
/// 마지막으로 확인된 매물 목록을 기기에 그대로 캐시해둔다.
enum ListingsCache {
    private struct CachePayload: Codable {
        let headers: [String]
        let rows: [[String]]
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("listings_cache.json")
    }

    static func save(headers: [String], rows: [[String]]) {
        let payload = CachePayload(headers: headers, rows: rows)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> (headers: [String], listings: [Listing]) {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return ([], []) }
        let listings = payload.rows.enumerated().map { Listing(id: $0.offset, headers: payload.headers, row: $0.element) }
        return (payload.headers, listings)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
