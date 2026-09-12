import SwiftUI

/// 앱 전체에서 공유하는 디자인 시스템. 앱 아이콘과 통일된 다크 네이비 + 골드 톤.
enum Theme {
    static let background       = Color(red: 0.043, green: 0.055, blue: 0.075)   // #0B0E13
    static let surface           = Color(red: 0.086, green: 0.114, blue: 0.157)   // #161D28
    static let surfaceElevated  = Color(red: 0.122, green: 0.157, blue: 0.208)   // #1F2835
    static let border           = Color(red: 0.157, green: 0.204, blue: 0.267)   // #283444
    static let textPrimary      = Color(red: 0.918, green: 0.937, blue: 0.965)   // #EAEFF6
    static let textSecondary    = Color(red: 0.545, green: 0.596, blue: 0.671)   // #8B98AB
    static let textFaint        = Color(red: 0.361, green: 0.408, blue: 0.482)   // #5C687B
    static let accent           = Color(red: 0.961, green: 0.659, blue: 0.000)   // #F5A800
    static let accentBright     = Color(red: 1.000, green: 0.773, blue: 0.290)   // #FFC54A
    static let success          = Color(red: 0.204, green: 0.816, blue: 0.475)   // #34D079
    static let error            = Color(red: 0.941, green: 0.376, blue: 0.376)   // #F06060
    static let info             = Color(red: 0.408, green: 0.663, blue: 0.867)   // #68A9DD

    static let radiusLarge: CGFloat = 22
    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 10

    static let cornerRadius: CGFloat = 16 // 하위 호환
}

// MARK: - Reusable components

/// 카드형 컨테이너 — 모든 섹션의 기본 배경.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

/// 아이콘 배지가 붙은 섹션 헤더.
struct SectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    init(_ icon: String, _ title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = nil
    }

    init<T: View>(_ icon: String, _ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> T) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textFaint)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// 골드 그라디언트 primary 버튼.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: isEnabled ? [Theme.accentBright, Theme.accent] : [Theme.textFaint, Theme.textFaint],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: isEnabled ? Theme.accent.opacity(0.35) : .clear, radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 아웃라인 텍스트필드 스타일 — 데스크톱 앱의 입력창 느낌.
struct BoxedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
    }
}

extension View {
    /// Form/List 계열 화면에 다크 배경을 일관되게 입히기 위한 modifier (레거시 화면용).
    func themedListBackground() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background)
    }
}
