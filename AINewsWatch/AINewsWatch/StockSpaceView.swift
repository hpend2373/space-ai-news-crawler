import SwiftUI

// MARK: - BriefItem Model

struct BriefItem: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let reason: String
    let articleCount: Int
    let issueCount: Int
    let headlines: [String]
    let timestamp: String
    let sources: String
    let category: String?
    let sourceQuality: Int
    init(title:String,summary:String,reason:String,articleCount:Int,issueCount:Int,headlines:[String],timestamp:String,sources:String,category:String?=nil,sourceQuality:Int=0){
        self.title=title;self.summary=summary;self.reason=reason;self.articleCount=articleCount;self.issueCount=issueCount;self.headlines=headlines;self.timestamp=timestamp;self.sources=sources;self.category=category;self.sourceQuality=sourceQuality
    }

    var hasIssue: Bool { issueCount > 0 || (!summary.contains("큰 이슈 없음") && !summary.isEmpty) }
    var isSpaceEconomy: Bool {
        title.contains("우주경제") || title.contains("Space Economy")
    }

    var iconName: String {
        if isSpaceEconomy { return "globe.asia.australia.fill" }
        if title.lowercased().contains("spacex") { return "flame.fill" }
        if title.lowercased().contains("rocket lab") { return "airplane" }
        if title.lowercased().contains("planet lab") { return "globe.americas.fill" }
        if hasIssue { return "exclamationmark.triangle.fill" }
        return "chart.bar.fill"
    }
}


// MARK: - Issue Classification & Source Scoring
struct SpaceAnalyzer {
    static func classifyBigIssue(_ title: String) -> String? {
        let t = title.lowercased()
        let cats: [(String, [String])] = [
            ("M&A", ["acquire","acquisition","merge","merger","buyout","takeover","인수","합병"]),
            ("자금조달", ["ipo","funding","raise","capital","offering","상장","투자유치"]),
            ("실적", ["earnings","revenue","profit","guidance","quarterly","실적","매출"]),
            ("발사사고", ["explosion","failure","abort","anomaly","delay","폭발","실패","사고","연기"]),
            ("계약", ["contract","award","partnership","deal","agreement","계약","수주"]),
            ("규제", ["regulatory","faa","fcc","antitrust","lawsuit","규제","소송"]),
            ("발사", ["launch","mission","deploy","orbit","landing","발사","배치"]),
            ("경영진", ["ceo","cto","executive","appoint","resign","임명","사임"]),
        ]
        for (cat, kws) in cats { for kw in kws { if t.contains(kw) { return cat } } }
        return nil
    }
    static func sourceScore(_ name: String) -> Int {
        let n = name.lowercased()
        if ["rocket lab","nasa.gov","spacex.com"].contains(where:{n.contains($0)}){return 6}
        if ["spacenews","spaceflight now"].contains(where:{n.contains($0)}){return 5}
        if ["reuters","bloomberg","cnbc","wsj"].contains(where:{n.contains($0)}){return 4}
        if ["techcrunch","verge","bbc","cnn"].contains(where:{n.contains($0)}){return 3}
        if ["marketbeat","motley fool","benzinga","seeking alpha"].contains(where:{n.contains($0)}){return -4}
        return 1
    }
    static func whyItMatters(_ cat: String?) -> String {
        guard let c = cat else { return "참고할 만한 뉴스입니다." }
        if c.contains("M&A"){return "기업 구조변경은 주가 시장에 영향 미칩니다."}
        if c.contains("자금"){return "자금조달은 성장전략 주식할인에 영향 미칩니다."}
        if c.contains("실적"){return "실적은 기업가치 평가에 핵심적입니다."}
        if c.contains("사고"){return "발사사고는 수익에 심각한 영향을 미칩니다."}
        if c.contains("계약"){return "신규계약은 매출파이프라인을 보여줍니다."}
        if c.contains("규제"){return "규제변화는 사업운영에 영향 미칩니다."}
        if c.contains("발사"){return "발사성공은 기술력을 수익에 반영하는 지표입니다."}
        if c.contains("경영"){return "경영진변동은 전략변화를 시사합니다."}
        return "참고할 만한 뉴스입니다."
    }
}

