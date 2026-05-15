import AppKit
import SwiftUI
import Combine

// AI News Brief - ai_agent.py 실행 및 dashboard.md 파싱

private enum AINewsPaths {
    static let root = NSHomeDirectory() + "/ai app/ai-monitor"
    static let dashboardMarkdown = root + "/dashboard.md"
    static let dashboardHTML = root + "/dashboard.html"
    static let collectorScript = root + "/run_ai_agent.sh"
    static let collectorLog = NSHomeDirectory() + "/ai_agent.log"
}

// MARK: - Data Models

struct AINewsItem: Identifiable {
    let id = UUID()
    let provider: String
    let source: String
    let timestamp: String
    let title: String
    let url: String
    let summary: String

    var providerColor: Color {
        let p = provider.lowercased()
        if p.contains("openai") { return AppStyle.openAIGreen }
        if p.contains("anthropic") { return AppStyle.anthropicOrange }
        if p.contains("google") || p.contains("deepmind") { return AppStyle.googleBlue }
        if p.contains("notebooklm") { return AppStyle.notebookLMCyan }
        if p.contains("트렌딩") { return AppStyle.trendingPurple }
        if p.contains("소식") { return AppStyle.importantRed }
        return .secondary
    }

    var sourceIcon: String {
        switch source {
        case "X": return "bubble.left.fill"
        case "RSS": return "dot.radiowaves.up.forward"
        case "웹": return "globe"
        case "뉴스": return "newspaper.fill"
        default: return "doc.text"
        }
    }
}

struct AINewsSection: Identifiable {
    let id = UUID()
    let title: String
    let sectionType: String
    let items: [AINewsItem]

    var icon: String {
        switch sectionType {
        case "trending": return "flame.fill"
        case "official": return providerIcon
        case "digest": return "newspaper.fill"
        default: return "doc.text"
        }
    }

    var color: Color {
        switch sectionType {
        case "trending": return AppStyle.trendingPurple
        case "official": return providerColor
        case "digest": return AppStyle.importantRed
        default: return .secondary
        }
    }

    var isTrending: Bool { sectionType == "trending" }

    /// 회사 로고 이미지 이름 (Assets.xcassets 참조). nil이면 SF Symbol 사용.
    var logoImageName: String? {
        guard sectionType == "official" else { return nil }
        let t = title.lowercased()
        if t.contains("openai") { return "logo_openai" }
        if t.contains("anthropic") { return "logo_anthropic" }
        if t.contains("google ai") { return "logo_google_ai" }
        if t.contains("deepmind") { return "logo_deepmind" }
        if t.contains("notebooklm") { return "logo_notebooklm" }
        if t.contains("xai") || t.contains("grok") { return "logo_xai" }
        return nil
    }

    private var providerIcon: String {
        let t = title.lowercased()
        if t.contains("openai") { return "sparkles" }
        if t.contains("anthropic") { return "brain" }
        if t.contains("google ai") { return "magnifyingglass" }
        if t.contains("deepmind") { return "atom" }
        if t.contains("notebooklm") { return "book.fill" }
        if t.contains("xai") || t.contains("grok") { return "xmark" }
        return "building.2"
    }

    private var providerColor: Color {
        let t = title.lowercased()
        if t.contains("openai") { return AppStyle.openAIGreen }
        if t.contains("anthropic") { return AppStyle.anthropicOrange }
        if t.contains("google") || t.contains("deepmind") { return AppStyle.googleBlue }
        if t.contains("notebooklm") { return AppStyle.notebookLMCyan }
        if t.contains("xai") || t.contains("grok") { return .primary }
        return .secondary
    }
}

// MARK: - ViewModel

@MainActor
final class AINewsViewModel: ObservableObject {
    @Published var sections: [AINewsSection] = []
    @Published var markdownText: String = ""
    @Published var statusText: String = "준비됨"
    @Published var isRunning: Bool = false
    @Published var dashboardUpdatedAt: String = "-"
    @Published var generatedAt: String = ""
    @Published var cutoffAt: String = ""
    @Published var needsFolderAccess: Bool = false

    private var securityScopedURL: URL?

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - 폴더 접근

