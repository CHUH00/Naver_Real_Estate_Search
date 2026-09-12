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
            Form {
                Section {
                    Picker("검색 방식", selection: $mode) {
                        Text("지역 일괄 검색").tag(0)
                        Text("URL 직접 입력").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Theme.surface)

                if mode == 0 {
                    regionSection
                } else {
                    urlSection
                }

                Section {
                    Button {
                        showFilters = true
                    } label: {
                        HStack {
                            Label("필터", systemImage: "slider.horizontal.3")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(filters.isEmpty ? "제한 없음" : "설정됨")
                                .foregroundStyle(filters.isEmpty ? Theme.textSecondary : Theme.accent)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        HStack {
                            Spacer()
                            if isStarting || model.logger.isRunning {
                                ProgressView().tint(Theme.background)
                            } else {
                                Text("수집 시작").font(.headline)
                            }
                            Spacer()
                        }
                        .foregroundStyle(Theme.background)
                        .padding(.vertical, 4)
                    }
                    .disabled(isStarting || model.logger.isRunning || !canStart)
                    .listRowBackground(
                        (isStarting || model.logger.isRunning || !canStart)
                            ? Theme.accent.opacity(0.4) : Theme.accent
                    )
                }

                if !relay.isConnected {
                    Section {
                        Label("중계 연결 안 됨 — 설정 탭에서 확인해 주세요", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.error)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedListBackground()
            .navigationTitle("매물 수집기")
            .sheet(isPresented: $showFilters) {
                FilterSheet(filters: $filters)
            }
        }
    }

    private var canStart: Bool {
        if mode == 0 {
            return !selectedGu.isEmpty || !selectedDong.isEmpty || !manualRegion.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var regionSection: some View {
        Group {
            Section {
                FlowChips(RegionData.seoulRegions) { gu in
                    ChipButton(gu, isSelected: selectedGu.contains(gu)) {
                        toggleGu(gu)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("서울 구 선택").foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)

            if !dongOptions.isEmpty {
                Section {
                    FlowChips(dongOptions) { dong in
                        ChipButton(dong, isSelected: selectedDong.contains(dong), color: Theme.info) {
                            if selectedDong.contains(dong) { selectedDong.remove(dong) }
                            else { selectedDong.insert(dong) }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("동 선택 (선택 시 동 단위로 검색)").foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                TextField("예: 용두동, 강남구", text: $manualRegion)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.textPrimary)
            } header: {
                Text("또는 직접 입력").foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)
        }
    }

    private var urlSection: some View {
        Section {
            TextEditor(text: $urlText)
                .frame(minHeight: 140)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .tint(Theme.accent)
            Button("클립보드 붙여넣기") {
                if let s = UIPasteboard.general.string {
                    urlText = urlText.isEmpty ? s : urlText + "\n" + s
                }
            }
            .foregroundStyle(Theme.accent)
        } header: {
            Text("네이버 부동산 매물 URL (줄바꿈으로 구분)").foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surface)
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
