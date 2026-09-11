import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView(model: model, onStarted: { selectedTab = 2 })
                .tabItem { Label("검색", systemImage: "magnifyingglass") }
                .tag(0)

            ListingsView(model: model)
                .tabItem { Label("매물", systemImage: "list.bullet.rectangle") }
                .tag(1)

            LogView(logger: model.logger)
                .tabItem { Label("로그", systemImage: "terminal") }
                .tag(2)

            SettingsView(model: model)
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(3)
        }
        .task { await model.ensureSession() }
        .alert("오류", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
