import SwiftUI

/// Brief 앱 아이콘 생성기
/// "O" 모양의 원형 디자인 + 그라디언트
struct AppIconView: View {
    let size: CGFloat
    
    var body: some View {
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
            
            // 주 원형 (O)
            ZStack {
                // 외곽 원 (그라디언트)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.36, green: 0.71, blue: 1.0),    // 밝은 파랑
                                Color(red: 0.58, green: 0.4, blue: 0.95),    // 보라
                                Color(red: 0.95, green: 0.4, blue: 0.58)     // 핑크
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)
                
                // 내부 원 (투명 - "O" 만들기)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.95),
                                Color(red: 0.05, green: 0.05, blue: 0.15).opacity(0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.45, height: size * 0.45)
                
                // 광택 효과
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.0)
                            ],
                            center: .init(x: 0.3, y: 0.3),
                            startRadius: 0,
                            endRadius: size * 0.3
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)
                    .offset(x: -size * 0.05, y: -size * 0.05)
                
                // 중앙 강조 포인트
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.36, green: 0.95, blue: 0.78).opacity(0.6),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.15
                        )
                    )
                    .frame(width: size * 0.25, height: size * 0.25)
                    .blur(radius: 4)
            }
            
            // 반짝이는 별 효과 (선택사항)
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: size * 0.025, height: size * 0.025)
                    .blur(radius: 1)
                    .offset(
                        x: size * sparkleOffset(index).x,
                        y: size * sparkleOffset(index).y
                    )
            }
        }
        .frame(width: size, height: size)
    }
    
    private func sparkleOffset(_ index: Int) -> (x: CGFloat, y: CGFloat) {
        switch index {
        case 0: return (-0.25, -0.22)
        case 1: return (0.28, -0.18)
        case 2: return (0.15, 0.26)
        default: return (0, 0)
        }
    }
}

/// 간단한 버전 (더 미니멀)
struct AppIconViewMinimal: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // 배경
            Color(red: 0.08, green: 0.08, blue: 0.18)
            
            // 메인 원형 링
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.36, green: 0.71, blue: 1.0),
                                Color(red: 0.58, green: 0.4, blue: 0.95),
                                Color(red: 0.95, green: 0.4, blue: 0.58)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size * 0.12
                    )
                    .frame(width: size * 0.62, height: size * 0.62)
                
                // 광택
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: size * 0.04
                    )
                    .frame(width: size * 0.62, height: size * 0.62)
                    .rotationEffect(.degrees(-45))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 프리뷰용 뷰
struct AppIconPreview: View {
    var body: some View {
        VStack(spacing: 40) {
            Text("Brief 앱 아이콘 디자인")
                .font(.title.bold())
            
            HStack(spacing: 40) {
                VStack(spacing: 12) {
                    AppIconView(size: 256)
                        .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Text("버전 1: 풀 디자인")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 12) {
                    AppIconViewMinimal(size: 256)
                        .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Text("버전 2: 미니멀")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("macOS 앱 아이콘 가이드: 1024x1024px")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview("아이콘 미리보기") {
    AppIconPreview()
}

#Preview("아이콘 단독 - 풀 디자인") {
    AppIconView(size: 1024)
}

#Preview("아이콘 단독 - 미니멀") {
    AppIconViewMinimal(size: 1024)
}