    func checkFolderAccess() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "aiNewsFolderBookmark") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if url.startAccessingSecurityScopedResource() {
                    securityScopedURL = url
                }
                needsFolderAccess = false
                return
            }
        }

        let fm = FileManager.default
        if fm.isReadableFile(atPath: AINewsPaths.dashboardMarkdown) {
            needsFolderAccess = false
        } else {
            needsFolderAccess = true
            statusText = "폴더 접근 권한 필요"
        }
    }

    func requestFolderAccess() {
        let panel = NSOpenPanel()
        panel.message = "AI News Brief가 작동하려면 스크립트 폴더에 접근해야 합니다"
        panel.prompt = "접근 허용"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: AINewsPaths.root)

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: "aiNewsFolderBookmark")
                if url.startAccessingSecurityScopedResource() {
                    securityScopedURL = url
                }
                needsFolderAccess = false
                statusText = "폴더 접근 권한 부여됨 ✅"
                refresh()
            } catch {
                statusText = "북마크 저장 실패: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 데이터 로드

    func refresh() {
        markdownText = (try? String(contentsOfFile: AINewsPaths.dashboardMarkdown, encoding: .utf8)) ?? "대시보드 파일이 없습니다."
        dashboardUpdatedAt = formatDate(path: AINewsPaths.dashboardMarkdown)
        parseMarkdown()
    }

    // MARK: - 마크다운 파싱

    private func parseMarkdown() {
        guard !markdownText.isEmpty && markdownText != "대시보드 파일이 없습니다." else {
            sections = []
            return
        }

        let lines = markdownText.components(separatedBy: "\n")

        // 메타데이터 추출
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- 생성:") {
                generatedAt = t.replacingOccurrences(of: "- 생성:", with: "").trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("- 기준(컷오프):") {
                cutoffAt = t.replacingOccurrences(of: "- 기준(컷오프):", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // 섹션별 분리
        var segments: [(section: String, provider: String, lines: [String])] = []
        var curSection = ""
        var curProvider = ""
        var curLines: [String] = []

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("## ") && !t.hasPrefix("### ") {
                if !curSection.isEmpty {
                    segments.append((curSection, curProvider, curLines))
                }
                curSection = String(t.dropFirst(3))
                curProvider = ""
                curLines = []
            } else if t.hasPrefix("### ") {
                if !curProvider.isEmpty || !curLines.isEmpty {
                    segments.append((curSection, curProvider, curLines))
                    curLines = []
                }
                curProvider = String(t.dropFirst(4))
            } else {
                curLines.append(line)
            }
        }
        if !curSection.isEmpty {
            segments.append((curSection, curProvider, curLines))
        }

        // 각 세그먼트를 섹션으로 변환
        var parsedSections: [AINewsSection] = []

        for (section, provider, sLines) in segments {
            guard section != "소스 상태" else { continue }

            let items = parseItems(from: sLines)

            let sectionType: String
            let displayTitle: String

            switch section {
            case "X 트렌딩 AI":
                sectionType = "trending"
                displayTitle = "X 트렌딩 AI"
            case "공식 채널":
                guard !provider.isEmpty else { continue }
                sectionType = "official"
                displayTitle = provider
            case "AI 소식 정리":
                sectionType = "digest"
                displayTitle = "AI 소식 정리"
                guard !items.isEmpty else { continue }
            default:
                continue
            }

            parsedSections.append(AINewsSection(
                title: displayTitle,
                sectionType: sectionType,
                items: items
            ))
        }

        sections = parsedSections

        let totalItems = parsedSections.reduce(0) { $0 + $1.items.count }
        let trendingCount = parsedSections.first { $0.sectionType == "trending" }?.items.count ?? 0
        if totalItems > 0 {
            statusText = "총 \(totalItems)건 (트렌딩 \(trendingCount)건)"
        }

        print("🎉 AI 뉴스 \(parsedSections.count)개 섹션, 총 \(totalItems)건 파싱 완료")
    }

    private func parseItems(from lines: [String]) -> [AINewsItem] {
        var items: [AINewsItem] = []
        let pattern = #"^- \[([^\]]+)\]\[([^\]]+)\] (\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s*(?:KST)?\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            if let match = regex.firstMatch(in: trimmed, range: range),
               let providerRange = Range(match.range(at: 1), in: trimmed),
               let sourceRange = Range(match.range(at: 2), in: trimmed),
               let tsRange = Range(match.range(at: 3), in: trimmed),
               let titleRange = Range(match.range(at: 4), in: trimmed) {

                let provider = String(trimmed[providerRange])
                let source = String(trimmed[sourceRange])
                let timestamp = String(trimmed[tsRange])
                let title = String(trimmed[titleRange])

                var url = ""
                var summaryParts: [String] = []

                i += 1

                while i < lines.count {
                    let subLine = lines[i]
                    let subTrimmed = subLine.trimmingCharacters(in: .whitespaces)

                    if subLine.hasPrefix("  ") && subTrimmed.hasPrefix("- ") {
                        let content = String(subTrimmed.dropFirst(2))
                        if content.hasPrefix("http://") || content.hasPrefix("https://") {
                            if url.isEmpty { url = content }
                        } else if !content.isEmpty {
                            summaryParts.append(content)
                        }
                        i += 1
                    }
                    else if subTrimmed.isEmpty {
                        // 빈 줄 건너뛰되, 다음 줄이 새 아이템 시작이면 break
                        var peek = i + 1
                        while peek < lines.count && lines[peek].trimmingCharacters(in: .whitespaces).isEmpty {
                            peek += 1
                        }
                        if peek >= lines.count {
                            break
                        }
                        let peekTrimmed = lines[peek].trimmingCharacters(in: .whitespaces)
                        // 새 아이템(- [...][...])이나 섹션 헤더(## / ###)면 break
                        if peekTrimmed.hasPrefix("- [") || peekTrimmed.hasPrefix("## ") || peekTrimmed.hasPrefix("### ") {
                            break
                        }
                        // 아직 같은 아이템의 continuation → 계속 진행
                        i += 1
                    }
                    else {
                        // 들여쓰기 없는 일반 텍스트 = continuation line → summary에 추가
                        if subTrimmed.hasPrefix("- [") || subTrimmed.hasPrefix("## ") {
                            break
                        }
                        if !subTrimmed.isEmpty {
                            summaryParts.append(subTrimmed)
                        }
                        i += 1
                    }
                }

                items.append(AINewsItem(
                    provider: provider,
                    source: source,
                    timestamp: timestamp,
                    title: Self.stripThinkTags(title),
                    url: url,
                    summary: Self.stripThinkTags(summaryParts.joined(separator: " "))
                ))
            } else {
                i += 1
            }
        }

        return items
    }

    /// Python 수집기가 <think> 태그를 포함한 채로 저장할 때 방어
    static func stripThinkTags(_ text: String) -> String {
        var s = text
        // </think> 이후만 사용
        while let r = s.range(of: "</think>") {
            s = String(s[r.upperBound...])
        }
        // 잔여 태그 제거
        s = s.replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .replacingOccurrences(of: "/no_think", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // thinking 텍스트만 남은 경우 빈 문자열 반환
        let low = s.lowercased()
        if low.hasPrefix("okay,") || low.hasPrefix("ok,") { return "" }
        if low.contains("the user wants") && low.contains("translat") { return "" }
        if low.contains("let me start") && low.contains("translat") { return "" }
        return s
    }

    // MARK: - 액션

    func openDashboard() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AINewsPaths.dashboardHTML))
    }

    func runCollector() {
        guard !isRunning else { return }
        isRunning = true
        statusText = "AI 뉴스 수집 중..."

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "cd '\(AINewsPaths.root)' && bash '\(AINewsPaths.collectorScript)' 2>&1"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        env["HOME"] = NSHomeDirectory()
        task.environment = env

        do {
            try task.run()

            // DispatchQueue 사용 — Swift concurrency cooperative thread 차단 방지
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    self?.isRunning = false
                    if task.terminationStatus == 0 {
                        self?.statusText = "AI 뉴스 수집 완료 ✅"
                        print("✅ AI 뉴스 수집 성공")
                    } else {
                        self?.statusText = "수집 실패 (코드: \(task.terminationStatus)) ❌"
                        print("❌ AI 뉴스 수집 실패:", output.prefix(500))
                    }
                    self?.refresh()
                }
            }
        } catch {
            isRunning = false
            statusText = "수집 실행 오류: \(error.localizedDescription)"
        }
    }

    private func formatDate(path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return "-"
        }
        return df.string(from: date)
    }
}

