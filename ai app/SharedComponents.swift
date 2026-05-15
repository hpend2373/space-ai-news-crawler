import SwiftUI

// MARK: - Apple Design System (macOS Native — HIG 준수)

/// 앱 전체 디자인 토큰 — Apple Human Interface Guidelines 기반
/// 컬러, 타이포그래피, 레이아웃, 코너 레디우스 등 통합 관리
enum AppStyle {

    // MARK: Claude Desktop Palette

    /// 메인 배경 — Claude Desktop의 따뜻한 크림색
    static let pageBg       = Color(red: 0.980, green: 0.976, blue: 0.969)   // #FAF9F7
    /// 카드/서피스 — 밝은 화이트
    static let cardBg       = Color.white
    /// 보조 서피스 — 아주 살짝 따뜻한 회색
    static let surfaceBg    = Color(red: 0.965, green: 0.957, blue: 0.945)   // #F7F4F1
    /// 테두리 — 미세한 따뜻한 회색
    static let borderColor  = Color(red: 0.890, green: 0.875, blue: 0.855)   // #E3DFD9
    /// Claude 테라코타 악센트
    static let claudeAccent = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757

    // MARK: Accent Colors (기능별)

    static let spaceBlue   = Color(red: 0.30, green: 0.50, blue: 0.78)      // 부드러운 블루
    static let aiTeal      = Color(red: 0.851, green: 0.467, blue: 0.341)    // Claude 테라코타
    static let trendingPurple = Color(red: 0.55, green: 0.42, blue: 0.72)   // 부드러운 퍼플
    static let issueOrange = Color(red: 0.90, green: 0.55, blue: 0.20)      // 따뜻한 오렌지
    static let importantRed = Color(red: 0.85, green: 0.30, blue: 0.30)     // 부드러운 레드
    static let successGreen = Color(red: 0.30, green: 0.70, blue: 0.50)     // 부드러운 그린

    // MARK: Provider Colors (브랜드별)

    static let openAIGreen    = Color(red: 16/255, green: 163/255, blue: 127/255)
    static let anthropicOrange = Color(red: 0.851, green: 0.467, blue: 0.341)  // Claude 테라코타
    static let googleBlue     = Color(red: 0.26, green: 0.52, blue: 0.96)
    static let deepMindBlue   = Color(red: 66/255, green: 133/255, blue: 244/255)
    static let notebookLMCyan = Color(red: 0.20, green: 0.60, blue: 0.70)

    // MARK: Concentric Corner Radii (Apple HIG — outer = inner + padding)

    static let cardRadius: CGFloat    = 16    // 외곽 카드
    static let innerRadius: CGFloat   = 10    // 카드 내부 요소 (padding 6pt 기준)
    static let badgeRadius: CGFloat   = 6     // 작은 배지/태그
    static let iconRadius: CGFloat    = 12    // 아이콘 배경

    // MARK: Layout

    static let cardPadding: CGFloat   = 14    // 카드 내부 패딩
    static let sectionSpacing: CGFloat = 12   // 섹션 간 간격
    static let itemSpacing: CGFloat   = 1     // 리스트 아이템 간 (Apple grouped list: 거의 0)
    static let contentInset: CGFloat  = 16    // 스크롤뷰 좌우 인셋
}

// MARK: - Apple Grouped Section Card

/// Apple의 grouped list / Weather·Stocks 카드 스타일
/// - 반투명 머티리얼 배경 (.ultraThinMaterial)
/// - 미세한 separator 테두리
/// - Concentric continuous 코너
struct AppleCard: ViewModifier {
    var isHovered: Bool = false
    var hasBorder: Bool = false
    var borderColor: Color = .secondary

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous)
                    .fill(AppStyle.cardBg)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.07 : 0.03),
                        radius: isHovered ? 8 : 3,
                        x: 0, y: isHovered ? 2 : 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous)
                    .strokeBorder(
                        hasBorder
                            ? borderColor.opacity(0.3)
                            : AppStyle.borderColor.opacity(0.6),
                        lineWidth: hasBorder ? 1.5 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous))
    }
}

extension View {
    func appleCard(isHovered: Bool = false, hasBorder: Bool = false, borderColor: Color = .secondary) -> some View {
        modifier(AppleCard(isHovered: isHovered, hasBorder: hasBorder, borderColor: borderColor))
    }
}

// MARK: - Apple Section Header (Grouped List 스타일)

/// Apple 설정/Weather 앱 스타일 섹션 헤더
struct SectionHeader: View {
    let title: String
    let icon: String?
    let color: Color

    init(_ title: String, icon: String? = nil, color: Color = .secondary) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

// MARK: - Apple List Row Divider

/// Apple grouped list 내부 구분선 — 좌측 패딩 적용
struct ListRowDivider: View {
    var leadingPadding: CGFloat = 52

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.4))
            .frame(height: 0.5)
            .padding(.leading, leadingPadding)
    }
}

// MARK: - Apple Badge Label (캡슐)

/// 작은 카테고리/상태 배지 (예: "중요", "인기", "트렌딩")
struct BadgeLabel: View {
    let text: String
    let icon: String?
    let color: Color

    init(_ text: String, icon: String? = nil, color: Color = .secondary) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.10))
        )
    }
}

// MARK: - Apple Native Action Button

/// macOS 네이티브 `.borderedProminent` 버튼 래퍼
/// Apple의 시스템 버튼 스타일을 그대로 사용
struct ActionButton: View {
    let title: String
    let icon: String?
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String, icon: String? = nil, color: Color = .accentColor, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if isLoading {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 10, height: 10)
                    Text(title)
                }
            } else if let icon = icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(color)
        .disabled(isLoading)
    }
}

// MARK: - Apple Icon Circle

/// Apple 스타일 아이콘 원형 배경 (Weather·Stocks 앱 참고)
struct IconCircle: View {
    let icon: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
