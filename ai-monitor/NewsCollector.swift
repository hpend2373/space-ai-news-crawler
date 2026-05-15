import Foundation

struct CollectionResult {
    let allItems: [NewsItem]
    let trendingItems: [NewsItem]
    let digestItems: [NewsItem]
    let sourceHealth: [String]
}

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
        
        let totalSteps = Double(config.providers.count + 2) // providers + digest + trending
        var currentStep = 0.0
        
        // 1. 각 제공자별 뉴스 수집
        for provider in config.providers {
            currentStep += 1
            await progressHandler(currentStep / totalSteps, "\(provider.name) 수집 중...")
            
            // X (Nitter)
            for handle in provider.xHandles {
                let (items, errors) = await fetchNitterPosts(
                    handle: handle,
                    providerId: provider.id,
                    providerName: provider.name,
                    cutoffDate: cutoffDate
                )
                allItems.append(contentsOf: items)
                sourceHealth.append(contentsOf: errors)
            }
            
            // RSS
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
        
        // 3. X Trending
        if config.xTrending.enabled {
            currentStep += 1
            await progressHandler(currentStep / totalSteps, "트렌딩 수집 중...")
            
            let (trending, trendingErrors) = await fetchTrending(cutoffDate: cutoffDate)
            trendingItems = trending
            sourceHealth.append(contentsOf: trendingErrors)
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
    
    // MARK: - Nitter
    
    private func fetchNitterPosts(
        handle: String,
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) async -> ([NewsItem], [String]) {
        var items: [NewsItem] = []
        var errors: [String] = []
        
        for instance in config.nitter.instances {
            let url = "\(instance)/\(handle.replacingOccurrences(of: "@", with: ""))"
            
            guard let requestUrl = URL(string: url) else {
                errors.append("Nitter \(handle): 잘못된 URL")
                continue
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: requestUrl)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    errors.append("Nitter \(handle): HTTP 오류")
                    continue
                }
                
                let html = String(data: data, encoding: .utf8) ?? ""
                let parsed = parseNitterHTML(
                    html: html,
                    instance: instance,
                    handle: handle,
                    providerId: providerId,
                    providerName: providerName,
                    cutoffDate: cutoffDate
                )
                
                if parsed.isEmpty {
                    errors.append("Nitter \(handle): 파싱 실패 (0개)")
                } else {
                    items.append(contentsOf: parsed)
                    return (items, []) // 성공하면 바로 리턴
                }
                
            } catch {
                errors.append("Nitter \(handle): \(error.localizedDescription)")
            }
        }
        
        return (items, errors)
    }
    
    private func parseNitterHTML(
        html: String,
        instance: String,
        handle: String,
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) -> [NewsItem] {
        var items: [NewsItem] = []
        
        // 간단한 정규식 파싱 (실제로는 더 복잡한 HTML 파서 필요)
        // timeline-item으로 분할
        let chunks = html.components(separatedBy: "<div class=\"timeline-item")
        
        for chunk in chunks.dropFirst() {
            // URL 및 날짜 추출
            guard let urlMatch = chunk.range(of: "href=\"(/[^\"]+/status/[^\"]+)\""),
                  let dateMatch = chunk.range(of: "title=\"([^\"]+UTC)\"") else {
                continue
            }
            
            let href = String(chunk[urlMatch]).replacingOccurrences(of: "href=\"", with: "").replacingOccurrences(of: "\"", with: "")
            let dateStr = String(chunk[dateMatch]).replacingOccurrences(of: "title=\"", with: "").replacingOccurrences(of: "\"", with: "")
            
            // 날짜 파싱
            guard let date = parseNitterDate(dateStr) else { continue }
            if date < cutoffDate { continue }
            
            // 내용 추출
            guard let contentRange = chunk.range(of: "<div class=\"tweet-content[^>]*>(.+?)</div>", options: .regularExpression) else {
                continue
            }
            
            let contentHTML = String(chunk[contentRange])
            let content = stripHTML(contentHTML)
            
            if content.isEmpty { continue }
            
            let url = href.hasPrefix("http") ? href : "\(instance)\(href)"
            
            items.append(NewsItem(
                providerId: providerId,
                providerName: providerName,
                source: "X",
                title: String(content.prefix(140)),
                url: url,
                publishedAt: date,
                summary: String(content.prefix(420)),
                rawText: content
            ))
            
            if items.count >= config.nitter.maxPostsPerHandle {
                break
            }
        }
        
        return items
    }
    
    private func parseNitterDate(_ dateStr: String) -> Date? {
        // "Feb 9, 2026 · 5:20 PM UTC" 형식 파싱
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · h:mm a z"
        formatter.locale = Locale(identifier: "en_US")
        
        if let date = formatter.date(from: dateStr) {
            return date
        }
        
        // "Feb 9, 2026 · 17:20 UTC" 형식도 시도
        formatter.dateFormat = "MMM d, yyyy · HH:mm z"
        return formatter.date(from: dateStr)
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
            let (data, response) = try await URLSession.shared.data(from: requestUrl)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return ([], "HTTP 오류")
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
        // Anthropic 뉴스 페이지 파싱
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
            let (data, _) = try await URLSession.shared.data(from: requestUrl)
            let html = String(data: data, encoding: .utf8) ?? ""
            
            // href="/news/" 패턴 찾기
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
            
            // 각 아티클 가져오기
            for articleUrl in articleUrls {
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
            let (data, _) = try await URLSession.shared.data(from: requestUrl)
            let html = String(data: data, encoding: .utf8) ?? ""
            
            // og:title 추출
            var title = ""
            if let titleRange = html.range(of: "<meta property=\"og:title\" content=\"([^\"]+)\"", options: .regularExpression) {
                let match = String(html[titleRange])
                title = match.replacingOccurrences(of: "<meta property=\"og:title\" content=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }
            
            // og:description 추출
            var description = ""
            if let descRange = html.range(of: "<meta property=\"og:description\" content=\"([^\"]+)\"", options: .regularExpression) {
                let match = String(html[descRange])
                description = match.replacingOccurrences(of: "<meta property=\"og:description\" content=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }
            
            // 날짜 추출 (Anthropic는 "Feb 9, 2026" 형식)
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
            let url = "https://news.google.com/rss/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&hl=en-US&gl=US&ceid=US:en"
            
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
    
    // MARK: - Trending
    
    private func fetchTrending(cutoffDate: Date) async -> ([NewsItem], [String]) {
        // Nitter 검색 기능 (트렌딩)
        // 구현은 복잡하므로 간략화
        return ([], [])
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
        
        // HTML 엔티티 디코딩
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if elementName == "item" {
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description":
            currentDescription += string
        case "pubDate":
            currentPubDate += string
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            formatter.locale = Locale(identifier: "en_US")
            
            let pubDate = formatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Date()
            
            items.append(RSSItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: pubDate
            ))
        }
    }
}