// MARK: - AI News Content View (Apple 스타일)

struct AINewsContentView: View {
    @ObservedObject var vm: AINewsViewModel
    let onBackToHome: () -> Void
    @State private var showRawText = false
    @State private var hasCheckedAccess = false

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 - Claude 스타일 배경
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    // 뒤로가기 버튼 - bordered, small controlSize
                    Button(action: onBackToHome) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("첫 화면으로")

                    // 타이틀 & 상태
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI News Brief")
                            .font(.title3)
                            .fontWeight(.semibold)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusIndicatorColor(vm.statusText))
                                .frame(width: 6, height: 6)
                            Text(vm.statusText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // AI 뉴스 수집 버튼
                    ActionButton(
                        vm.isRunning ? "수집 중..." : "AI 뉴스 수집",
                        icon: vm.isRunning ? nil : "brain",
                        color: AppStyle.aiTeal,
                        isLoading: vm.isRunning,
                        action: { vm.runCollector() }
                    )
                }
                .padding(.horizontal, AppStyle.contentInset)
                .padding(.vertical, 12)

                // 메타데이터 바 — 조건부 뷰 없음, 동일 구조 유지
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(aiMetadataSummary)
                            .font(.caption2)
                            .foregroundStyle(vm.generatedAt.isEmpty ? .tertiary : .secondary)
                    }

                    Spacer()

                    Toggle(isOn: $showRawText) {
                        Label("원본", systemImage: "doc.plaintext")
                            .font(.caption2)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(.horizontal, AppStyle.contentInset)
                .padding(.vertical, 8)
                .background(AppStyle.surfaceBg)

                Divider()
            }
            .background(AppStyle.cardBg)

            // 접근 권한 경고 배너
            if vm.needsFolderAccess {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                        .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("폴더 접근 권한 필요")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("앱이 정상적으로 작동하려면 스크립트 폴더에 대한 접근 권한이 필요합니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("허용") {
                        vm.requestFolderAccess()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(12)
                .background(AppStyle.cardBg)
                .overlay(
                    Rectangle()
                        .fill(Color.orange.opacity(0.4))
                        .frame(height: 2),
                    alignment: .top
                )
            }

            // 메인 콘텐츠
            Group {
                if showRawText {
                    ScrollView {
                        Text(vm.markdownText.isEmpty ? "내용 없음" : vm.markdownText)
                            .textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppStyle.contentInset)
                    }
                    .background(AppStyle.pageBg)
                } else {
                    ScrollView {
                        if vm.sections.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "tray")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundStyle(.tertiary)

                                Text("AI 뉴스를 불러오는 중...")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)

                                Text("'AI 뉴스 수집' 버튼을 눌러 최신 데이터를 가져오세요")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(60)
                        } else {
                            LazyVStack(spacing: AppStyle.sectionSpacing) {
                                ForEach(vm.sections) { section in
                                    AINewsSectionCard(section: section)
                                }
                            }
                            .padding(AppStyle.contentInset)
                        }
                    }
                    .background(AppStyle.pageBg)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 400, idealHeight: 520)
        .onAppear {
            if !hasCheckedAccess {
                hasCheckedAccess = true
                vm.checkFolderAccess()

                if vm.needsFolderAccess {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        vm.requestFolderAccess()
                    }
                } else {
                    vm.refresh()
                }
            }
        }
    }

    private var aiMetadataSummary: String {
        guard !vm.generatedAt.isEmpty else { return "대기 중" }
        var parts = [vm.generatedAt]
        if !vm.cutoffAt.isEmpty { parts.append("기준: \(vm.cutoffAt)") }
        return parts.joined(separator: " · ")
    }

    private func statusIndicatorColor(_ status: String) -> Color {
        if status.contains("완료") { return AppStyle.successGreen }
        if status.contains("실패") || status.contains("오류") { return AppStyle.importantRed }
        if status.contains("수집 중") { return AppStyle.aiTeal }
        return .gray
    }
}

