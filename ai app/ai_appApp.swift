import SwiftUI

@main
struct BriefApp: App {
    var body: some Scene {
        WindowGroup {
            ModeSelectionView()
                .preferredColorScheme(.light)
                .onAppear {
                    NSApp?.appearance = NSAppearance(named: .aqua)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - 모드 선택 화면 (Apple 스타일)

struct ModeSelectionView: View {
    @State private var selectedMode: BriefMode?
    @State private var isAnimating = false

    // 백그라운드 유지 — ViewModel을 상위에서 소유하여 뷰 전환 시 수집·번역 Task가 끊기지 않음
    @StateObject private var spaceVM = BriefViewModel()
    @StateObject private var aiVM = AINewsViewModel()
    @State private var hasVisitedStock = false
    @State private var hasVisitedAI = false

    var body: some View {
        ZStack {
            // ── 홈 화면 — 모드 미선택 시 표시 ──
            if selectedMode == nil {
                ZStack {
                    AppStyle.pageBg
                        .ignoresSafeArea()

                    GeometryReader { geo in
                        Circle()
                            .fill(AppStyle.spaceBlue.opacity(0.05))
                            .frame(width: 300, height: 300)
                            .blur(radius: 90)
                            .offset(x: -60, y: -40)

                        Circle()
                            .fill(AppStyle.claudeAccent.opacity(0.04))
                            .frame(width: 280, height: 280)
                            .blur(radius: 90)
                            .offset(x: geo.size.width - 220, y: geo.size.height - 260)
                    }
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        Spacer()

                        VStack(spacing: 8) {
                            Text("Daily Brief")
                                .font(.system(size: 38, weight: .bold, design: .default))
                                .foregroundColor(Color(white: 0.13))

                            Text("어떤 뉴스를 확인하시겠습니까?")
                                .font(.body)
                                .foregroundColor(Color(white: 0.40))
                        }
                        .padding(.bottom, 40)

                        HStack(spacing: 20) {
                            ModeCard(
                                mode: .stock,
                                icon: "globe.americas.fill",
                                title: "Space News",
                                subtitle: spaceVM.isRunning ? "수집 진행 중..." : "우주 산업 뉴스 브리핑",
                                accentColor: AppStyle.spaceBlue,
                                onSelect: { selectMode(.stock) }
                            )

                            ModeCard(
                                mode: .ai,
                                icon: "brain.head.profile",
                                title: "AI News",
                                subtitle: aiVM.isRunning ? "수집 진행 중..." : "OpenAI · Anthropic · Google AI",
                                accentColor: AppStyle.aiTeal,
                                onSelect: { selectMode(.ai) }
                            )
                        }
                        .padding(.horizontal, 40)

                        Spacer()

                        Text("홈 버튼으로 언제든 전환할 수 있습니다")
                            .font(.footnote)
                            .foregroundColor(Color(white: 0.60))
                            .padding(.bottom, 28)
                    }
                }
                .transition(.opacity)
            }

            // ── Space News — 한 번 방문 후 항상 유지 (수집·번역 백그라운드 지속) ──
            if hasVisitedStock {
                StockSpaceContentView(vm: spaceVM, onBackToHome: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMode = nil
                    }
                })
                .opacity(selectedMode == .stock ? 1 : 0)
                .allowsHitTesting(selectedMode == .stock)
            }

            // ── AI News — 한 번 방문 후 항상 유지 (수집 백그라운드 지속) ──
            if hasVisitedAI {
                AINewsContentView(vm: aiVM, onBackToHome: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMode = nil
                    }
                })
                .opacity(selectedMode == .ai ? 1 : 0)
                .allowsHitTesting(selectedMode == .ai)
            }
        }
        .frame(width: 780, height: 540)
        .onChange(of: selectedMode) { newMode in
            // 모드 복귀 시 파일 다시 읽기 (백그라운드 수집 결과 반영)
            switch newMode {
            case .stock: spaceVM.refresh()
            case .ai: aiVM.refresh()
            case nil: break
            }
        }
    }

    private func selectMode(_ mode: BriefMode) {
        // 방문 플래그 — 뷰를 생성하여 이후 항상 유지 (애니메이션 전에 설정)
        switch mode {
        case .stock: hasVisitedStock = true
        case .ai: hasVisitedAI = true
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedMode = mode
        }
        UserDefaults.standard.set(mode.rawValue, forKey: "selectedMode")
    }
}

// MARK: - 모드 카드 (Apple Weather·Stocks 스타일)

struct ModeCard: View {
    let mode: BriefMode
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 20) {
                Spacer().frame(height: 4)

                // 아이콘 (Apple 스타일 그라디언트 원)
                IconCircle(icon: icon, color: accentColor, size: 72)

                // 텍스트
                VStack(spacing: 5) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(white: 0.13))

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.40))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Spacer()

                // CTA 버튼 — macOS 네이티브
                Text("시작하기")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accentColor)
                    )

                Spacer().frame(height: 4)
            }
            .frame(width: 260, height: 290)
            .appleCard(isHovered: isHovered, hasBorder: isHovered, borderColor: accentColor)
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - 모드 열거형

enum BriefMode: String, Codable {
    case stock = "stock"
    case ai = "ai"
}

#Preview {
    ModeSelectionView()
}
