import SwiftUI

struct NewsCard: View {
    let item: NewsItem
    
    var body: some View {
        Link(destination: URL(string: item.url)!) {
            VStack(alignment: .leading, spacing: 10) {
                // 상단: 배지와 시간
                HStack {
                    // 제공자 배지
                    Text(item.providerName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(providerColor.opacity(0.2))
                        .foregroundStyle(providerColor)
                        .cornerRadius(12)
                    
                    // 소스 배지
                    Text(sourceLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(sourceColor.opacity(0.15))
                        .foregroundStyle(sourceColor)
                        .cornerRadius(10)
                    
                    Spacer()
                    
                    // 시간
                    Text(item.publishedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 제목
                Text(item.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                
                // 메타 정보 (트렌딩 아이템용)
                if !item.meta.isEmpty {
                    Text(item.meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 요약
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var providerColor: Color {
        switch item.providerId.lowercased() {
        case "openai":
            return Color(red: 0.357, green: 0.714, blue: 1.0) // #5BB6FF
        case "anthropic":
            return Color(red: 1.0, green: 0.827, blue: 0.431) // #FFD36E
        case "google", "deepmind":
            return Color(red: 0.357, green: 0.949, blue: 0.776) // #5BF2C6
        case "digest", "x_trending":
            return Color(red: 1.0, green: 0.357, blue: 0.478) // #FF5B7A
        default:
            return .gray
        }
    }
    
    private var sourceLabel: String {
        switch item.source.uppercased() {
        case "X":
            return "X"
        case "RSS":
            return "RSS"
        case "WEB":
            return "웹"
        case "DIGEST":
            return "뉴스"
        default:
            return item.source
        }
    }
    
    private var sourceColor: Color {
        switch item.source.uppercased() {
        case "X":
            return Color(red: 0.357, green: 0.714, blue: 1.0)
        case "RSS":
            return Color(red: 0.357, green: 0.949, blue: 0.776)
        case "WEB":
            return Color(red: 1.0, green: 0.827, blue: 0.431)
        case "DIGEST":
            return Color(red: 1.0, green: 0.357, blue: 0.478)
        default:
            return .gray
        }
    }
}

#Preview {
    NewsCard(item: NewsItem(
        id: UUID(),
        providerId: "openai",
        providerName: "OpenAI",
        source: "X",
        title: "ChatGPT-5 출시 예정",
        url: "https://example.com",
        publishedAt: Date(),
        summary: "OpenAI가 차세대 언어 모델 ChatGPT-5를 발표했습니다. 이전 버전보다 10배 빠른 성능을 자랑합니다.",
        rawText: "",
        meta: ""
    ))
    .padding()
    .background(Color(red: 0.027, green: 0.039, blue: 0.063))
}
