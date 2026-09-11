import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var baseURL: String = APIClient.shared.baseURLString
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isDownloading = false
    @State private var shareURL: URL?
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("서버 주소") {
                    TextField("예: https://xxxx.trycloudflare.com", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("저장") {
                        APIClient.shared.baseURLString = baseURL.trimmingCharacters(in: .whitespaces)
                        model.sessionID = nil
                        Task { await model.ensureSession() }
                    }
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("연결 테스트")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("엑셀 파일") {
                    Text("수집된 모든 매물은 서버에 엑셀 파일로도 저장됩니다. 파일을 내려받아 공유하거나 다른 앱에서 열 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await downloadExcel() }
                    } label: {
                        HStack {
                            Label("엑셀 파일 다운로드", systemImage: "square.and.arrow.down")
                            Spacer()
                            if isDownloading { ProgressView() }
                        }
                    }
                    .disabled(isDownloading)
                }

                Section("세션") {
                    Text("저장 \(model.rowCount)건")
                        .foregroundStyle(.secondary)
                    Button("전체 초기화", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
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