// MARK: - Watchlist Manager
class WatchlistManager: ObservableObject {
    static let shared = WatchlistManager()
    private let key = "watchlistTickers"
    @Published var tickers: [String] {
        didSet { UserDefaults.standard.set(tickers, forKey: key) }
    }
    private init() {
        self.tickers = UserDefaults.standard.stringArray(forKey: key) ?? ["RKLB", "PL", "SpaceX"]
    }
    func add(_ ticker: String) {
        let t = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard !t.isEmpty, !tickers.contains(t) else { return }
        tickers.append(t)
    }
    func remove(at offsets: IndexSet) { tickers.remove(atOffsets: offsets) }
    func move(from src: IndexSet, to dst: Int) { tickers.move(fromOffsets: src, toOffset: dst) }
}

// MARK: - Watch Profile (macOS _watch_profile equivalent)
struct WatchProfile {
    let displayName: String
    let termsEN: [String]
    let termsKR: [String]
    let secCIK: String?
    let rssFeeds: [String]
    let googleQueries: [(String, String)]

    func titleMentions(_ title: String) -> Bool {
        let t = title.lowercased()
        return termsEN.contains(where: { t.contains($0) }) || termsKR.contains(where: { t.contains($0) })
    }

    static func profile(for ticker: String) -> WatchProfile {
        switch ticker.uppercased() {
        case "RKLB":
            return WatchProfile(
                displayName: "Rocket Lab (RKLB)",
                termsEN: ["rocket lab","rocketlab","rklb","electron","neutron","khosla"],
                termsKR: ["\u{B85C}\u{CF13}\u{B7A9}"],
                secCIK: "0001819994",
                rssFeeds: ["https://www.rocketlabusa.com/updates/rss/"],
                googleQueries: [
                    ("\"Rocket Lab\" (launch OR electron OR neutron OR RKLB)", "\u{B85C}\u{CF13}\u{B7A9} (\u{BC1C}\u{C0AC} OR \u{ACC4}\u{C57D})"),
                    ("\"Rocket Lab\" (contract OR partnership OR defense)", "\u{B85C}\u{CF13}\u{B7A9} (\u{BC29}\u{C0B0} OR \u{ACC4}\u{C57D})")
                ]
            )
        case "PL":
            return WatchProfile(
                displayName: "Planet Labs (PL)",
                termsEN: ["planet labs","planetscope","planet.com","pelican","tanager","skysat","dove"],
                termsKR: ["\u{D50C}\u{B798}\u{B2DB}\u{B7A9}\u{C2A4}"],
                secCIK: "0001836935",
                rssFeeds: ["https://www.planet.com/pulse/rss/"],
                googleQueries: [
                    ("\"Planet Labs\" (satellite OR imagery OR Pelican OR Tanager)", "\u{D50C}\u{B798}\u{B2DB} \u{B7A9}\u{C2A4} (\u{C704}\u{C131} OR \u{C601}\u{C0C1})"),
                    ("\"Planet Labs\" (contract OR government OR defense)", "\u{D50C}\u{B798}\u{B2DB}\u{B7A9}\u{C2A4} (\u{ACC4}\u{C57D} OR \u{BC29}\u{C0B0})")
                ]
            )
        case "SPACEX":
            return WatchProfile(
                displayName: "SpaceX",
                termsEN: ["spacex","starship","falcon","starlink","dragon"],
                termsKR: ["\u{C2A4}\u{D398}\u{C774}\u{C2A4}x","\u{C2A4}\u{D398}\u{C774}\u{C2A4}\u{C5D1}\u{C2A4}"],
                secCIK: nil,
                rssFeeds: [],
                googleQueries: [
                    ("SpaceX (launch OR Starship OR Falcon OR Starlink)", "\u{C2A4}\u{D398}\u{C774}\u{C2A4}X (\u{BC1C}\u{C0AC} OR \u{C2A4}\u{D0C0}\u{C2ED})"),
                    ("SpaceX (contract OR NASA OR military OR defense)", "\u{C2A4}\u{D398}\u{C774}\u{C2A4}X (\u{ACC4}\u{C57D} OR \u{BC29}\u{C0B0})")
                ]
            )
        default:
            return WatchProfile(
                displayName: ticker,
                termsEN: [ticker.lowercased()],
                termsKR: [],
                secCIK: nil,
                rssFeeds: [],
                googleQueries: [("\(ticker) space", "\(ticker)")]
            )
        }
    }
}

// MARK: - SEC Filing
struct SECFiling {
    let form: String
    let filingDate: String
    let description: String
    let url: String
}

