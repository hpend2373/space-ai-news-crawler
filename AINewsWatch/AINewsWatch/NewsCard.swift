import SwiftUI

struct NewsCard: View {
    let item: NewsItem

    var body: some View {
        Link(destination: URL(string: item.url) ?? URL(string: "https://example.com")!) {
            VStack(alignment: .leading, spacing: 0) {
                // 상단: 제공자 + 소스 + 시간
                HStack(spacing: DS.space8) {
                    Circle()
                        .fill(providerColor)
                        .frame(width: 8, height: 8)

                    Text(item.providerName)
                        .font(DS.caption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(providerColor)

                    DSBadge(text: sourceLabel, color: DS.stone)

                    Spacer()

                    Text(item.publishedAt, style: .relative)
                        .font(DS.caption2)
                        .foregroundStyle(DS.mist)
                }
                .padding(.bottom, 10)

                // 제목
                Text(item.title)
                    .font(DS.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // 메타 정보
                if !item.meta.isEmpty {
                    Text(item.meta)
                        .font(DS.caption2)
                        .foregroundStyle(DS.mist)
                        .padding(.top, 6)
                }

                // 요약
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(DS.caption1)
                        .foregroundStyle(DS.stone)
                        .lineLimit(2)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .warmCard()
    }

    // MARK: - Provider Colors

    private var providerColor: Color {
        switch item.providerId.lowercased() {
        case "openai":       return DS.openAI
        case "anthropic":    return DS.anthropic
        case "google", "deepmind": return DS.google
        case "x_trending":   return DS.ink
        case "digest":       return DS.accentRed
        default:             return DS.stone
        }
    }

    private var sourceLabel: String {
        switch item.source.uppercased() {
        case "X": return "X"
        case "RSS": return "RSS"
        case "WEB": return "웹"
        case "DIGEST": return "뉴스"
        default: return item.source
        }
    }
}

#Preview {
    VStack(spacing: DS.space12) {
        NewsCard(item: NewsItem(
            providerId: "openai",
            providerName: "OpenAI",
            source: "X",
            title: "GPT-5 출시가 임박했습니다. 이전 버전 대비 10배 향상된 성능을 기대하세요.",
            url: "https://example.com",
            publishedAt: Date().addingTimeInterval(-3600),
            summary: "OpenAI가 차세대 언어 모델을 발표했습니다.",
            rawText: "",
            meta: ""
        ))

        NewsCard(item: NewsItem(
            providerId: "anthropic",
            providerName: "Anthropic",
            source: "WEB",
            title: "Claude 4 출시 — 코딩, 분석, 창의적 작업에서 혁신적인 성능 향상",
            url: "https://example.com",
            publishedAt: Date().addingTimeInterval(-7200),
            summary: "Anthropic이 Claude 4를 공식 출시했습니다.",
            rawText: "",
            meta: ""
        ))
    }
    .padding(DS.space16)
    .background(DS.cream)
}
