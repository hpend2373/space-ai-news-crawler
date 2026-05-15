import SwiftUI

@main
struct BriefApp: App {
    var body: some Scene {
        WindowGroup {
            ModeSelectionView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - 모드 선택 화면

struct ModeSelectionView: View {
    @State private var selectedMode: BriefMode?
    @State private var isAnimating = false
    
    var body: some View {
        if let mode = selectedMode {
            // 선택된 모드로 이동
            BriefMainView(mode: mode, onBack: {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    selectedMode = nil
                    // 선택 초기화
                    UserDefaults.standard.removeObject(forKey: "selectedMode")
                }
            })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        } else {
            // 모드 선택 화면
            ZStack {
                // 배경 그라디언트
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // 헤더
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isAnimating ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                        
                        Text("Brief")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("어떤 뉴스를 확인하시겠습니까?")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 60)
                    
                    // 모드 선택 카드
                    HStack(spacing: 24) {
                        ModeCard(
                            mode: .stock,
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Stock + Space",
                            subtitle: "우주 산업 & 주식 뉴스",
                            gradient: [.blue, .purple],
                            onSelect: { selectMode(.stock) }
                        )
                        
                        ModeCard(
                            mode: .ai,
                            icon: "brain.head.profile",
                            title: "AI News",
                            subtitle: "OpenAI, Anthropic, Google AI",
                            gradient: [.pink, .orange],
                            onSelect: { selectMode(.ai) }
                        )
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // 하단 정보
                    Text("언제든지 설정에서 모드를 변경할 수 있습니다")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 20)
                }
            }
            .frame(width: 800, height: 600)
            .onAppear {
                isAnimating = true
            }
        }
    }
    
    private func selectMode(_ mode: BriefMode) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            selectedMode = mode
        }
        
        // 선택 저장
        UserDefaults.standard.set(mode.rawValue, forKey: "selectedMode")
    }
}

struct ModeCard: View {
    let mode: BriefMode
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 20) {
                // 아이콘
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient.map { $0.opacity(0.3) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: icon)
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // 텍스트
                VStack(spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
                // 선택 버튼
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("선택")
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(isHovered ? .white : .white.opacity(0.8))
                .padding(.top, 8)
            }
            .frame(width: 280, height: 340)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(isHovered ? 0.15 : 0.08))
                    .shadow(color: .black.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 30 : 15, x: 0, y: isHovered ? 15 : 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: isHovered ? gradient : [.white.opacity(0.2), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 2 : 1
                    )
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - 메인 뷰 (모드별 라우팅)

struct BriefMainView: View {
    let mode: BriefMode
    let onBack: () -> Void
    
    var body: some View {
        switch mode {
        case .stock:
            StockSpaceContentView(onBackToHome: onBack)
        case .ai:
            AINewsContentView(onBackToHome: onBack)
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
