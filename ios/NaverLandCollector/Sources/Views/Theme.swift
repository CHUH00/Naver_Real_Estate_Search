import SwiftUI

/// 앱 전체에서 공유하는 디자인 시스템. 앱 아이콘과 통일된 다크 네이비 + 골드 톤.
enum Theme {
    static let background       = Color(red: 0.055, green: 0.071, blue: 0.094)   // #0E1218
    static let surface          = Color(red: 0.086, green: 0.114, blue: 0.157)   // #161D28
    static let surfaceElevated  = Color(red: 0.114, green: 0.145, blue: 0.192)   // #1D2531
    static let border           = Color(red: 0.122, green: 0.165, blue: 0.227)   // #1F2A3A
    static let textPrimary      = Color(red: 0.886, green: 0.918, blue: 0.961)   // #E2EAF5
    static let textSecondary    = Color(red: 0.541, green: 0.596, blue: 0.686)   // #8A98AF
    static let accent           = Color(red: 0.961, green: 0.659, blue: 0.000)   // #F5A800
    static let success          = Color(red: 0.204, green: 0.816, blue: 0.475)   // #34D079
    static let error            = Color(red: 0.941, green: 0.376, blue: 0.376)   // #F06060
    static let info             = Color(red: 0.353, green: 0.620, blue: 0.831)   // #5A9ED4

    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 10
}

/// Form/List 계열 화면에 다크 배경을 일관되게 입히기 위한 modifier.
struct ThemedListBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

extension View {
    func themedListBackground() -> some View { modifier(ThemedListBackground()) }
}