// MARK: - SEC Fetcher (macOS EDGAR equivalent)
actor SECFetcher {
    static let shared = SECFetcher()
    private let importantForms = ["10-K","10-Q","8-K","S-1","6-K","20-F","DEF 14A","SC 13D","SC 13G"]

    func recentFilings(cik: String) async -> [SECFiling] {
        let cleaned = cik.drop(while: { $0 == "0" })
        let padded = String(repeating: "0", count: max(0, 10 - cleaned.count)) + cleaned
        let urlStr = "https://data.sec.gov/submissions/CIK\(padded).json"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.setValue("AINewsWatch/1.0 contact@example.com", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let filings = json["filings"] as? [String: Any],
                  let recentObj = filings["recent"] as? [String: Any],
                  let forms = recentObj["form"] as? [String],
                  let dates = recentObj["filingDate"] as? [String],
                  let names = recentObj["primaryDocument"] as? [String],
                  let accessions = recentObj["accessionNumber"] as? [String]
            else { return [] }
            let cutoff = Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? Date()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            var results: [SECFiling] = []
            for i in 0..<min(forms.count, dates.count, names.count, accessions.count) {
                guard importantForms.contains(forms[i]),
                      let d = df.date(from: dates[i]), d >= cutoff else { continue }
                let accClean = accessions[i].replacingOccurrences(of: "-", with: "")
                let cikNum = String(cleaned)
                let fileUrl = "https://www.sec.gov/Archives/edgar/data/\(cikNum)/\(accClean)/\(names[i])"
                results.append(SECFiling(form: forms[i], filingDate: dates[i], description: names[i], url: fileUrl))
                if results.count >= 5 { break }
            }
            return results
        } catch {
            print("SEC fetch error: \(error)")
            return []
        }
    }
}


// MARK: - BriefViewModel (HTTP + Direct RSS — iOS)

@MainActor
final class BriefViewModel: ObservableObject {
    @Published var briefItems: [BriefItem] = []
    @Published var inboxText: String = ""
    @Published var statusText: String = "준비됨"
    @Published var isRunning: Bool = false
    @Published var metadata: String = ""
    @Published var lastDataSource: String = ""

    var serverHost: String {
        didSet { UserDefaults.standard.set(serverHost, forKey: "spaceServerHost") }
    }
    var serverPort: Int {
        didSet { UserDefaults.standard.set(serverPort, forKey: "spaceServerPort") }
    }

    init() {
        self.serverHost = UserDefaults.standard.string(forKey: "spaceServerHost")
            ?? UserDefaults.standard.string(forKey: "serverHost")
            ?? "127.0.0.1"
        self.serverPort = UserDefaults.standard.integer(forKey: "spaceServerPort")
        if self.serverPort == 0 { self.serverPort = 8766 }
    }

    func refresh() async {
        guard !isRunning else { return }
        isRunning = true
        statusText = "데이터 로드 중..."

        let mode = UserDefaults.standard.string(forKey: "dataSourceMode") ?? "auto"

        switch mode {
        case "server":
            if let text = await fetchFromHTTP() {
                inboxText = text
                parseInbox()
                lastDataSource = "서버"
                statusText = briefItems.isEmpty ? "파싱 결과 없음" : "서버 (\(briefItems.count)개)"
            } else {
                statusText = "서버 연결 실패"
            }
        case "direct":
            await refreshFromDirectRSS()
        default: // auto
            if let text = await fetchFromHTTP() {
                inboxText = text
                parseInbox()
                lastDataSource = "서버"
                statusText = briefItems.isEmpty ? "파싱 결과 없음" : "서버 (\(briefItems.count)개)"
            } else {
                print("⚠️ 우주 뉴스 서버 연결 실패, 직접 RSS 수집으로 전환")
                await refreshFromDirectRSS()
            }
        }

        isRunning = false
    }

