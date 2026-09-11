import SwiftUI

struct LogView: View {
    @ObservedObject var logger: WebSocketLogger

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logger.entries) { entry in
                            Text(entry.message.isEmpty ? " " : entry.message)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(color(for: entry.tag))
                                .id(entry.id)
                        }
                        if let summary = logger.resultSummary {
                            Text(summary)
                                .font(.footnote.bold())
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
            .navigationTitle("수집 로그")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("지우기") { logger.clear() }
                }
            }
            .overlay(alignment: .bottom) {
                if logger.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("수집 중…")
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
        case "success": return .green
        case "error": return .red
        case "info": return .blue
        case "accent": return .orange
        default: return .secondary
        }
    }
}
