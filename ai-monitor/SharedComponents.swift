import SwiftUI

// MARK: - 공통 UI 컴포넌트

/// 모던한 버튼 스타일 (Stock + AI News 공통)
struct ModernButtonStyle: ButtonStyle {
    let color: Color
    var isProminent: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isProminent ? color : Color.clear)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isProminent ? Color.clear : color.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(isProminent ? .white : color)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
