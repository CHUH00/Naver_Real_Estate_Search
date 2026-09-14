import SwiftUI

/// 토스 스타일 디자인 시스템 — 화이트 배경, 블루 액센트, 카드 기반 레이아웃.
enum Theme {
    static let background       = Color(red: 0.965, green: 0.969, blue: 0.976)   // #F6F7F9
    static let surface           = Color.white
    static let surfaceElevated  = Color.white
    static let border           = Color(red: 0.910, green: 0.922, blue: 0.941)   // #E8EBF0
    static let textPrimary      = Color(red: 0.098, green: 0.122, blue: 0.157)   // #191F28
    static let textSecondary    = Color(red: 0.451, green: 0.486, blue: 0.529)   // #737C87
    static let textFaint        = Color(red: 0.690, green: 0.710, blue: 0.749)   // #B0B5BF
    static let accent           = Color(red: 0.192, green: 0.510, blue: 0.965)   // #3182F6 (토스 블루)
    static let accentBright     = Color(red: 0.322, green: 0.588, blue: 0.980)   // #52A9FA
    static let accentSoft       = Color(red: 0.906, green: 0.937, blue: 0.996)   // #E7EFFE
    static let success          = Color(red: 0.000, green: 0.769, blue: 0.443)   // #00C471
    static let error            = Color(red: 0.941, green: 0.267, blue: 0.322)   // #F04452
    static let info             = accent

    static let radiusLarge: CGFloat = 24
    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 12

    static let cornerRadius: CGFloat = 16 // 하위 호환
}

// MARK: - Reusable components

/// 카드형 컨테이너 — 얇은 보더 대신 은은한 그림자로 배경과 분리.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accentSoft)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.bold))
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

/// 토스 블루 primary 버튼 — 큰 탭 영역, 플랫 컬러.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(isEnabled ? Theme.accent : Theme.textFaint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 연한 회색 배경의 입력창 스타일 — 보더 없이 채워진 필드.
struct BoxedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
    }
}

extension View {
    /// Form/List 계열 화면에 앱 배경색을 일관되게 입히기 위한 modifier (레거시 화면용).
    func themedListBackground() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background)
    }
}
