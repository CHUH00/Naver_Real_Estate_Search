import SwiftUI

struct FilterSheet: View {
    @Binding var filters: ScrapeFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        SectionHeader("wonsign.circle", "매매가", subtitle: "억 원 단위")
                            .padding(.bottom, 12)
                        rangeRow(min: $filters.priceMin, max: $filters.priceMax, unit: "억")
                    }

                    Card {
                        SectionHeader("square.dashed", "전용면적", subtitle: "평 단위")
                            .padding(.bottom, 12)
                        rangeRow(min: $filters.areaMin, max: $filters.areaMax, unit: "평")
                    }

                    Card {
                        SectionHeader("location.north.circle", "방향")
                            .padding(.bottom, 12)
                        FlowChips(ScrapeFilters.directionOptions) { d in
                            ChipButton(d, isSelected: filters.directions.contains(d), color: Theme.info) {
                                if filters.directions.contains(d) { filters.directions.remove(d) }
                                else { filters.directions.insert(d) }
                            }
                        }
                    }

                    Card {
                        SectionHeader("building.2.crop.circle", "해당층")
                            .padding(.bottom, 12)
                        FlowChips(ScrapeFilters.floorOptions) { f in
                            ChipButton(f, isSelected: filters.floors.contains(f), color: Theme.success) {
                                if filters.floors.contains(f) { filters.floors.remove(f) }
                                else { filters.floors.insert(f) }
                            }
                        }
                    }

                    Card {
                        SectionHeader("person.3", "단지 세대수", subtitle: "최소 세대수")
                            .padding(.bottom, 12)
                        TextField("예: 300", text: $filters.householdMin)
                            .textFieldStyle(BoxedTextFieldStyle())
                            .keyboardType(.numberPad)
                    }

                    Button(role: .destructive) {
                        withAnimation { filters = ScrapeFilters() }
                    } label: {
                        Label("필터 초기화", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .foregroundStyle(Theme.error)
                    .background(Theme.error.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func rangeRow(min: Binding<String>, max: Binding<String>, unit: String) -> some View {
        HStack(spacing: 10) {
            TextField("최소", text: min)
                .textFieldStyle(BoxedTextFieldStyle())
                .keyboardType(.decimalPad)
            Text("~").foregroundStyle(Theme.textFaint)
            TextField("최대", text: max)
                .textFieldStyle(BoxedTextFieldStyle())
                .keyboardType(.decimalPad)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
        }
    }
}
