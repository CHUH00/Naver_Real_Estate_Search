import SwiftUI

struct ListingsView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    private var filtered: [Listing] {
        guard !searchText.isEmpty else { return model.listings }
        return model.listings.filter {
            $0.complexName.localizedCaseInsensitiveContains(searchText)
                || $0.address.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.listings.isEmpty {
                    ContentUnavailableCompat(
                        title: "저장된 매물이 없습니다",
                        message: "검색 탭에서 지역 또는 URL로 매물을 수집해 보세요."
                    )
                } else {
                    List {
                        ForEach(filtered) { listing in
                            NavigationLink(value: listing.id) {
                                ListingRow(listing: listing)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "단지명 또는 주소 검색")
                    .refreshable { await model.refreshListings() }
                }
            }
            .navigationTitle("매물 (\(model.rowCount))")
            .navigationDestination(for: Int.self) { id in
                if let listing = model.listings.first(where: { $0.id == id }) {
                    ListingDetailView(listing: listing)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshListings() }
                    } label: {
                        if model.isLoadingListings {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task { await model.refreshListings() }
        }
    }
}

private struct ListingRow: View {
    let listing: Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(listing.complexName).font(.headline)
                Spacer()
                Text(Listing.formatWon(listing.priceMain))
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            if !listing.address.isEmpty {
                Text(listing.address).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if !listing.areaExclusive.isEmpty {
                    Label("\(listing.areaExclusive)평", systemImage: "square.dashed")
                }
                if !listing.floor.isEmpty {
                    Label(listing.floor, systemImage: "building")
                }
                if !listing.direction.isEmpty {
                    Label(listing.direction, systemImage: "location.north")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ListingDetailView: View {
    let listing: Listing

    private let displayOrder: [String] = [
        "단지명", "주소", "거래유형", "매매가 (만원)", "기보증금", "입주가능일",
        "공급면적 (평)", "전용면적 (평)", "방향", "단지세대수/동세대수",
        "총주차대수 (대)", "방수/화장실수 (개)", "해당층/총층", "현관구조",
        "난방 (방식/연료)", "관리비 (만원)", "건축물 용도", "매물특징", "중개사",
    ]

    var body: some View {
        List {
            ForEach(displayOrder, id: \.self) { key in
                let value = listing[key]
                if !value.isEmpty {
                    HStack(alignment: .top) {
                        Text(key).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                        Text(value)
                        Spacer()
                    }
                    .font(.subheadline)
                }
            }
            if let url = URL(string: listing.url), !listing.url.isEmpty {
                Link(destination: url) {
                    Label("네이버 부동산에서 보기", systemImage: "safari")
                }
            }
        }
        .navigationTitle(listing.complexName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// iOS 16 미만도 지원하기 위한 ContentUnavailableView 대체.
struct ContentUnavailableCompat: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
