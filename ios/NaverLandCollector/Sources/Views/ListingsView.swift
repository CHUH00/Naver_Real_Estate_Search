import SwiftUI

struct ListingsView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var showClearConfirm = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var showDeleteSelectedConfirm = false

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
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { listing in
                                if isSelecting {
                                    Button {
                                        toggleSelection(listing.id)
                                    } label: {
                                        ListingRow(listing: listing, isSelecting: true, isSelected: selectedIDs.contains(listing.id))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink(value: listing.id) {
                                        ListingRow(listing: listing, isSelecting: false, isSelected: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, isSelecting ? 70 : 0)
                    }
                    .searchable(text: $searchText, prompt: "단지명 또는 주소 검색")
                    .refreshable { await model.refreshListings() }
                }
            }
            .background(Theme.background)
            .navigationTitle("매물 \(model.rowCount)건")
            .navigationDestination(for: Int.self) { id in
                if let listing = model.listings.first(where: { $0.id == id }) {
                    ListingDetailView(listing: listing)
                }
            }
            .toolbar {
                if !model.listings.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelecting ? "완료" : "선택") {
                            withAnimation {
                                isSelecting.toggle()
                                selectedIDs.removeAll()
                            }
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
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
                    .tint(Theme.accent)
                }
                if !model.listings.isEmpty && !isSelecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("지우기") { showClearConfirm = true }
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isSelecting && !selectedIDs.isEmpty {
                    deleteSelectedBar
                }
            }
            .task { await model.refreshListings() }
            .confirmationDialog("저장된 매물을 전부 지울까요?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("전부 지우기", role: .destructive) {
                    Task { await model.clearAllListings() }
                }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("선택한 \(selectedIDs.count)건을 삭제할까요?", isPresented: $showDeleteSelectedConfirm, titleVisibility: .visible) {
                Button("\(selectedIDs.count)건 삭제", role: .destructive) {
                    let nos = Set(model.listings.filter { selectedIDs.contains($0.id) }.map { $0.articleNo })
                    Task { await model.deleteListings(articleNos: nos) }
                    isSelecting = false
                    selectedIDs.removeAll()
                }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private func toggleSelection(_ id: Int) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private var deleteSelectedBar: some View {
        Button {
            showDeleteSelectedConfirm = true
        } label: {
            Label("\(selectedIDs.count)건 삭제", systemImage: "trash.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.error)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .shadow(color: Theme.error.opacity(0.35), radius: 10, y: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "tray")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            Text("저장된 매물이 없습니다")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("검색 탭에서 지역 또는 URL로\n매물을 수집해 보세요.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

private struct ListingRow: View {
    let listing: Listing
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textFaint)
                    .padding(.top, 2)
            }
            content
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(listing.complexName)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !listing.address.isEmpty {
                        Text(listing.address)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(Listing.formatWon(listing.priceMain))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }

            if !specs.isEmpty {
                HStack(spacing: 8) {
                    ForEach(specs, id: \.self) { spec in
                        Text(spec)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.background)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    private var specs: [String] {
        var s: [String] = []
        if !listing.areaExclusive.isEmpty { s.append(listing.areaExclusive) }
        if !listing.floor.isEmpty { s.append(listing.floor) }
        if !listing.direction.isEmpty { s.append(listing.direction) }
        return s
    }
}

struct ListingDetailView: View {
    let listing: Listing

    private let specItems: [(icon: String, key: String, label: String)] = [
        ("square.dashed", "전용면적 (평)", "전용면적"),
        ("location.north", "방향", "방향"),
        ("building", "해당층/총층", "해당층"),
        ("calendar", "입주가능일", "입주가능일"),
        ("banknote", "기보증금", "기보증금"),
        ("creditcard", "관리비 (만원)", "관리비"),
    ]

    private let extraItems: [String] = [
        "거래유형", "공급면적 (평)", "단지세대수/동세대수", "총주차대수 (대)",
        "방수/화장실수 (개)", "현관구조", "난방 (방식/연료)", "건축물 용도",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard

                if !listing.feature.isEmpty {
                    Card {
                        SectionHeader("text.quote", "매물특징").padding(.bottom, 8)
                        Text(listing.feature)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                Card {
                    SectionHeader("info.circle", "상세 정보").padding(.bottom, 10)
                    VStack(spacing: 0) {
                        ForEach(Array(extraItems.enumerated()), id: \.offset) { i, key in
                            let value = listing[key]
                            if !value.isEmpty {
                                detailRow(key, value)
                                if i < extraItems.count - 1 { Divider().overlay(Theme.border) }
                            }
                        }
                    }
                }

                if !listing.dealer.isEmpty {
                    Card {
                        SectionHeader("person.crop.circle", "중개사").padding(.bottom, 8)
                        Text(listing.dealer)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if let url = URL(string: listing.url), !listing.url.isEmpty {
                    Link(destination: url) {
                        Label("네이버 부동산에서 보기", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(listing.complexName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(listing.complexName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if !listing.address.isEmpty {
                    Text(listing.address)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(Listing.formatWon(listing.priceMain))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(specItems, id: \.key) { item in
                        let value = listing[item.key]
                        if !value.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.label)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textFaint)
                                    Text(value)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.background)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