    private func fetchFromHTTP() async -> String? {
        let urlStr = "http://\(serverHost):\(serverPort)/inbox.md"
        guard let url = URL(string: urlStr) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            print("Stock space fetch error: \(error)")
            return nil
        }
    }

    // MARK: - 직접 RSS 수집 (Google News)

    /// macOS space_stock_brief.py main() equivalent - per-ticker collection
    private func refreshFromDirectRSS() async {
        statusText = "Collecting news per ticker..."
        let collector = NewsCollector(config: .defaultSpace)
        let result = await collector.collect(windowHours: 48) { progress, message in
            self.statusText = message
        }
        let allNews = result.allItems + result.digestItems
        
        var items: [BriefItem] = []
        let tickers = WatchlistManager.shared.tickers
        var usedIds = Set<UUID>()
        
        for ticker in tickers {
            let profile = WatchProfile.profile(for: ticker)
            
            // Filter news for this ticker
            var tickerNews: [NewsItem]
            if ticker.uppercased() == "SPACEX" {
                tickerNews = allNews.filter { item in
                    guard !usedIds.contains(item.id) else { return false }
                    let t = item.title.lowercased()
                    let isSpaceX = profile.titleMentions(item.title)
                    let isGenericSpace = t.contains("space") && !t.contains("rocket lab") && !t.contains("planet lab")
                    return isSpaceX || isGenericSpace
                }
            } else {
                tickerNews = allNews.filter { item in
                    guard !usedIds.contains(item.id) else { return false }
                    return profile.titleMentions(item.title)
                }
            }
            
            // Mark used
            for item in tickerNews { usedIds.insert(item.id) }
            
            // Sort by source quality
            let sorted = tickerNews.sorted { SpaceAnalyzer.sourceScore($0.providerName) > SpaceAnalyzer.sourceScore($1.providerName) }
            
            // Classify issues
            var issueItems: [(NewsItem, String)] = []
            var normalItems: [NewsItem] = []
            for item in sorted {
                if let cat = SpaceAnalyzer.classifyBigIssue(item.title) {
                    issueItems.append((item, cat))
                } else {
                    normalItems.append(item)
                }
            }
            
            let sortedIssues = issueItems.sorted { SpaceAnalyzer.sourceScore($0.0.providerName) > SpaceAnalyzer.sourceScore($1.0.providerName) }
            let sortedNormals = normalItems
            
            // SEC filings
            var secHeadlines: [String] = []
            if let cik = profile.secCIK {
                let filings = await SECFetcher.shared.recentFilings(cik: cik)
                for f in filings {
                    secHeadlines.append("\u{1F4CB} SEC \(f.form): \(f.description) (\(f.filingDate))")
                }
            }
            
            // Build headlines
            var headlines: [String] = secHeadlines
            for (item, cat) in sortedIssues.prefix(5) {
                let badge = SpaceAnalyzer.sourceScore(item.providerName) >= 4 ? "\u{2B50}" : "\u{1F4F0}"
                let ts = item.publishedAt.formatted(date: .abbreviated, time: .shortened)
                headlines.append("\(badge)[\(cat)] \(ts) \u{2014} \(item.title)")
            }
            for item in sortedNormals.prefix(5) {
                let badge = SpaceAnalyzer.sourceScore(item.providerName) >= 4 ? "\u{2B50}" : ""
                let ts = item.publishedAt.formatted(date: .abbreviated, time: .shortened)
                headlines.append("\(badge)\(ts) \u{2014} \(item.title)")
            }
            
            let sources = Array(Set(tickerNews.map{$0.providerName})).joined(separator: ", ")
            let ic = issueItems.count
            let avg = tickerNews.isEmpty ? 0 : tickerNews.map{SpaceAnalyzer.sourceScore($0.providerName)}.reduce(0,+)/tickerNews.count
            
            let summary: String; let reason: String; let mainCat: String?
            if !sortedIssues.isEmpty {
                let cats = Array(Set(sortedIssues.map{$0.1}))
                mainCat = cats.first
                let catStr = cats.joined(separator: ", ")
                summary = "\u{1F6A8} New big issue \(ic) (\(catStr))"
                let top = sortedIssues.first!.0.title
                reason = "\(top)\n\(SpaceAnalyzer.whyItMatters(mainCat))"
            } else {
                mainCat = nil
                let hp = sortedNormals.prefix(3).map{$0.title}.joined(separator: " / ")
                summary = "No big issues (\(tickerNews.count) articles)"
                reason = hp.isEmpty ? "No recent events" : "Headlines: \(hp)"
            }
            
            items.append(BriefItem(
                title: profile.displayName,
                summary: summary,
                reason: reason,
                articleCount: tickerNews.count,
                issueCount: ic,
                headlines: headlines,
                timestamp: Date().formatted(date: .abbreviated, time: .shortened),
                sources: sources,
                category: mainCat,
                sourceQuality: avg
            ))
        }
        
        // Space Economy catch-all section
        let spaceEconNews = allNews.filter { item in
            guard !usedIds.contains(item.id) else { return false }
            return isSpaceEconRelevant(item)
        }
        
        if !spaceEconNews.isEmpty {
            for item in spaceEconNews { usedIds.insert(item.id) }
            let sorted2 = spaceEconNews.sorted { SpaceAnalyzer.sourceScore($0.providerName) > SpaceAnalyzer.sourceScore($1.providerName) }
            var issueItems2: [(NewsItem, String)] = []
            var normalItems2: [NewsItem] = []
            for item in sorted2 {
                if let cat = SpaceAnalyzer.classifyBigIssue(item.title) {
                    issueItems2.append((item, cat))
                } else {
                    normalItems2.append(item)
                }
            }
            let sortedIssues2 = issueItems2.sorted { SpaceAnalyzer.sourceScore($0.0.providerName) > SpaceAnalyzer.sourceScore($1.0.providerName) }
            
            var headlines2: [String] = []
            for (item, cat) in sortedIssues2.prefix(5) {
                let badge = SpaceAnalyzer.sourceScore(item.providerName) >= 4 ? "\u{2B50}" : "\u{1F4F0}"
                let ts = item.publishedAt.formatted(date: .abbreviated, time: .shortened)
                headlines2.append("\(badge)[\(cat)] \(ts) \u{2014} \(item.title)")
            }
            for item in normalItems2.prefix(5) {
                let ts = item.publishedAt.formatted(date: .abbreviated, time: .shortened)
                headlines2.append("\(ts) \u{2014} \(item.title)")
            }
            let sources2 = Array(Set(spaceEconNews.map{$0.providerName})).joined(separator: ", ")
            let ic2 = issueItems2.count
            let avg2 = spaceEconNews.isEmpty ? 0 : spaceEconNews.map{SpaceAnalyzer.sourceScore($0.providerName)}.reduce(0,+)/spaceEconNews.count
            
            let summary2: String; let reason2: String; let mainCat2: String?
            if !sortedIssues2.isEmpty {
                let cats2 = Array(Set(sortedIssues2.map{$0.1}))
                mainCat2 = cats2.first
                let catStr2 = cats2.joined(separator: ", ")
                summary2 = "\u{1F6A8} Big issues \(ic2) (\(catStr2))"
                let top2 = sortedIssues2.first!.0.title
                reason2 = "\(top2)\n\(SpaceAnalyzer.whyItMatters(mainCat2))"
            } else {
                mainCat2 = nil
                let hp2 = normalItems2.prefix(3).map{$0.title}.joined(separator: " / ")
                summary2 = "No big issues (\(spaceEconNews.count) articles)"
                reason2 = hp2.isEmpty ? "No recent events" : "Headlines: \(hp2)"
            }
            
            items.append(BriefItem(
                title: "Space Economy",
                summary: summary2,
                reason: reason2,
                articleCount: spaceEconNews.count,
                issueCount: ic2,
                headlines: headlines2,
                timestamp: Date().formatted(date: .abbreviated, time: .shortened),
                sources: sources2,
                category: mainCat2,
                sourceQuality: avg2
            ))
        }
        
        briefItems = items.sorted {
            if $0.issueCount != $1.issueCount { return $0.issueCount > $1.issueCount }
            return $0.sourceQuality > $1.sourceQuality
        }
        lastDataSource = "Direct RSS"
        metadata = "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))"
        statusText = briefItems.isEmpty ? "No results" : "Direct collection done (\(briefItems.count) sections)"
        print("\u{2705} Direct RSS: \(allNews.count) items \u{2192} \(briefItems.count) sections")
    }
    
    /// macOS _space_econ_relevant equivalent
    private func isSpaceEconRelevant(_ item: NewsItem) -> Bool {
        let src = item.providerName.lowercased()
        if src == "spacenews" { return true }
        let t = item.title.lowercased()
        let pattern = "contract|award|deal|partnership|agreement|budget|policy|regulation|license|faa|fcc|satellite|launch|rocket|spacecraft|payload|orbit|iss|space station|artemis|starship|falcon|dragon|starlink|ariane|ula|blue origin|rocket lab|planet labs|spacex|space force|defense"
        if t.range(of: pattern, options: .regularExpression) != nil { return true }
        let krPattern = "\u{C6B0}\u{C8FC}|\u{C704}\u{C131}|\u{BC1C}\u{C0AC}|\u{B85C}\u{CF13}|\u{ACC4}\u{C57D}|\u{C218}\u{C8FC}|\u{C608}\u{C0B0}|\u{C815}\u{CC45}|\u{ADE0}\u{C81C}|\u{C0C1}\u{C5C5}\u{C6B0}\u{C8FC}|\u{BC29}\u{C0B0}|\u{C2A4}\u{D398}\u{C774}\u{C2A4}"
        if t.range(of: krPattern, options: .regularExpression) != nil { return true }
        return false
    }


    // MARK: - Inbox Parser (macOS와 동일 로직)

    private func parseInbox() {
        guard !inboxText.isEmpty else {
            briefItems = []
            return
        }

        let lines = inboxText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var items: [BriefItem] = []

        let fieldPrefixes = ["무슨 일", "왜 중요한지", "날짜", "출처", "HTML 대시보드",
                             "[리포트", "리포트 파일", "리포트 URL", "에이전트 버전",
                             "생성 시각", "신규 윈도우", "검색 윈도우", "워치리스트"]

        // Extract metadata
        var metaLines: [String] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if lines[i].starts(with: "## ") { break }
            if !trimmed.isEmpty && fieldPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                metaLines.append(lines[i])
            } else if !metaLines.isEmpty && !trimmed.isEmpty {
                break
            }
            i += 1
            if i > 20 { break }
        }
        metadata = metaLines.joined(separator: "\n")

        // Parse sections
        var currentTitle = ""
        var currentSummary = ""
        var currentReason = ""
        var currentArticleCount = 0
        var currentIssueCount = 0
        var currentHeadlines: [String] = []
        var currentTimestamp = ""
        var currentSources = ""

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let isSectionHeader = line.starts(with: "## ") || (
                !trimmedLine.isEmpty
                && index > 0
                && lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
                && !fieldPrefixes.contains(where: { trimmedLine.hasPrefix($0) })
            )

            if isSectionHeader {
                if !currentTitle.isEmpty {
                    items.append(BriefItem(
                        title: currentTitle, summary: currentSummary, reason: currentReason,
                        articleCount: currentArticleCount, issueCount: currentIssueCount,
                        headlines: currentHeadlines, timestamp: currentTimestamp, sources: currentSources
                    ))
                }

                currentTitle = line.starts(with: "## ")
                    ? String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                    : trimmedLine
                currentSummary = ""
                currentReason = ""
                currentArticleCount = 0
                currentIssueCount = 0
                currentHeadlines = []
                currentTimestamp = ""
                currentSources = ""

            } else if line.contains("무슨 일") && line.contains(":") {
                currentSummary = line.replacingOccurrences(of: "**무슨 일**:", with: "")
                    .replacingOccurrences(of: "무슨 일:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if line.contains("관련 기사") {
                    let components = line.components(separatedBy: " ")
                    for (idx, comp) in components.enumerated() {
                        if comp.contains("기사") && idx < components.count - 1 {
                            let numStr = components[idx + 1]
                                .replacingOccurrences(of: "건)", with: "")
                                .replacingOccurrences(of: "건,", with: "")
                                .replacingOccurrences(of: "건", with: "")
                                .replacingOccurrences(of: ",", with: "")
                            if let count = Int(numStr) {
                                currentArticleCount = count
                            }
                        }
                    }
                }

                if line.contains("이슈 기준 충족") {
                    let components = line.components(separatedBy: " ")
                    for (idx, comp) in components.enumerated() {
                        if comp.contains("충족") && idx < components.count - 1 {
                            let numStr = components[idx + 1]
                                .replacingOccurrences(of: "건)", with: "")
                                .replacingOccurrences(of: "건,", with: "")
                                .replacingOccurrences(of: "건", with: "")
                            if let count = Int(numStr) {
                                currentIssueCount = count
                            }
                        }
                    }
                }

            } else if line.contains("왜 중요한지") && line.contains(":") {
                currentReason = line.replacingOccurrences(of: "**왜 중요한지**:", with: "")
                    .replacingOccurrences(of: "왜 중요한지:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if line.contains("헤드라인:") {
                    let headlinePart = line.components(separatedBy: "헤드라인:").last ?? ""
                    currentHeadlines = headlinePart.components(separatedBy: " / ")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }

            } else if line.contains("날짜") && line.contains(":") {
                currentTimestamp = line.replacingOccurrences(of: "**날짜**:", with: "")
                    .replacingOccurrences(of: "날짜:", with: "")
                    .trimmingCharacters(in: .whitespaces)

            } else if line.contains("출처") && line.contains(":") {
                currentSources = line.replacingOccurrences(of: "**출처**:", with: "")
                    .replacingOccurrences(of: "출처:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        if !currentTitle.isEmpty {
            items.append(BriefItem(
                title: currentTitle, summary: currentSummary, reason: currentReason,
                articleCount: currentArticleCount, issueCount: currentIssueCount,
                headlines: currentHeadlines, timestamp: currentTimestamp, sources: currentSources
            ))
        }

        briefItems = items
    }
}

