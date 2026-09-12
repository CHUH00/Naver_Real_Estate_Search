import SwiftUI

struct FilterSheet: View {
    @Binding var filters: ScrapeFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("최소", text: $filters.priceMin).keyboardType(.decimalPad)
                        Text("~").foregroundStyle(Theme.textSecondary)
                        TextField("최대", text: $filters.priceMax).keyboardType(.decimalPad)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("매매가 (억 원)").foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    HStack {
                        TextField("최소", text: $filters.areaMin).keyboardType(.decimalPad)
                        Text("~").foregroundStyle(Theme.textSecondary)
                        TextField("최대", text: $filters.areaMax).keyboardType(.decimalPad)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("전용면적 (평)").foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    FlowChips(ScrapeFilters.directionOptions) { d in
                        ChipButton(d, isSelected: filters.directions.contains(d), color: Theme.info) {
                            if filters.directions.contains(d) { filters.directions.remove(d) }
                            else { filters.directions.insert(d) }
                        }
                    }
                } header: {
                    Text("방향").foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    FlowChips(ScrapeFilters.floorOptions) { f in
                        ChipButton(f, isSelected: filters.floors.contains(f), color: Theme.success) {
                            if filters.floors.contains(f) { filters.floors.remove(f) }
                            else { filters.floors.insert(f) }
                        }
                    }
                } header: {
                    Text("해당층").foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("최소 세대수", text: $filters.householdMin)
                        .keyboardType(.numberPad)
                        .tint(Theme.accent)
                } header: {
                    Text("단지 세대수").foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button("필터 초기화", role: .destructive) {
                        filters = ScrapeFilters()
                    }
                    .foregroundStyle(Theme.error)
                }
                .listRowBackground(Theme.surface)
            }
            .themedListBackground()
            .navigationTitle("필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
