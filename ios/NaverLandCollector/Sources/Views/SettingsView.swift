import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var relay = RelayClient.shared
    @State private var baseURL: String = APIClient.shared.baseURLString
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isDownloading = false
    @State private var shareURL: URL?
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        SectionHeader("server.rack", "서버 주소").padding(.bottom, 12)
                        TextField("예: https://naverland-backend.onrender.com", text: $baseURL)
                            .textFieldStyle(BoxedTextFieldStyle())
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        HStack(spacing: 10) {
                            Button {
                                APIClient.shared.baseURLString = baseURL.trimmingCharacters(in: .whitespaces)
                                Task { await model.restartSession() }
                            } label: {
                                Text("저장").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .foregroundStyle(Theme.background)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

                            Button {
                                Task { await testConnection() }
                            } label: {
                                HStack {
                                    Text("연결 테스트").font(.subheadline.weight(.medium))
                                    if isTesting { ProgressView().scaleEffect(0.8) }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .foregroundStyle(Theme.accent)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        }
                        .padding(.top, 10)

                        if let testResult {
                            Text(testResult)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 6)
                        }
                    }

                    Card {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(relay.isConnected ? Theme.success : Theme.error)
                                .frame(width: 9, height: 9)
                            Text(relay.isConnected ? "중계 연결됨" : "중계 연결 안 됨")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        Text("네이버 부동산이 서버(클라우드) IP를 차단하기 때문에, 실제 접속은 이 아이폰의 통신망을 거쳐서 이루어집니다. 수집 중에는 앱을 꺼두지 마세요.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 6)
                    }

                    Card {
                        SectionHeader("tablecells", "엑셀 파일").padding(.bottom, 8)
                        Text("수집된 모든 매물은 서버에 엑셀 파일로도 저장됩니다. 파일을 내려받아 공유하거나 다른 앱에서 열 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.bottom, 10)
                        Button {
                            Task { await downloadExcel() }
                        } label: {
                            HStack {
                                Label("엑셀 파일 다운로드", systemImage: "square.and.arrow.down")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if isDownloading { ProgressView() }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                        }
                        .foregroundStyle(Theme.accent)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .disabled(isDownloading)
                    }

                    Card {
                        SectionHeader("archivebox", "세션", subtitle: "저장 \(model.rowCount)건")
                            .padding(.bottom, 12)
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Label("전체 초기화", systemImage: "trash")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .foregroundStyle(Theme.error)
                        .background(Theme.error.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("설정")
            .sheet(item: Binding(
                get: { shareURL.map { IdentifiableURL(url: $0) } },
                set: { shareURL = $0?.url }
            )) { item in
                ShareSheet(activityItems: [item.url])
            }
            .confirmationDialog("모든 매물 데이터를 삭제할까요?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("초기화", role: .destructive) {
                    Task { await model.resetSession() }
                }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        APIClient.shared.baseURLString = baseURL.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await APIClient.shared.newSession()
            testResult = "✅ 연결 성공"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }

    private func downloadExcel() async {
        isDownloading = true
        defer { isDownloading = false }
        guard let sid = model.sessionID else { return }
        do {
            shareURL = try await APIClient.shared.downloadExcel(sid)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