// MARK: - Section Card (Apple grouped list pattern)

struct AINewsSectionCard: View {
    let section: AINewsSection
    @State private var isExpanded = false
    @State private var isHovered = false

    var displayItems: [AINewsItem] {
        isExpanded ? section.items : Array(section.items.prefix(3))
    }

    var hiddenCount: Int {
        max(0, section.items.count - 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(alignment: .center, spacing: 12) {
                // Icon with background
                if let logoName = section.logoImageName {
                    Image(logoName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white))
                        .clipShape(Circle())
                } else {
                    IconCircle(icon: section.icon, color: section.color, size: 38)
                }

                // Title & metadata
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if section.isTrending {
                            BadgeLabel("인기", icon: "flame.fill", color: AppStyle.trendingPurple)
                        }
                    }

                    HStack(spacing: 10) {
                        Label("\(section.items.count)건", systemImage: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        let sourceCounts = Dictionary(grouping: section.items, by: { $0.source })
                        ForEach(sourceCounts.keys.sorted(), id: \.self) { source in
                            HStack(spacing: 3) {
                                Image(systemName: sourceIconFor(source))
                                    .font(.system(size: 8))
                                Text("\(source) \(sourceCounts[source]?.count ?? 0)")
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()
            }
            .padding(AppStyle.cardPadding)

            // Item list with dividers
            VStack(alignment: .leading, spacing: 0) {
                if section.items.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                        Text("최근 24시간 내 수집된 항목이 없습니다")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        AINewsItemRow(item: item, isExpanded: isExpanded, sectionColor: section.color)

                        if index < displayItems.count - 1 || (!isExpanded && hiddenCount > 0) {
                            ListRowDivider(leadingPadding: AppStyle.cardPadding + 4)
                        }
                    }
                }

                // "More" / "Collapse" button
                if !isExpanded && hiddenCount > 0 {
                    ListRowDivider(leadingPadding: AppStyle.cardPadding + 4)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                            Text("외 \(hiddenCount)건 더보기")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                } else if isExpanded && hiddenCount > 0 {
                    ListRowDivider(leadingPadding: AppStyle.cardPadding + 4)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9))
                            Text("접기")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppStyle.cardPadding)
            .padding(.bottom, AppStyle.cardPadding)
        }
        .appleCard(
            isHovered: isHovered,
            hasBorder: section.isTrending,
            borderColor: AppStyle.trendingPurple
        )
        .scaleEffect(isHovered ? 1.003 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func sourceIconFor(_ source: String) -> String {
        switch source {
        case "X": return "bubble.left.fill"
        case "RSS": return "dot.radiowaves.up.forward"
        case "웹": return "globe"
        case "뉴스": return "newspaper.fill"
        default: return "doc.text"
        }
    }
}

// MARK: - News Item Row (Apple list pattern)

struct AINewsItemRow: View {
    let item: AINewsItem
    let isExpanded: Bool
    let sectionColor: Color

    // 번역은 Python 수집기가 처리 — 인앱 이중 번역 제거 (GPU 경합 방지)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(item.providerColor.opacity(0.35))
                    .frame(width: 4, height: 4)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 4) {
                    // Source badge + timestamp
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: item.sourceIcon)
                                .font(.system(size: 8))
                            Text(item.source)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(item.providerColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppStyle.surfaceBg)
                        .clipShape(Capsule())

                        Text(item.timestamp.replacingOccurrences(of: " KST", with: ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !item.provider.contains("소식") && !item.provider.contains("트렌딩") {
                            Text("· \(item.provider)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        // (번역 스피너 제거 — Python 수집기에서 번역 완료)
                    }

                    // Title
                    Text(item.title)
                        .font(isExpanded ? .body : .subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 2)

                    // Expanded summary
                    if isExpanded && !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    // Source link
                    if isExpanded && !item.url.isEmpty {
                        Button(action: {
                            if let url = URL(string: item.url) {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text("원문 보기")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        // 인앱 번역 제거 — Python 수집기가 마크다운에 번역 완료 후 저장
    }

}

#Preview {
    AINewsContentView(vm: AINewsViewModel(), onBackToHome: {})
}
