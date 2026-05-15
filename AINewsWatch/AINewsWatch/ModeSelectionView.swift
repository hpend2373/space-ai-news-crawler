import SwiftUI

// MARK: - 모드 열거형

enum BriefMode: String, Codable {
    case stock = "stock"
    case ai = "ai"
}

// MARK: - 모드 선택 홈 화면 (Apple HIG — Warm Cream)

struct ModeSelectionView: View {
    @State private var selectedMode: BriefMode?

    var body: some View {
        Group {
            if let mode = selectedMode {
                switch mode {
                case .stock:
                    StockSpaceContentView(onBackToHome: goHome)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .ai:
                    ContentView(onBackToHome: goHome)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            } else {
                homeScreen
            }
        }
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: "selectedMode"),
               let mode = BriefMode(rawValue: saved) {
                selectedMode = mode
            }
        }
    }

    private func goHome() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedMode = nil
            UserDefaults.standard.removeObject(forKey: "selectedMode")
        }
    }

    private func selectMode(_ mode: BriefMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "selectedMode")
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedMode = mode
        }
    }

    // MARK: - Home Screen

    private var homeScreen: some View {
        ZStack {
            DS.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Hero — minimal, 콘텐츠에 양보하는 UI
                VStack(spacing: DS.space16) {
                    Text("Daily")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.ink)
                        .tracking(-0.5)

                    Text("무엇이 궁금하세요?")
                        .font(DS.body)
                        .foregroundStyle(DS.stone)
                }
                .padding(.bottom, DS.space48)

                // Mode cards — 넉넉한 여백, 명확한 계층
                VStack(spacing: DS.space12) {
                    HomeCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Stock + Space",
                        subtitle: "우주 산업 & 주식",
                        color: DS.accentBlue,
                        action: { selectMode(.stock) }
                    )

                    HomeCard(
                        icon: "cpu",
                        title: "AI News",
                        subtitle: "OpenAI · Anthropic · Google",
                        color: DS.accentOrange,
                        action: { selectMode(.ai) }
                    )
                }
                .padding(.horizontal, DS.space20)

                Spacer()
                Spacer()
            }
        }
    }
}

// MARK: - Home Card (Apple HIG — Deference)

private struct HomeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space16) {
                // 아이콘 — 둥근 사각형 (Apple Settings 스타일)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous)
                            .fill(color)
                    )

                VStack(alignment: .leading, spacing: DS.space2) {
                    Text(title)
                        .font(DS.headline)
                        .foregroundStyle(DS.ink)

                    Text(subtitle)
                        .font(DS.subheadline)
                        .foregroundStyle(DS.stone)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.mist)
            }
            .padding(DS.space16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .warmCard()
    }
}
