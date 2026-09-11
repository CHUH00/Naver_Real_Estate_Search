import SwiftUI

struct SearchView: View {
    @ObservedObject var model: AppModel
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
                            Text("필터")
                            Spacer()
                            Text(filters.isEmpty ? "제한 없음" : "설정됨")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        HStack {
                            Spacer()
                            if isStarting || model.logger.isRunning {
                                ProgressView()
                            } else {
                                Text("수집 시작").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(isStarting || model.logger.isRunning || !canStart)
                }
            }
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
            Section("서울 구 선택") {
                FlowChips(RegionData.seoulRegions) { gu in
                    ChipButton(gu, isSelected: selectedGu.contains(gu)) {
                        toggleGu(gu)
                    }
                }
                .padding(.vertical, 4)
            }

            if !dongOptions.isEmpty {
                Section("동 선택 (선택 시 동 단위로 검색)") {
                    FlowChips(dongOptions) { dong in
                        ChipButton(dong, isSelected: selectedDong.contains(dong), color: .blue) {
                            if selectedDong.contains(dong) { selectedDong.remove(dong) }
                            else { selectedDong.insert(dong) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("또는 직접 입력") {
                TextField("예: 용두동, 강남구", text: $manualRegion)
            }
        }
    }

    private var urlSection: some View {
        Section("네이버 부동산 매물 URL (줄바꿈으로 구분)") {
            TextEditor(text: $urlText)
                .frame(minHeight: 140)
                .font(.system(.footnote, design: .monospaced))
            Button("클립보드 붙여넣기") {
                if let s = UIPasteboard.general.string {
                    urlText = urlText.isEmpty ? s : urlText + "\n" + s
                }
            }
        }
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
