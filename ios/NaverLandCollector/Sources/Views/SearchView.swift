import SwiftUI

struct SearchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var relay = RelayClient.shared
    var onStarted: () -> Void

    @State private var mode = 0 // 0: 지역, 1: URL
    @State private var selectedGu: Set<String> = []
    @State private var selectedDong: Set<String> = []
    @State private var manualRegion = ""
    @State private var urlText = ""
    @State private var filters = ScrapeFilters()
    @State private var showFilters = false
    @State private var isStarting = false

    private var dongOptions: [String] {
        RegionData.seoulRegions
            .filter { selectedGu.contains($0) }
            .flatMap { RegionData.seoulDong[$0] ?? [] }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    relayBanner
                    modeSwitcher

                    if mode == 0 { regionCards } else { urlCard }

                    filterCard
                    startButton
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showFilters) {
                FilterSheet(filters: $filters)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NAVER LAND")
                .font(.caption2.weight(.bold))
                .tracking(2)
                .foregroundStyle(Theme.textFaint)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("매물 수집기")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("전세안고 매매")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.top, 4)
    }

    private var relayBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(relay.isConnected ? Theme.success : Theme.error)
                .frame(width: 8, height: 8)
            Text(relay.isConnected ? "중계 연결됨 — 수집 준비 완료" : "중계 연결 안 됨 — 설정에서 확인해 주세요")
                .font(.caption.weight(.medium))
                .foregroundStyle(relay.isConnected ? Theme.success : Theme.error)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((relay.isConnected ? Theme.success : Theme.error).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    // MARK: - Mode switcher

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            modeButton("지역 일괄 검색", tag: 0)
            modeButton("URL 직접 입력", tag: 1)
        }
        .padding(4)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func modeButton(_ title: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { mode = tag }
        } label: {
            Text(title)
                .font(.subheadline.weight(mode == tag ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(mode == tag ? Theme.background : Theme.textSecondary)
                .background(mode == tag ? Theme.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Region mode

    private var regionCards: some View {
        VStack(spacing: 16) {
            Card {
                SectionHeader("building.2", "서울 구 선택", subtitle: selectedGu.isEmpty ? nil : "\(selectedGu.count)개 선택됨") {
                    HStack(spacing: 10) {
                        Button("전체 선택") { selectAllGu() }
                        Button("해제") { deselectAll() }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.bottom, 12)

                FlowChips(RegionData.seoulRegions) { gu in
                    ChipButton(gu, isSelected: selectedGu.contains(gu)) { toggleGu(gu) }
                }
            }

            if !dongOptions.isEmpty {
                Card {
                    SectionHeader("mappin.and.ellipse", "동 선택", subtitle: "선택하면 동 단위로 검색")
                        .padding(.bottom, 12)
                    FlowChips(dongOptions) { dong in
                        ChipButton(dong, isSelected: selectedDong.contains(dong), color: Theme.info) {
                            if selectedDong.contains(dong) { selectedDong.remove(dong) }
                            else { selectedDong.insert(dong) }
                        }
                    }
                }
            }

            Card {
                SectionHeader("keyboard", "직접 입력")
                    .padding(.bottom, 10)
                TextField("예: 용두동, 강남구", text: $manualRegion)
                    .textFieldStyle(BoxedTextFieldStyle())
            }
        }
    }

    private var urlCard: some View {
        Card {
            SectionHeader("link", "네이버 부동산 매물 URL", subtitle: "여러 개는 줄바꿈으로 구분")
                .padding(.bottom, 10)
            TextEditor(text: $urlText)
                .frame(minHeight: 130)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .tint(Theme.accent)
                .padding(10)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

            Button {
                if let s = UIPasteboard.general.string {
                    urlText = urlText.isEmpty ? s : urlText + "\n" + s
                }
            } label: {
                Label("클립보드 붙여넣기", systemImage: "doc.on.clipboard")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.top, 10)
        }
    }

    // MARK: - Filter

    private var filterCard: some View {
        Card {
            Button { showFilters = true } label: {
                SectionHeader("slider.horizontal.3", "필터", subtitle: filterSummary) {
                    HStack(spacing: 8) {
                        if !filters.isEmpty {
                            Button {
                                filters = ScrapeFilters()
                            } label: {
                                Text("초기화")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.error)
                            }
                            .buttonStyle(.plain)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var filterSummary: String {
        if filters.isEmpty { return "제한 없음" }
        var parts: [String] = []
        if !filters.priceMin.isEmpty || !filters.priceMax.isEmpty {
            parts.append("매매가 \(filters.priceMin.isEmpty ? "0" : filters.priceMin)~\(filters.priceMax.isEmpty ? "∞" : filters.priceMax)억")
        }
        if !filters.areaMin.isEmpty || !filters.areaMax.isEmpty { parts.append("면적") }
        if !filters.directions.isEmpty { parts.append("방향 \(filters.directions.count)") }
        if !filters.floors.isEmpty { parts.append("층 \(filters.floors.count)") }
        if !filters.householdMin.isEmpty { parts.append("세대수") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Start button

    private var startButton: some View {
        Button {
            Task { await start() }
        } label: {
            if isStarting || model.logger.isRunning {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.background)
                    Text("수집 중…")
                }
            } else {
                Label("수집 시작", systemImage: "arrow.down.circle.fill")
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: canStart && !isStarting && !model.logger.isRunning))
        .disabled(isStarting || model.logger.isRunning || !canStart)
        .padding(.top, 4)
    }

    private var canStart: Bool {
        if mode == 0 {
            return !selectedGu.isEmpty || !selectedDong.isEmpty || !manualRegion.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func selectAllGu() {
        selectedGu = Set(RegionData.seoulRegions)
    }

    private func deselectAll() {
        selectedGu.removeAll()
        selectedDong.removeAll()
    }

    private func toggleGu(_ gu: String) {
        if selectedGu.contains(gu) {
            selectedGu.remove(gu)
            for dong in RegionData.seoulDong[gu] ?? [] { selectedDong.remove(dong) }
        } else {
            selectedGu.insert(gu)
        }
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        onStarted()
        if mode == 0 {
            let regions: [String]
            if !selectedDong.isEmpty {
                regions = Array(selectedDong).sorted()
            } else if !selectedGu.isEmpty {
                regions = Array(selectedGu).sorted()
            } else {
                regions = [manualRegion.trimmingCharacters(in: .whitespaces)]
            }
            await model.runRegionScrape(regions: regions, filters: filters)
        } else {
            let urls = urlText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            await model.runURLScrape(urls: urls, filters: filters)
        }
    }
}
