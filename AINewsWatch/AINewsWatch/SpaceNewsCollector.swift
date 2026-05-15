import Foundation

// MARK: - Space News Collector (직접 수집 - Google News RSS 기반)

struct SpaceNewsConfig {
    let sources: [SpaceSource]
    let maxItemsTotal: Int
    
    struct SpaceSource {
        let id: String
        let name: String
        let queries: [String]
    }
    
    static let defaultSpace = SpaceNewsConfig(
        sources: [
            SpaceSource(id: "spacex", name: "SpaceX", queries: [
                "스페이스X 발사",
                "SpaceX launch"
            ]),
            SpaceSource(id: "rocketlab", name: "Rocket Lab", queries: [
                "로켓랩 발사",
                "Rocket Lab launch"
            ]),
            SpaceSource(id: "blueorigin", name: "Blue Origin", queries: [
                "블루오리진 우주",
                "Blue Origin launch"
            ]),
            SpaceSource(id: "nasa", name: "NASA", queries: [
                "NASA 미션",
                "NASA mission 2026"
            ]),
            SpaceSource(id: "space_economy", name: "우주경제", queries: [
                "우주산업 뉴스",
                "위성 발사 2026",
                "space industry news"
            ]),
        ],
        maxItemsTotal: 40
    )
}

actor SpaceNewsCollector {
    let config: SpaceNewsConfig
    
    init(config: SpaceNewsConfig = .defaultSpace) {
        self.config = config
    }
    
    func collect(
        progressHandler: @MainActor @Sendable (Double, String) async -> Void
    ) async -> [SpaceCollectedItem] {
        var allItems: [SpaceCollectedItem] = []
        let totalSteps = Double(config.sources.count)
        var currentStep = 0.0
        
        for source in config.sources {
            currentStep += 1
            await progressHandler(currentStep / totalSteps, "\(source.name) 수집 중...")
            
            for query in source.queries {
                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let url = "https://news.google.com/rss/search?q=\(encoded)&hl=ko&gl=KR&ceid=KR:ko"
                
                let items = await fetchGoogleNewsRSS(url: url, sourceId: source.id, sourceName: source.name)
                allItems.append(contentsOf: items)
                
                if allItems.count >= config.maxItemsTotal { break }
            }
            
            if allItems.count >= config.maxItemsTotal { break }
        }
        
        let deduped = deduplicate(allItems)
        return Array(deduped.sorted { $0.publishedAt > $1.publishedAt }.prefix(config.maxItemsTotal))
    }
    
    private func fetchGoogleNewsRSS(url: String, sourceId: String, sourceName: String) async -> [SpaceCollectedItem] {
        guard let requestUrl = URL(string: url) else { return [] }
        
        do {
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            
            let parser = SpaceRSSParser(data: data, sourceId: sourceId, sourceName: sourceName)
            return parser.parse()
        } catch {
            return []
        }
    }
    
    private func deduplicate(_ items: [SpaceCollectedItem]) -> [SpaceCollectedItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = item.url.isEmpty ? "\(item.title)|\(item.publishedAt)" : item.url
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}

struct SpaceCollectedItem {
    let sourceId: String
    let sourceName: String
    let title: String
    let url: String
    let publishedAt: Date
    let summary: String
}

class SpaceRSSParser: NSObject, XMLParserDelegate {
    private var items: [SpaceCollectedItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var insideItem = false
    private let data: Data
    private let sourceId: String
    private let sourceName: String
    
    init(data: Data, sourceId: String, sourceName: String) {
        self.data = data
        self.sourceId = sourceId
        self.sourceName = sourceName
    }
    
    func parse() -> [SpaceCollectedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            insideItem = true
            currentTitle = ""; currentLink = ""; currentDescription = ""; currentPubDate = ""
        }
        if insideItem && elementName == "link", let href = attributeDict["href"] {
            currentLink = href
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        case "description", "summary": currentDescription += string
        case "pubDate", "published", "updated": currentPubDate += string
        default: break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" || elementName == "entry" {
            insideItem = false
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            var desc = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            desc = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            desc = desc.replacingOccurrences(of: "&amp;", with: "&")
            let pubDate = Self.parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            
            if !title.isEmpty {
                items.append(SpaceCollectedItem(
                    sourceId: sourceId, sourceName: sourceName,
                    title: title, url: link, publishedAt: pubDate,
                    summary: String(desc.prefix(500))
                ))
            }
        }
    }
    
    private static func parseDate(_ dateStr: String) -> Date {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd"
        ]
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            if let date = f.date(from: dateStr) { return date }
        }
        return Date()
    }
}
