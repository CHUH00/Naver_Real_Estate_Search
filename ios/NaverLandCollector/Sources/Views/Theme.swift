import SwiftUI
import UIKit

/// 토스 스타일 디자인 시스템 — 화이트/블루(라이트) · 다크 네이비/블루(다크), 카드 기반 레이아웃.
///
/// 모든 색은 시스템 다크모드 설정에 따라 자동으로 바뀌는 다이내믹 컬러다
/// (UIColor의 트레잇 기반 provider를 그대로 감싸서 씀). 그래서 화면 쪽 코드는
/// 라이트/다크를 신경쓸 필요 없이 그냥 Theme.xxx 를 쓰면 된다.
enum Theme {
    /// 라이트용 RGB와 다크용 RGB를 받아 트레잇에 따라 자동 전환되는 Color를 만든다.
    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(UIColor { trait in
            let (r, g, b) = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }

    static let background = dynamic(
        light: (0.965, 0.969, 0.976),   // #F6F7F9
        dark:  (0.055, 0.059, 0.067)    // #0E0F11
    )
    static let surface = dynamic(
        light: (1.000, 1.000, 1.000),   // 흰색
        dark:  (0.106, 0.114, 0.125)    // #1B1D20
    )
    static let surfaceElevated = dynamic(
        light: (1.000, 1.000, 1.000),
        dark:  (0.141, 0.149, 0.165)    // #242630
    )
    static let border = dynamic(
        light: (0.910, 0.922, 0.941),   // #E8EBF0
        dark:  (0.196, 0.204, 0.220)    // #323438
    )
    static let textPrimary = dynamic(
        light: (0.098, 0.122, 0.157),   // #191F28
        dark:  (0.949, 0.953, 0.961)    // #F2F3F5
    )
    static let textSecondary = dynamic(
        light: (0.451, 0.486, 0.529),   // #737C87
        dark:  (0.635, 0.655, 0.678)    // #A2A7AD
    )
    static let textFaint = dynamic(
        light: (0.690, 0.710, 0.749),   // #B0B5BF
        dark:  (0.392, 0.412, 0.435)    // #64696F
    )
    static let accent = dynamic(
        light: (0.192, 0.510, 0.965),   // #3182F6 (토스 블루)
        dark:  (0.290, 0.573, 1.000)    // #4A92FF — 어두운 배경에서 살짝 밝게
    )
    static let accentBright = dynamic(
        light: (0.322, 0.588, 0.980),   // #52A9FA
        dark:  (0.400, 0.651, 1.000)    // #66A6FF
    )
    static let accentSoft = dynamic(
        light: (0.906, 0.937, 0.996),   // #E7EFFE
        dark:  (0.110, 0.169, 0.271)    // #1C2B45
    )
    static let success = dynamic(
        light: (0.000, 0.769, 0.443),   // #00C471
        dark:  (0.204, 0.831, 0.522)    // #34D485
    )
    static let error = dynamic(
        light: (0.941, 0.267, 0.322),   // #F04452
        dark:  (1.000, 0.373, 0.408)    // #FF5F68
    )
    static let info = accent
    /// 세그먼트 스위처 같은 곳의 "홈" 트랙 배경.
    static let track = dynamic(
        light: (0.902, 0.914, 0.933),   // #E6E9EE
        dark:  (0.192, 0.200, 0.216)    // #313337
    )

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
