import SwiftUI

struct LogView: View {
    @ObservedObject var logger: WebSocketLogger

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                terminalChrome

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if logger.entries.isEmpty {
                                Text("아직 로그가 없습니다. 검색 탭에서 수집을 시작해 보세요.")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            ForEach(logger.entries) { entry in
                                Text(entry.message.isEmpty ? " " : entry.message)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(color(for: entry.tag))
                                    .id(entry.id)
                            }
                            if let summary = logger.resultSummary {
                                Text(summary)
                                    .font(.system(.footnote, design: .monospaced).bold())
                                    .foregroundStyle(Theme.accentBright)
                                    .padding(.top, 6)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: logger.entries.count) { _ in
                        if let last = logger.entries.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
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

    private var terminalChrome: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.error).frame(width: 9, height: 9)
            Circle().fill(Theme.accent).frame(width: 9, height: 9)
            Circle().fill(Theme.success).frame(width: 9, height: 9)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
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
