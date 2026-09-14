import SwiftUI

struct LogView: View {
    @ObservedObject var logger: WebSocketLogger

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if logger.entries.isEmpty {
                            emptyState
                        }
                        ForEach(logger.entries) { entry in
                            logRow(entry).id(entry.id)
                        }
                        if let summary = logger.resultSummary {
                            summaryRow(summary)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: logger.entries.count) { _ in
                    if let last = logger.entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("수집 로그")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("지우기") { logger.clear() }
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
                }
            }
            .overlay(alignment: .bottom) {
                if logger.isRunning { runningPill }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textFaint)
            Text("아직 로그가 없습니다")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("검색 탭에서 수집을 시작해 보세요")
                .font(.footnote)
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var runningPill: some View {
        Button {
            logger.cancelByUser()
        } label: {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("수집 중… (눌러서 종료)").foregroundStyle(.white)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 4)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        let trimmed = entry.message.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 4)
        } else if entry.tag == "accent" {
            Text(trimmed.replacingOccurrences(of: "─", with: "").trimmingCharacters(in: .whitespaces))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 10)
                .padding(.bottom, 2)
        } else {
            HStack(alignment: .top, spacing: 8) {
                icon(for: entry, text: trimmed)
                Text(trimmed)
                    .font(.footnote)
                    .foregroundStyle(color(for: entry.tag))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)
        }
    }

    private func icon(for entry: LogEntry, text: String) -> some View {
        let name: String
        let tint: Color
        switch entry.tag {
        case "error":
            name = "xmark.circle.fill"; tint = Theme.error
        case "info":
            name = "checkmark.circle.fill"; tint = Theme.success
        default:
            if text.hasPrefix("제외") {
                name = "minus.circle.fill"; tint = Theme.textFaint
            } else {
                name = "circle.fill"; tint = Theme.textFaint
            }
        }
        return Image(systemName: name)
            .font(.system(size: name == "circle.fill" ? 5 : 13))
            .foregroundStyle(tint)
            .frame(width: 16, height: 18)
    }

    private func summaryRow(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
            Text(summary)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, 8)
    }

    private func color(for tag: String) -> Color {
        switch tag {
        case "error": return Theme.error
        case "info": return Theme.textPrimary
        default: return Theme.textSecondary
        }
    }
}
