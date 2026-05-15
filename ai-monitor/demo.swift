#!/usr/bin/env swift

// AI News Watch - Command Line Demo
// 실제 앱의 핵심 로직을 테스트하기 위한 커맨드라인 버전

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Models

struct NewsItem: Codable {
    let id = UUID()
    let providerId: String
    let providerName: String
    let source: String
    let title: String
    let url: String
    let publishedAt: Date
    let summary: String
    let rawText: String
    let meta: String
}

struct NewsConfig {
    let providers: [Provider]
    let nitterInstances: [String]
    let windowHours: Int
    
    struct Provider {
        let id: String
        let name: String
        let xHandles: [String]
        let rssUrls: [String]
        let webUrls: [String]
    }
}

// MARK: - News Collector

class NewsCollector {
    let config: NewsConfig
    
    init(config: NewsConfig) {
        self.config = config
    }
    
    func collect() async throws -> [NewsItem] {
        print("📡 뉴스 수집 시작...")
        print("⏱️  범위: 최근 \(config.windowHours)시간")
        print("")
        
        var allItems: [NewsItem] = []
        let cutoffDate = Date().addingTimeInterval(-Double(config.windowHours) * 3600)
        
        for provider in config.providers {
            print("🔍 \(provider.name) 수집 중...")
            
            // X (Nitter)
            for handle in provider.xHandles {
                print("  - X: @\(handle)", terminator: "")
                let items = try await fetchNitter(
                    handle: handle,
                    providerId: provider.id,
                    providerName: provider.name,
                    cutoffDate: cutoffDate
                )
                print(" ✓ \(items.count)개")
                allItems.append(contentsOf: items)
            }
            
            // RSS
            for rssUrl in provider.rssUrls {
                print("  - RSS: \(URL(string: rssUrl)?.host ?? "RSS")", terminator: "")
                let items = try await fetchRSS(
                    url: rssUrl,
                    providerId: provider.id,
                    providerName: provider.name,
                    cutoffDate: cutoffDate
                )
                print(" ✓ \(items.count)개")
                allItems.append(contentsOf: items)
            }
            
            // Web
            for webUrl in provider.webUrls {
                print("  - Web: \(URL(string: webUrl)?.host ?? "Web")", terminator: "")
                if webUrl.contains("anthropic.com/news") {
                    let items = try await fetchAnthropicNews(
                        providerId: provider.id,
                        providerName: provider.name,
                        cutoffDate: cutoffDate
                    )
                    print(" ✓ \(items.count)개")
                    allItems.append(contentsOf: items)
                } else {
                    print(" ⊘ 지원 안 됨")
                }
            }
            
            print("")
        }
        
        // 중복 제거
        allItems = deduplicate(allItems)
        
        print("✅ 총 \(allItems.count)개 뉴스 수집 완료")
        print("")
        
        return allItems.sorted { $0.publishedAt > $1.publishedAt }
    }
    
    // MARK: - Nitter
    