// MARK: - StockSpaceContentView (Apple HIG — Warm Cream)

struct StockSpaceContentView: View {
    @StateObject private var vm = BriefViewModel()
    @State private var showWatchlistEditor = false
    let onBackToHome: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DS.cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    statusHeader

                    if vm.isRunning && vm.briefItems.isEmpty {
                        loadingState
                    } else if vm.briefItems.isEmpty && !vm.isRunning {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: DS.space12) {
                                ForEach(vm.briefItems) { item in
                                    BriefItemCard(item: item)
                                }
                            }
                            .padding(.horizontal, DS.space16)
                            .padding(.top, DS.space4)
                            .padding(.bottom, DS.space32)
                        }
                    }
                }
            }
            .navigationTitle("Space News")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showWatchlistEditor = true }) {
                            Image(systemName: "list.bullet.rectangle")
                        }
                    }
                }
                .sheet(isPresented: $showWatchlistEditor) {
                    WatchlistEditView()
                }

            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(DS.cream, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBackToHome) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("홈")
                                .font(DS.body)
                        }
                        .foregroundStyle(DS.ink)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.ink)
                            .rotationEffect(.degrees(vm.isRunning ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: vm.isRunning)
                    }
                    .disabled(vm.isRunning)
                }
            }
            .task {
                if vm.briefItems.isEmpty {
                    await vm.refresh()
                }
            }
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        Group {
            if vm.isRunning {
                HStack(spacing: DS.space8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(DS.accentBlue)
                    Text(vm.statusText)
                        .font(DS.caption1)
                        .foregroundStyle(DS.stone)
                }
                .padding(.vertical, DS.space8)
            } else if !vm.briefItems.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DS.accentGreen)
                        .frame(width: 6, height: 6)
                    Text(vm.statusText)
                        .font(DS.caption1)
                        .foregroundStyle(DS.stone)

                    if !vm.metadata.isEmpty {
                        Text("·")
                            .foregroundStyle(DS.mist)
                        Text(metadataSummary)
                            .font(DS.caption1)
                            .foregroundStyle(DS.mist)
                    }
                }
                .padding(.vertical, DS.space8)
            }
        }
    }

    private var metadataSummary: String {
        guard !vm.metadata.isEmpty else { return "" }
        let lines = vm.metadata.split(separator: "\n")
        for line in lines {
            if line.contains("생성 시각:") {
                return String(line.components(separatedBy: ": ").last ?? "")
            }
        }
        return ""
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: DS.space16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DS.accentBlue)

            Text("수집 중...")
                .font(DS.title3)
                .foregroundStyle(DS.ink)

            Text("우주 산업 뉴스를 불러오고 있습니다")
                .font(DS.subheadline)
                .foregroundStyle(DS.stone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(DS.mist)

            Text("우주 뉴스가 없습니다")
                .font(DS.title3)
                .foregroundStyle(DS.ink)

            Text("서버에서 Space News 데이터를 가져옵니다")
                .font(DS.subheadline)
                .foregroundStyle(DS.stone)

            Button {
                Task { await vm.refresh() }
            } label: {
                Text("새로고침")
                    .font(DS.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, DS.space24)
                    .padding(.vertical, DS.space12)
                    .background(DS.ink)
                    .foregroundStyle(DS.cream)
                    .clipShape(Capsule())
            }
            .padding(.top, DS.space8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - BriefItemCard (Apple HIG — Warm Cream)

struct BriefItemCard: View {
    let item: BriefItem
    @State private var isExpanded = false

    var displayHeadlines: [String] {
        isExpanded ? item.headlines : Array(item.headlines.prefix(3))
    }

    private var accentColor: Color {
        if item.isSpaceEconomy { return DS.accentPurple }
        if item.hasIssue { return DS.accentRed }
        return DS.accentBlue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row
            HStack(alignment: .center, spacing: DS.space12) {
                // Icon — 둥근 사각형 (Apple Settings 스타일)
                Image(systemName: item.iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
                            .fill(accentColor)
                    )

                // Title and stats
                VStack(alignment: .leading, spacing: DS.space4) {
                    HStack(spacing: DS.space8) {
                        Text(item.title)
                            .font(DS.headline)
                            .foregroundStyle(DS.ink)

                        if item.hasIssue {
                            DSBadge(text: "중요", color: DS.accentRed)
                        }
                    }

                    HStack(spacing: 10) {
                        Label("\(item.articleCount)", systemImage: "doc.text")
                            .font(DS.caption2)
                            .foregroundStyle(DS.mist)

                        if item.issueCount > 0 {
                            Label("\(item.issueCount) 이슈", systemImage: "exclamationmark.circle.fill")
                                .font(DS.caption2)
                                .foregroundStyle(DS.accentRed)
                        }

                        if !item.headlines.isEmpty {
                            Label("\(item.headlines.count) 뉴스", systemImage: "newspaper.fill")
                                .font(DS.caption2)
                                .foregroundStyle(DS.mist)
                        }
                    }
                }

                Spacer()

                if !item.headlines.isEmpty || !item.reason.isEmpty {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.mist)
                }
            }
            .padding(DS.space16)

            // Summary
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(DS.subheadline)
                    .foregroundStyle(item.hasIssue || item.isSpaceEconomy ? DS.ink : DS.stone)
                    .lineLimit(isExpanded ? nil : 3)
                    .padding(.horizontal, DS.space16)
                    .padding(.bottom, item.headlines.isEmpty && !isExpanded ? DS.space16 : 10)
            }

            // Headlines
            if !displayHeadlines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(displayHeadlines, id: \.self) { headline in
                        HStack(alignment: .top, spacing: DS.space8) {
                            Circle()
                                .fill(accentColor.opacity(0.35))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)

                            Text(headline.replacingOccurrences(of: " KST", with: ""))
                                .font(DS.caption1)
                                .foregroundStyle(DS.stone)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }

                    if !isExpanded && item.headlines.count > 3 {
                        Text("외 \(item.headlines.count - 3)건 더보기")
                            .font(DS.caption1)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.accentBlue)
                            .padding(.top, DS.space4)
                    }
                }
                .padding(.horizontal, DS.space16)
                .padding(.bottom, isExpanded ? 0 : DS.space16)
            }

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    DSHairline(indent: DS.space16)

                    if !item.reason.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.accentOrange)
                                Text("왜 중요한가")
                                    .font(DS.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(DS.stone)
                            }

                            Text(item.reason)
                                .font(DS.subheadline)
                                .foregroundStyle(DS.ink)
                        }
                        .padding(.horizontal, DS.space16)
                    }

                    HStack(spacing: DS.space12) {
                        if !item.timestamp.isEmpty {
                            Label(item.timestamp.replacingOccurrences(of: " KST", with: ""), systemImage: "clock")
                                .font(DS.caption2)
                                .foregroundStyle(DS.mist)
                        }
                        Spacer()
                        if !item.sources.isEmpty {
                            Text(item.sources)
                                .font(DS.caption2)
                                .foregroundStyle(DS.mist)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, DS.space16)
                    .padding(.bottom, DS.space12)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .warmCard(highlighted: item.hasIssue || item.isSpaceEconomy, color: accentColor)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

// MARK: - Watchlist Edit View
struct WatchlistEditView: View {
    @ObservedObject var manager = WatchlistManager.shared
    @State private var newTicker = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Add Ticker") {
                    HStack {
                        TextField("Ticker or company (e.g. RKLB)", text: $newTicker)
                            .textInputAutocapitalization(.characters)
                        Button(action: addTicker) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newTicker.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Current Watchlist") {
                    ForEach(manager.tickers, id: \.self) { ticker in
                        HStack {
                            let profile = WatchProfile.profile(for: ticker)
                            VStack(alignment: .leading) {
                                Text(profile.displayName)
                                    .font(.headline)
                                if profile.secCIK != nil {
                                    Text("SEC filing monitor")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(ticker)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.gray.opacity(0.15)))
                        }
                    }
                    .onDelete(perform: manager.remove)
                    .onMove(perform: manager.move)
                }
                Section {
                    Text("Manage tickers like macOS watchlist.txt. Supported: RKLB, PL, SpaceX and custom tickers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addTicker() {
        manager.add(newTicker)
        newTicker = ""
    }
}
