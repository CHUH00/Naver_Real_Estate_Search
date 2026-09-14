import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var selectedTab = 0

    init() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.surface)
        tabAppearance.shadowColor = UIColor(Theme.border)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Theme.background)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView(model: model, onStarted: { selectedTab = 2 })
                .tabItem { Label("검색", systemImage: "magnifyingglass") }
                .tag(0)

            ListingsView(model: model)
                .tabItem { Label("매물", systemImage: "list.bullet.rectangle") }
                .tag(1)

            LogView(logger: model.logger)
                .tabItem { Label("로그", systemImage: "list.bullet.clipboard") }
                .tag(2)

            SettingsView(model: model)
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(Theme.accent)
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