    private func fetchNitter(
        handle: String,
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) async throws -> [NewsItem] {
        for instance in config.nitterInstances {
            let urlString = "\(instance)/\(handle.replacingOccurrences(of: "@", with: ""))"
            guard let url = URL(string: urlString) else { continue }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }
                
                let html = String(data: data, encoding: .utf8) ?? ""
                let items = parseNitterHTML(
                    html: html,
                    instance: instance,
                    handle: handle,
                    providerId: providerId,
                    providerName: providerName,
                    cutoffDate: cutoffDate
                )
                
                if !items.isEmpty {
                    return items
                }
            } catch {
                continue
            }
        }
        
        return []
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
        
        // timeline-item으로 분할
        let chunks = html.components(separatedBy: "<div class=\"timeline-item")
        
        for chunk in chunks.dropFirst().prefix(12) {
            // URL 추출
            guard let hrefRange = chunk.range(of: #"href="(/[^"]+/status/[^"]+)""#, options: .regularExpression) else {
                continue
            }
            let hrefMatch = String(chunk[hrefRange])
            let href = hrefMatch
                .replacingOccurrences(of: "href=\"", with: "")
                .replacingOccurrences(of: "\"", with: "")
            
            // 날짜 추출
            guard let dateRange = chunk.range(of: #"title="([^"]+UTC)""#, options: .regularExpression) else {
                continue
            }
            let dateMatch = String(chunk[dateRange])
            let dateStr = dateMatch
                .replacingOccurrences(of: "title=\"", with: "")
                .replacingOccurrences(of: "\"", with: "")
            
            guard let date = parseNitterDate(dateStr) else { continue }
            if date < cutoffDate { continue }
            
            // 내용 추출
            guard let contentRange = chunk.range(of: #"<div class="tweet-content[^>]*>(.+?)</div>"#, options: .regularExpression) else {
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
                rawText: content,
                meta: ""
            ))
        }
        
        return items
    }
    
    private func parseNitterDate(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        
        // "Feb 9, 2026 · 5:20 PM UTC"
        formatter.dateFormat = "MMM d, yyyy · h:mm a z"
        if let date = formatter.date(from: dateStr) {
            return date
        }
        
        // "Feb 9, 2026 · 17:20 UTC"
        formatter.dateFormat = "MMM d, yyyy · HH:mm z"
        return formatter.date(from: dateStr)
    }
    
    // MARK: - RSS
    
    private func fetchRSS(
        url: String,
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) async throws -> [NewsItem] {
        guard let requestUrl = URL(string: url) else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: requestUrl)
        
        // 간단한 RSS 파싱 (실제로는 XMLParser 사용)
        let xml = String(data: data, encoding: .utf8) ?? ""
        
        var items: [NewsItem] = []
        let itemRegex = try NSRegularExpression(pattern: "<item>(.+?)</item>", options: .dotMatchesLineSeparators)
        let matches = itemRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        
        for match in matches.prefix(10) {
            guard let range = Range(match.range(at: 1), in: xml) else { continue }
            let itemXML = String(xml[range])
            
            let title = extractXMLTag(itemXML, tag: "title")
            let link = extractXMLTag(itemXML, tag: "link")
            let pubDateStr = extractXMLTag(itemXML, tag: "pubDate")
            let description = extractXMLTag(itemXML, tag: "description")
            
            guard let pubDate = parseRFC822Date(pubDateStr) else { continue }
            if pubDate < cutoffDate { continue }
            
            items.append(NewsItem(
                providerId: providerId,
                providerName: providerName,
                source: "RSS",
                title: title,
                url: link,
                publishedAt: pubDate,
                summary: stripHTML(description),
                rawText: "\(title)\n\(description)",
                meta: ""
            ))
        }
        
        return items
    }
    
    private func parseRFC822Date(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.date(from: dateStr)
    }
    
    private func extractXMLTag(_ xml: String, tag: String) -> String {
        let pattern = "<\(tag)>(.+?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return ""
        }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Anthropic Web
    
    private func fetchAnthropicNews(
        providerId: String,
        providerName: String,
        cutoffDate: Date
    ) async throws -> [NewsItem] {
        let listingUrl = "https://www.anthropic.com/news"
        guard let url = URL(string: listingUrl) else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""
        
        // 뉴스 링크 추출
        let linkRegex = try NSRegularExpression(pattern: #"href="(/news/[^"]+)""#)
        let matches = linkRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        var articleUrls: [String] = []
        for match in matches.prefix(10) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let path = String(html[range])
            let articleUrl = "https://www.anthropic.com\(path)"
            if !articleUrls.contains(articleUrl) {
                articleUrls.append(articleUrl)
            }
        }
        
        var items: [NewsItem] = []
        
        for articleUrl in articleUrls.prefix(5) {
            guard let url = URL(string: articleUrl) else { continue }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let html = String(data: data, encoding: .utf8) ?? ""
                
                // og:title 추출
                let title = extractMetaTag(html, property: "og:title")
                let description = extractMetaTag(html, property: "og:description")
                
                // 날짜 추출
                var date = Date()
                if let dateRange = html.range(of: #"<div class="body-3 agate">\s*([A-Z][a-z]{2}\s+\d{1,2},\s+\d{4})"#, options: .regularExpression) {
                    let match = String(html[dateRange])
                    if let dateStr = match.range(of: #"[A-Z][a-z]{2}\s+\d{1,2},\s+\d{4}"#, options: .regularExpression) {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM d, yyyy"
                        formatter.locale = Locale(identifier: "en_US")
                        if let parsed = formatter.date(from: String(match[dateStr])) {
                            date = parsed
                        }
                    }
                }
                
                if date < cutoffDate { continue }
                
                if !title.isEmpty {
                    items.append(NewsItem(
                        providerId: providerId,
                        providerName: providerName,
                        source: "WEB",
                        title: title,
                        url: articleUrl,
                        publishedAt: date,
                        summary: description,
                        rawText: "\(title)\n\(description)",
                        meta: ""
                    ))
                }
            } catch {
                continue
            }
        }
        
        return items
    }
    
    private func extractMetaTag(_ html: String, property: String) -> String {
        let pattern = "<meta\\s+property=\"\(property)\"\\s+content=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return ""
        }
        return String(html[range])
    }
    
    // MARK: - Utilities
    
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
}

