import SwiftUI

// MARK: - Design System — Apple HIG (Warm Cream Palette)
//
// 핵심 원칙:
// 1. Clarity — 한눈에 이해 가능, 불필요한 장식 제거
// 2. Deference — UI가 콘텐츠에 양보, 배경은 조용히
// 3. Depth — 시각적 레이어로 계층 전달
//
// 기본색: 따뜻한 크림/베이지 (#F5F0E8 계열)

enum DS {
    // MARK: - Color Palette (Warm Cream)

    /// 페이지 배경 — 따뜻한 크림
    static let cream       = Color(red: 0.96, green: 0.94, blue: 0.91)   // #F5F0E8
    /// 카드 배경 — 밝은 웜 화이트
    static let warmWhite   = Color(red: 0.99, green: 0.98, blue: 0.96)   // #FCFAF5
    /// 보조 서피스 — 약간 더 진한 크림
    static let sand        = Color(red: 0.93, green: 0.90, blue: 0.86)   // #EDE6DB
    /// 구분선
    static let hairline    = Color(red: 0.87, green: 0.84, blue: 0.79)   // #DED6CA
    /// 주 텍스트
    static let ink         = Color(red: 0.12, green: 0.12, blue: 0.12)   // #1F1F1F
    /// 보조 텍스트
    static let stone       = Color(red: 0.45, green: 0.43, blue: 0.40)   // #736E66
    /// 비활성 텍스트
    static let mist        = Color(red: 0.65, green: 0.62, blue: 0.58)   // #A69E94

    // MARK: - Accent Colors (절제된 톤)

    static let accentBlue   = Color(red: 0.25, green: 0.47, blue: 0.70)
    static let accentPurple = Color(red: 0.50, green: 0.38, blue: 0.65)
    static let accentRed    = Color(red: 0.78, green: 0.28, blue: 0.28)
    static let accentGreen  = Color(red: 0.28, green: 0.62, blue: 0.45)
    static let accentOrange = Color(red: 0.82, green: 0.52, blue: 0.22)

    // MARK: - Provider Colors

    static let openAI    = Color(red: 0.10, green: 0.46, blue: 0.82)
    static let anthropic = Color(red: 0.80, green: 0.48, blue: 0.28)
    static let google    = Color(red: 0.20, green: 0.58, blue: 0.42)
    static let googleAI  = Color(red: 0.26, green: 0.52, blue: 0.96)
    static let notebookLM = Color(red: 0.15, green: 0.68, blue: 0.68)
    static let metaAI    = Color(red: 0.24, green: 0.46, blue: 0.96)
    static let trending  = Color(red: 0.85, green: 0.35, blue: 0.25)

    // MARK: - Typography (SF Pro 기반 시스템 스타일)

    static let largeTitle  = Font.system(size: 34, weight: .bold, design: .default)
    static let title1      = Font.system(size: 28, weight: .bold, design: .default)
    static let title2      = Font.system(size: 22, weight: .bold, design: .default)
    static let title3      = Font.system(size: 20, weight: .semibold, design: .default)
    static let headline    = Font.system(size: 17, weight: .semibold, design: .default)
    static let body        = Font.system(size: 17, weight: .regular, design: .default)
    static let callout     = Font.system(size: 16, weight: .regular, design: .default)
    static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
    static let footnote    = Font.system(size: 13, weight: .regular, design: .default)
    static let caption1    = Font.system(size: 12, weight: .regular, design: .default)
    static let caption2    = Font.system(size: 11, weight: .regular, design: .default)

    // MARK: - Spacing (8pt grid system)

    static let space2: CGFloat  = 2
    static let space4: CGFloat  = 4
    static let space8: CGFloat  = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space48: CGFloat = 48

    // MARK: - Radius

    static let radiusS: CGFloat  = 8
    static let radiusM: CGFloat  = 12
    static let radiusL: CGFloat  = 16
    static let radiusXL: CGFloat = 20
}

// MARK: - Apple Card Modifier

struct WarmCard: ViewModifier {
    var highlighted: Bool = false
    var highlightColor: Color = DS.accentBlue

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                    .fill(DS.warmWhite)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                    .strokeBorder(
                        highlighted ? highlightColor.opacity(0.25) : DS.hairline.opacity(0.5),
                        lineWidth: highlighted ? 1.5 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
    }
}

extension View {
    func warmCard(highlighted: Bool = false, color: Color = DS.accentBlue) -> some View {
        modifier(WarmCard(highlighted: highlighted, highlightColor: color))
    }
}

// MARK: - Badge (작은 캡슐 라벨)

struct DSBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(DS.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.10)))
    }
}

// MARK: - Divider

struct DSHairline: View {
    var indent: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(DS.hairline.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, indent)
    }
}
