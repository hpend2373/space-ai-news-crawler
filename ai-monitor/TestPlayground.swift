// Swift Playgrounds에서 테스트 가능한 간소화 버전
// Xcode > File > New > Playground 에서 이 코드를 붙여넣으면 즉시 실행 가능

import SwiftUI
import PlaygroundSupport

// MARK: - 데이터 모델 (간소화)

struct NewsItem: Identifiable, Hashable {
    let id = UUID()
    let providerId: String
    let providerName: String
    let source: String
    let title: String
    let url: String
    let publishedAt: Date
    let summary: String
}

// MARK: - 뉴스 카드

struct NewsCard: View {
    let item: NewsItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.providerName)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(providerColor.opacity(0.2))
                    .foregroundStyle(providerColor)
                    .cornerRadius(12)
                
                Text(item.source)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .cornerRadius(10)
                
                Spacer()
                
                Text(item.publishedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(item.title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(3)
            
            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
    
    private var providerColor: Color {
        switch item.providerId.lowercased() {
        case "openai": return .blue
        case "anthropic": return .orange
        case "google": return .green
        default: return .gray
        }
    }
}

// MARK: - 메인 뷰

struct ContentView: View {
    let mockNews = [
        NewsItem(
            providerId: "openai",
            providerName: "OpenAI",
            source: "X",
            title: "ChatGPT-5 coming soon with major improvements",
            url: "https://openai.com",
            publishedAt: Date().addingTimeInterval(-3600),
            summary: "We're excited to announce ChatGPT-5 will launch next month with 10x performance improvements and better reasoning capabilities."
        ),
        NewsItem(
            providerId: "anthropic",
            providerName: "Anthropic",
            source: "WEB",
            title: "Claude 3.5 Sonnet achieves breakthrough in coding",
            url: "https://anthropic.com",
            publishedAt: Date().addingTimeInterval(-7200),
            summary: "Our latest model shows significant improvements in software engineering tasks, outperforming previous versions by 40%."
        ),
        NewsItem(
            providerId: "google",
            providerName: "Google AI",
            source: "RSS",
            title: "Gemini 2.0 Flash now available in API",
            url: "https://ai.google.dev",
            publishedAt: Date().addingTimeInterval(-1800),
            summary: "Access our fastest model through the Gemini API starting today. Flash is 2x faster than Pro while maintaining quality."
        ),
        NewsItem(
            providerId: "openai",
            providerName: "OpenAI",
            source: "X",
            title: "GPT-4 Turbo price reduction announced",
            url: "https://openai.com/pricing",
            publishedAt: Date().addingTimeInterval(-5400),
            summary: "We're reducing GPT-4 Turbo pricing by 50% to make advanced AI more accessible to developers worldwide."
        )
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 배경 그라디언트
                LinearGradient(
                    colors: [
                        Color(red: 0.027, green: 0.039, blue: 0.063),
                        Color(red: 0.043, green: 0.063, blue: 0.125)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // 뉴스 리스트
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(mockNews) { item in
                            NewsCard(item: item)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("AI 릴리스 워치")
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Playground 실행

PlaygroundPage.current.setLiveView(ContentView())