// MARK: - Main

@main
struct AINewsWatchDemo {
    static func main() async {
        print("🚀 AI News Watch Demo")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")
        
        let config = NewsConfig(
            providers: [
                NewsConfig.Provider(
                    id: "openai",
                    name: "OpenAI",
                    xHandles: ["OpenAI"],
                    rssUrls: [],
                    webUrls: []
                ),
                NewsConfig.Provider(
                    id: "anthropic",
                    name: "Anthropic",
                    xHandles: ["AnthropicAI"],
                    rssUrls: [],
                    webUrls: ["https://www.anthropic.com/news"]
                ),
                NewsConfig.Provider(
                    id: "google",
                    name: "Google AI",
                    xHandles: ["GoogleAI"],
                    rssUrls: [],
                    webUrls: []
                )
            ],
            nitterInstances: [
                "https://nitter.poast.org",
                "https://nitter.privacydev.net",
                "https://nitter.net"
            ],
            windowHours: 24
        )
        
        let collector = NewsCollector(config: config)
        
        do {
            let items = try await collector.collect()
            
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📰 최근 24시간 뉴스 (\(items.count)개)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("")
            
            for (index, item) in items.enumerated().prefix(20) {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                let dateStr = formatter.string(from: item.publishedAt)
                
                print("\(index + 1). [\(item.providerName)] [\(item.source)] \(dateStr)")
                print("   \(item.title)")
                print("   🔗 \(item.url)")
                if !item.summary.isEmpty {
                    let shortSummary = String(item.summary.prefix(100))
                    print("   💬 \(shortSummary)...")
                }
                print("")
            }
            
            if items.count > 20 {
                print("... 외 \(items.count - 20)개 더 있음")
                print("")
            }
            
            // 제공사별 통계
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📊 제공사별 통계")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("")
            
            let grouped = Dictionary(grouping: items, by: { $0.providerId })
            for (providerId, providerItems) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
                let name = providerItems.first?.providerName ?? providerId
                print("  \(name): \(providerItems.count)개")
            }
            print("")
            
            // 소스별 통계
            let bySource = Dictionary(grouping: items, by: { $0.source })
            for (source, sourceItems) in bySource.sorted(by: { $0.value.count > $1.value.count }) {
                print("  \(source): \(sourceItems.count)개")
            }
            
            print("")
            print("✅ 완료!")
            
        } catch {
            print("❌ 오류 발생: \(error)")
            exit(1)
        }
    }
}
