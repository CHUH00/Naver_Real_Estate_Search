import SwiftUI

struct FilterSheet: View {
    @Binding var filters: ScrapeFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("매매가 (억 원)") {
                    HStack {
                        TextField("최소", text: $filters.priceMin).keyboardType(.decimalPad)
                        Text("~")
                        TextField("최대", text: $filters.priceMax).keyboardType(.decimalPad)
                    }
                }
                Section("전용면적 (평)") {
                    HStack {
                        TextField("최소", text: $filters.areaMin).keyboardType(.decimalPad)
                        Text("~")
                        TextField("최대", text: $filters.areaMax).keyboardType(.decimalPad)
                    }
                }
                Section("방향") {
                    FlowChips(ScrapeFilters.directionOptions) { d in
                        ChipButton(d, isSelected: filters.directions.contains(d), color: .blue) {
                            if filters.directions.contains(d) { filters.directions.remove(d) }
                            else { filters.directions.insert(d) }
                        }
                    }
                }
                Section("해당층") {
                    FlowChips(ScrapeFilters.floorOptions) { f in
                        ChipButton(f, isSelected: filters.floors.contains(f), color: .green) {
                            if filters.floors.contains(f) { filters.floors.remove(f) }
                            else { filters.floors.insert(f) }
                        }
                    }
                }
                Section("단지 세대수") {
                    TextField("최소 세대수", text: $filters.householdMin).keyboardType(.numberPad)
                }
                Section {
                    Button("필터 초기화", role: .destructive) {
                        filters = ScrapeFilters()
                    }
                }
            }
            .navigationTitle("필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
