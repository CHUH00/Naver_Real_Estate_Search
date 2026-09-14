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
                VStack(alignment: .leading, spacing: 28) {
                    header
                    modeSwitcher

                    if mode == 0 { regionCards } else { urlCard }

                    filterCard
                    startButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("전세안고 매매")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text("어떤 매물을\n찾아드릴까요?")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(2)
                }
                Spacer()
            }
            relayBadge
        }
    }

    private var relayBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(relay.isConnected ? Theme.success : Theme.error)
                .frame(width: 7, height: 7)
            Text(relay.isConnected ? "중계 연결됨" : "중계 연결 안 됨")
                .font(.caption.weight(.semibold))
                .foregroundStyle(relay.isConnected ? Theme.success : Theme.error)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background((relay.isConnected ? Theme.success : Theme.error).opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Mode switcher

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            modeButton("지역 일괄 검색", tag: 0)
            modeButton("URL 직접 입력", tag: 1)
        }
        .padding(4)
        .background(Color(red: 0.902, green: 0.914, blue: 0.933))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func modeButton(_ title: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { mode = tag }
        } label: {
            Text(title)
                .font(.subheadline.weight(mode == tag ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(mode == tag ? Theme.textPrimary : Theme.textFaint)
                .background(mode == tag ? Theme.surface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .shadow(color: mode == tag ? .black.opacity(0.06) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Region mode

    private var regionCards: some View {
        VStack(spacing: 12) {
            Card {
                SectionHeader("building.2", "서울 구 선택", subtitle: selectedGu.isEmpty ? nil : "\(selectedGu.count)개 선택됨") {
                    HStack(spacing: 10) {
                        Button("전체") { selectAllGu() }
                        Button("해제") { deselectAll() }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.bottom, 14)

                FlowChips(RegionData.seoulRegions) { gu in
                    ChipButton(gu, isSelected: selectedGu.contains(gu)) { toggleGu(gu) }
                }
            }

            if !dongOptions.isEmpty {
                Card {
                    SectionHeader("mappin.and.ellipse", "동 선택", subtitle: "선택하면 동 단위로 검색")
                        .padding(.bottom, 14)
                    FlowChips(dongOptions) { dong in
                        ChipButton(dong, isSelected: selectedDong.contains(dong), color: Theme.accent) {
                            if selectedDong.contains(dong) { selectedDong.remove(dong) }
                            else { selectedDong.insert(dong) }
                        }
                    }
                }
            }

            Card {
                SectionHeader("keyboard", "직접 입력")
                    .padding(.bottom, 12)
                TextField("예: 용두동, 강남구", text: $manualRegion)
                    .textFieldStyle(BoxedTextFieldStyle())
            }
        }
    }

    private var urlCard: some View {
        Card {
            SectionHeader("link", "네이버 부동산 매물 URL", subtitle: "여러 개는 줄바꿈으로 구분")
                .padding(.bottom, 12)
            TextEditor(text: $urlText)
                .frame(minHeight: 130)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .tint(Theme.accent)
                .padding(12)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

            Button {
                if let s = UIPasteboard.general.string {
                    urlText = urlText.isEmpty ? s : urlText + "\n" + s
                }
            } label: {
                Label("클립보드 붙여넣기", systemImage: "doc.on.clipboard")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.top, 12)
        }
    }

    // MARK: - Filter

    private var filterCard: some View {
        Card {
            Button { showFilters = true } label: {
                SectionHeader("slider.horizontal.3", "필터", subtitle: filterSummary) {
                    HStack(spacing: 10) {
                        if !filters.isEmpty {
                            Button {
                                withAnimation { filters = ScrapeFilters() }
                            } label: {
                                Text("초기화")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.error)
                            }
                            .buttonStyle(.plain)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
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
                    ProgressView().tint(.white)
                    Text("수집 중…")
                }
            } else {
                Text("수집 시작")
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: canStart && !isStarting && !model.logger.isRunning))
        .disabled(isStarting || model.logger.isRunning || !canStart)
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
