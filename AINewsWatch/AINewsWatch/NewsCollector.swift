import Foundation

// MARK: - Configuration

struct NewsConfig {
    let providers: [ProviderConfig]
    let nitter: NitterConfig
    let digest: DigestConfig
    let xTrending: TrendingConfig

    struct ProviderConfig {
        let id: String
        let name: String
        let xHandles: [String]
        let rss: [String]
        let web: [String]
    }

    struct NitterConfig {
        let instances: [String]
        let maxPostsPerHandle: Int
    }

    struct DigestConfig {
        let googleNewsRssQueries: [String]
        let maxItemsTotal: Int
    }

    struct TrendingConfig {
        let enabled: Bool
    }

    /// 기본 AI 뉴스 설정
    static let defaultAI = NewsConfig(
        providers: [
            ProviderConfig(
                id: "openai",
                name: "OpenAI",
                xHandles: ["OpenAI"],
                rss: ["https://openai.com/blog/rss.xml"],
                web: []
            ),
            ProviderConfig(
                id: "anthropic",
                name: "Anthropic",
                xHandles: ["AnthropicAI"],
                rss: [],
                web: ["https://www.anthropic.com/news"]
            ),
            ProviderConfig(
                id: "google",
                name: "Google DeepMind",
                xHandles: ["GoogleDeepMind"],
                rss: ["https://blog.google/technology/ai/rss/"],
                web: []
            ),
            ProviderConfig(
                id: "meta",
                name: "Meta AI",
                xHandles: ["MetaAI"],
                rss: [],
                web: []
            ),
            ProviderConfig(
                id: "xai",
                name: "xAI",
                xHandles: ["xaboratory"],
                rss: [],
                web: []
            ),
            ProviderConfig(
                id: "googleai",
                name: "Google AI",
                xHandles: ["GoogleAI"],
                rss: ["https://blog.google/technology/ai/rss/"],
                web: []
            ),
            ProviderConfig(
                id: "notebooklm",
                name: "NotebookLM",
                xHandles: ["NotebookLM"],
                rss: [],
                web: []
            ),
        ],
        nitter: NitterConfig(
            instances: [
                "https://nitter.privacydev.net",
                "https://nitter.poast.org",
                "https://nitter.cz"
            ],
            maxPostsPerHandle: 10
        ),
        digest: DigestConfig(
            googleNewsRssQueries: [
                "artificial intelligence news",
                "OpenAI GPT",
                "Anthropic Claude",
                "Google Gemini AI",
                "AI model release",
                "machine learning breakthrough"
            ],
            maxItemsTotal: 30
        ),
        xTrending: TrendingConfig(enabled: true)
    )

    /// 기본 우주 뉴스 설정
    static let defaultSpace = NewsConfig(
        providers: [
            ProviderConfig(
                id: "spacex",
                name: "SpaceX",
                xHandles: ["SpaceX"],
                rss: [],
                web: []
            ),
            ProviderConfig(
                id: "rocketlab",
                name: "Rocket Lab",
                xHandles: ["RocketLab"],
                rss: ["https://rocketlabcorp.com/updates/rss/", "https://investors.rocketlabcorp.com/rss/news-releases.xml"],
                web: []
            ),
            ProviderConfig(
                id: "blueorigin",
                name: "Blue Origin",
                xHandles: ["blueorigin"],
                rss: [],
                web: []
            ),
            ProviderConfig(
                id: "nasa",
                name: "NASA",
                xHandles: ["NASA"],
                rss: ["https://www.nasa.gov/rss/dyn/breaking_news.rss"],
                web: []
            ),
            ProviderConfig(
                id: "spacenews",
                name: "SpaceNews",
                xHandles: ["SpaceNews_Inc"],
                rss: ["https://spacenews.com/feed/"],
                web: []
            ),
            ProviderConfig(
                id: "planetlabs",
                name: "Planet Labs",
                xHandles: ["planet"],
                rss: ["https://www.planet.com/pulse/rss/"],
                web: []
            ),
        ],
        nitter: NitterConfig(
            instances: [
                "https://nitter.privacydev.net",
                "https://nitter.poast.org",
                "https://nitter.cz"
            ],
            maxPostsPerHandle: 10
        ),
        digest: DigestConfig(
            googleNewsRssQueries: [
                "\"SpaceX\" launch OR mission OR Starship",
                "\"Rocket Lab\" launch OR Electron OR Neutron",
                "\"Blue Origin\" space OR New Glenn",
                "\"Planet Labs\" satellite OR PlanetScope",
                "space industry news satellite launch 2026",
                "NASA Artemis mission 2026",
                "space economy contract budget policy",
                "commercial space satellite defense",
                "스페이스X 발사 OR 미션 OR 스타쉽",
                "로켓랩 발사 OR 일렉트론 OR 뉴트론",
                "블루오리진 우주 OR 뉴글렌",
                "플래닛랩스 위성",
                "우주경제 계약 OR 예산 OR 정책 OR 발사",
                "상업우주 위성 OR 방산 OR 발사시장",
                "NASA 아르테미스 미션",
                "우주산업 뉴스 2026",
            ],
            maxItemsTotal: 50
        ),
        xTrending: TrendingConfig(enabled: false)
    )
}

