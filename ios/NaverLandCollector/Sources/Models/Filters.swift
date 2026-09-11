import Foundation

struct ScrapeFilters {
    var priceMin: String = ""   // 억 단위
    var priceMax: String = ""
    var areaMin: String = ""    // 평 단위
    var areaMax: String = ""
    var directions: Set<String> = []
    var floors: Set<String> = []
    var householdMin: String = ""

    static let directionOptions = ["남향", "남동향", "남서향", "동향", "서향", "북향", "북동향", "북서향"]
    static let floorOptions = ["저층", "중층", "고층"]

    var isEmpty: Bool {
        priceMin.isEmpty && priceMax.isEmpty && areaMin.isEmpty && areaMax.isEmpty
            && directions.isEmpty && floors.isEmpty && householdMin.isEmpty
    }

    /// 백엔드 /api/scrape/* 의 filters 필드로 보낼 JSON 딕셔너리.
    /// price는 억 → 만원으로 환산.
    func toPayload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let v = Double(priceMin) { payload["price_min"] = v * 10000 }
        if let v = Double(priceMax) { payload["price_max"] = v * 10000 }
        if let v = Double(areaMin) { payload["area_min"] = v }
        if let v = Double(areaMax) { payload["area_max"] = v }
        if !directions.isEmpty { payload["directions"] = Array(directions) }
        if !floors.isEmpty { payload["floors"] = Array(floors) }
        if let v = Int(householdMin) { payload["household_min"] = v }
        return payload
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let tag: String
}
