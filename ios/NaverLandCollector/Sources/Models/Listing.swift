import Foundation

/// /api/excel/preview 가 돌려주는 headers+rows 한 줄을 헤더명으로 접근 가능한 형태로 감싼다.
struct Listing: Identifiable {
    let id: Int
    let fields: [String: String]

    init(id: Int, headers: [String], row: [String]) {
        self.id = id
        var dict: [String: String] = [:]
        for (i, header) in headers.enumerated() where i < row.count {
            dict[header] = row[i]
        }
        self.fields = dict
    }

    subscript(_ header: String) -> String {
        fields[header] ?? ""
    }

    var complexName: String { self["단지명"].isEmpty ? "이름 없음" : self["단지명"] }
    var address: String { self["주소"] }
    var priceMain: String { self["매매가 (만원)"] }
    var rentPrice: String { self["기보증금"] }
    var areaExclusive: String { self["전용면적 (평)"] }
    var direction: String { self["방향"] }
    var floor: String { self["해당층/총층"] }
    var moveInDate: String { self["입주가능일"] }
    var feature: String { self["매물특징"] }
    var url: String { self["URL"] }
    var dealer: String { self["중개사"] }
    var maintenance: String { self["관리비 (만원)"] }

    /// "80,000" 같은 만원 문자열을 "8억" 형태로 보기 좋게 변환.
    static func formatWon(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        guard let man = Double(cleaned), man > 0 else { return raw.isEmpty ? "-" : raw }
        let eok = Int(man) / 10000
        let rest = Int(man) % 10000
        if eok == 0 { return "\(Int(man))만" }
        if rest == 0 { return "\(eok)억" }
        return "\(eok)억 \(rest)만"
    }
}