// MARK: - Collection Result

struct CollectionResult {
    let allItems: [NewsItem]
    let trendingItems: [NewsItem]
    let digestItems: [NewsItem]
    let sourceHealth: [String]
}

// MARK: - NewsCollector

actor NewsCollector {
    let config: NewsConfig

    init(config: NewsConfig) {
        self.config = config
    }

    func collect(
        windowHours: Int,
        progressHandler: @MainActor @Sendable (Double, String) async -> Void
    ) async -> CollectionResult {
        let cutoffDate = Date().addingTimeInterval(-Double(windowHours) * 3600)
        var allItems: [NewsItem] = []
        var trendingItems: [NewsItem] = []
        var digestItems: [NewsItem] = []
        var sourceHealth: [String] = []

        let totalSteps = Double(config.providers.count + 2)
        var currentStep = 0.0

        // 1. 각 제공자별 뉴스 수집
        for provider in config.providers {
            currentStep += 1
            await progressHandler(currentStep / totalSteps, "\(provider.name) 수집 중...")

            // RSS 피드 수집
            for rssUrl in provider.rss {
                let (items, error) = await fetchRSS(
                    url: rssUrl,
                    providerId: provider.id,
                    providerName: provider.name,
                    cutoffDate: cutoffDate
                )
                allItems.append(contentsOf: items)
                if let error = error {
                    sourceHealth.append("RSS \(provider.name): \(error)")
                }
            }

            // Web (Anthropic 등)
            for webUrl in provider.web {
                let (items, errors) = await fetchWebNews(
                    url: webUrl,
                    providerId: provider.id,
                    providerName: provider.name,
                    cutoffDate: cutoffDate
                )
                allItems.append(contentsOf: items)
                sourceHealth.append(contentsOf: errors)
            }
        }

        // 2. Digest (Google News RSS)
        currentStep += 1
        await progressHandler(currentStep / totalSteps, "AI 소식 수집 중...")

        let (digest, digestErrors) = await fetchDigest(cutoffDate: cutoffDate)
        digestItems = digest
        sourceHealth.append(contentsOf: digestErrors)

        // 3. X Trending (Google News RSS 기반)
        if config.xTrending.enabled {
            currentStep += 1
            await progressHandler(currentStep / totalSteps, "트렌딩 수집 중...")
            let trendQueries = [
                "ChatGPT OR Claude OR Gemini AI",
                "AI model OR LLM launch 2026",
                "AI agent OR AI startup"
            ]
            for query in trendQueries {
                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let trendUrl = "https://news.google.com/rss/search?q=\(encoded)&hl=ko&gl=KR&ceid=KR:ko"
                let (tItems, _) = await fetchRSS(
                    url: trendUrl,
                    providerId: "trending",
                    providerName: "트렌딩",
                    cutoffDate: cutoffDate
                )
                trendingItems.append(contentsOf: tItems)
                if trendingItems.count >= 30 { break }
            }
        }

        // 중복 제거 및 정렬
        allItems = deduplicate(allItems).sorted { $0.publishedAt > $1.publishedAt }
        digestItems = deduplicate(digestItems).sorted { $0.publishedAt > $1.publishedAt }
        trendingItems = deduplicate(trendingItems).sorted { $0.publishedAt > $1.publishedAt }

        return CollectionResult(
            allItems: allItems,
            trendingItems: trendingItems,
            digestItems: digestItems,
            sourceHealth: sourceHealth
        )
    }

    // MARK: - RSS

    private func fetchRSS(
        url: String,
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) async -> ([NewsItem], String?) {
        guard let requestUrl = URL(string: url) else {
            return ([], "잘못된 URL")
        }

        do {
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return ([], "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }

            let parser = SimpleRSSParser(data: data)
            let rssItems = parser.parse()

            let items = rssItems.compactMap { rssItem -> NewsItem? in
                guard rssItem.pubDate >= cutoffDate else { return nil }

                return NewsItem(
                    providerId: providerId,
                    providerName: providerName,
                    source: "RSS",
                    title: rssItem.title,
                    url: rssItem.link,
                    publishedAt: rssItem.pubDate,
                    summary: rssItem.description,
                    rawText: "\(rssItem.title)\n\(rssItem.description)"
                )
            }

            return (items, nil)

        } catch {
            return ([], error.localizedDescription)
        }
    }

    // MARK: - Web (Anthropic)

    private func fetchWebNews(
        url: String,
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) async -> ([NewsItem], [String]) {
        if url.contains("anthropic.com/news") {
            return await fetchAnthropicNews(
                url: url,
                providerId: providerId,
                providerName: providerName,
                cutoffDate: cutoffDate
            )
        }

        return ([], ["지원하지 않는 웹 소스: \(url)"])
    }

    private func fetchAnthropicNews(
        url: String,
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) async -> ([NewsItem], [String]) {
        guard let requestUrl = URL(string: url) else {
            return ([], ["잘못된 URL"])
        }

        var items: [NewsItem] = []
        var errors: [String] = []

        do {
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""

            let pattern = "href=\"(/news/[^\"]+)\""
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            var articleUrls: [String] = []
            for match in matches.prefix(18) {
                if let range = Range(match.range(at: 1), in: html) {
                    let path = String(html[range])
                    let fullUrl = "https://www.anthropic.com\(path)"
                    if !articleUrls.contains(fullUrl) {
                        articleUrls.append(fullUrl)
                    }
                }
            }

            for articleUrl in articleUrls.prefix(8) {
                if let article = await fetchAnthropicArticle(articleUrl) {
                    if article.date >= cutoffDate {
                        items.append(NewsItem(
                            providerId: providerId,
                            providerName: providerName,
                            source: "WEB",
                            title: article.title,
                            url: articleUrl,
                            publishedAt: article.date,
                            summary: article.description,
                            rawText: "\(article.title)\n\(article.description)"
                        ))
                    }
                }
            }

        } catch {
            errors.append("Anthropic 웹: \(error.localizedDescription)")
        }

        return (items, errors)
    }

    private func fetchAnthropicArticle(_ url: String) async -> (title: String, description: String, date: Date)? {
        guard let requestUrl = URL(string: url) else { return nil }

        do {
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""

            var title = ""
            if let titleRange = html.range(of: "<meta property=\"og:title\" content=\"([^\"]+)\"", options: .regularExpression) {
                let match = String(html[titleRange])
                title = match.replacingOccurrences(of: "<meta property=\"og:title\" content=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }

            var description = ""
            if let descRange = html.range(of: "<meta property=\"og:description\" content=\"([^\"]+)\"", options: .regularExpression) {
                let match = String(html[descRange])
                description = match.replacingOccurrences(of: "<meta property=\"og:description\" content=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }

            var date = Date()
            if let dateRange = html.range(of: "<div class=\"body-3 agate\">\\s*([A-Z][a-z]{2}\\s+\\d{1,2},\\s+\\d{4})", options: .regularExpression) {
                let match = String(html[dateRange])
                let dateStr = match.replacingOccurrences(of: "<div class=\"body-3 agate\">", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                formatter.locale = Locale(identifier: "en_US")
                if let parsedDate = formatter.date(from: dateStr) {
                    date = parsedDate
                }
            }

            if !title.isEmpty {
                return (title, description, date)
            }

        } catch {
            return nil
        }

        return nil
    }

    // MARK: - Digest (Google News RSS)

    private func fetchDigest(cutoffDate: Date) async -> ([NewsItem], [String]) {
        var items: [NewsItem] = []
        var errors: [String] = []

        for query in config.digest.googleNewsRssQueries {
            let url = "https://news.google.com/rss/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&hl=ko&gl=KR&ceid=KR:ko"

            let (rssItems, error) = await fetchRSS(
                url: url,
                providerId: "digest",
                providerName: "AI 소식",
                cutoffDate: cutoffDate
            )

            items.append(contentsOf: rssItems.map {
                NewsItem(
                    providerId: "digest",
                    providerName: "AI 소식",
                    source: "DIGEST",
                    title: $0.title,
                    url: $0.url,
                    publishedAt: $0.publishedAt,
                    summary: $0.summary,
                    rawText: $0.rawText
                )
            })

            if let error = error {
                errors.append("Google News RSS: \(error)")
            }

            if items.count >= config.digest.maxItemsTotal {
                break
            }
        }

        return (Array(items.prefix(config.digest.maxItemsTotal)), errors)
    }

    // MARK: - Utilities

    private func deduplicate(_ items: [NewsItem]) -> [NewsItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = item.url.isEmpty ? "\(item.title)|\(item.publishedAt)" : item.url
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func stripHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Translation (Google GTX)
    func translateToKorean(_ text: String) async -> String? {
        let asciiCount = text.unicodeScalars.filter { $0.isASCII && $0.value > 32 }.count
        let totalCount = text.count
        guard totalCount > 0 else { return nil }
        let asciiRatio = Double(asciiCount) / Double(totalCount)
        guard asciiRatio > 0.7 else { return nil }

        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ko&dt=t&q=\(encoded)"
        guard let url = URL(string: urlStr) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [Any],
               let sentences = json.first as? [[Any]] {
                let translated = sentences.compactMap { $0.first as? String }.joined()
                return translated.isEmpty ? nil : translated
            }
        } catch {}
        return nil
    }

    func translateItems(_ items: [NewsItem]) async -> [NewsItem] {
        var result: [NewsItem] = []
        for item in items {
            var newItem = item
            if let translatedTitle = await translateToKorean(item.title) {
                newItem = NewsItem(
                    providerId: item.providerId,
                    providerName: item.providerName,
                    source: item.source,
                    title: translatedTitle,
                    url: item.url,
                    publishedAt: item.publishedAt,
                    summary: item.summary,
                    rawText: item.rawText
                )
            }
            result.append(newItem)
        }
        return result
    }
}

// MARK: - Simple RSS Parser

struct RSSItem {
    let title: String
    let link: String
    let description: String
    let pubDate: Date
}

class SimpleRSSParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var insideItem = false

    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse() -> [RSSItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            insideItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
        }
        // Atom <link> support
        if insideItem && elementName == "link" {
            if let href = attributeDict["href"] {
                currentLink = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description", "summary", "content":
            currentDescription += string
        case "pubDate", "published", "updated":
            currentPubDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" || elementName == "entry" {
            insideItem = false

            let dateStr = currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)
            let pubDate = Self.parseDate(dateStr)

            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

            // HTML 제거
            var desc = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            desc = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            desc = desc.replacingOccurrences(of: "&nbsp;", with: " ")
            desc = desc.replacingOccurrences(of: "&lt;", with: "<")
            desc = desc.replacingOccurrences(of: "&gt;", with: ">")
            desc = desc.replacingOccurrences(of: "&amp;", with: "&")
            desc = desc.replacingOccurrences(of: "&quot;", with: "\"")
            desc = desc.replacingOccurrences(of: "&#39;", with: "'")

            if !title.isEmpty {
                items.append(RSSItem(
                    title: title,
                    link: link,
                    description: String(desc.prefix(500)),
                    pubDate: pubDate
                ))
            }
        }
    }

    /// 다양한 날짜 형식 파싱
    private static func parseDate(_ dateStr: String) -> Date {
        let formatters: [String] = [
            "EEE, dd MMM yyyy HH:mm:ss Z",      // RSS 2.0
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",            // Atom / ISO 8601
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]

        for format in formatters {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            if let date = f.date(from: dateStr) {
                return date
            }
        }

        return Date()
    }
}
