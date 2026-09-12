import SwiftUI

struct LogView: View {
    @ObservedObject var logger: WebSocketLogger

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(logger.entries) { entry in
                            Text(entry.message.isEmpty ? " " : entry.message)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(color(for: entry.tag))
                                .id(entry.id)
                        }
                        if let summary = logger.resultSummary {
                            Text(summary)
                                .font(.footnote.bold())
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.top, 6)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                }
            }
            .overlay(alignment: .bottom) {
                if logger.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text("수집 중…").foregroundStyle(Theme.textPrimary)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func color(for tag: String) -> Color {
        switch tag {
        case "success": return Theme.success
        case "error": return Theme.error
        case "info": return Theme.info
        case "accent": return Theme.accent
        default: return Theme.textSecondary
        }
    }
}
