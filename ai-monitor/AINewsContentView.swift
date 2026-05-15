import AppKit
import SwiftUI
import Combine

// AI News Brief - ai_agent.py 실행 및 dashboard.md 파싱

private enum AINewsPaths {
    static let root = "/Users/minyeop/ai app/ai-news-brief"
    static let dashboardMarkdown = root + "/dashboard.md"
    static let dashboardHTML = root + "/dashboard.html"
    static let collectorScript = root + "/run_ai_agent.sh"
    static let collectorLog = NSHomeDirectory() + "/ai_agent.log"
}

struct AINewsItem: Identifiable {
    let id = UUID()
    let provider: String          // OpenAI, Anthropic, Google AI
    let title: String
    let summary: String
    let source: String            // X, RSS, WEB
    let timestamp: String
    let url: String
    let score: Int                // 중요도 점수
    
    var isHighPriority: Bool { score >= 4 }
    var providerColor: Color {
        switch provider.lowercased() {
        case let p where p.contains("openai"):
            return .green
        case let p where p.contains("anthropic"):
            return .orange
        case let p where p.contains("google"):
            return .blue
        default:
            return .purple
        }
    }
}

@MainActor
final class AINewsViewModel: ObservableObject {
    @Published var newsItems: [AINewsItem] = []
    @Published var markdownText: String = ""
    @Published var statusText: String = "준비됨"
    @Published var isRunning: Bool = false
    @Published var dashboardUpdatedAt: String = "-"
    @Published var metadata: String = ""
    @Published var needsFolderAccess: Bool = false
    
    private var securityScopedURL: URL?
    
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd HH:MM:ss"
        return f
    }()
    
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
    
    func refresh() {
        markdownText = (try? String(contentsOfFile: AINewsPaths.dashboardMarkdown, encoding: .utf8)) ?? "대시보드 파일이 없습니다."
        dashboardUpdatedAt = formatDate(path: AINewsPaths.dashboardMarkdown)
        
        parseMarkdown()
    }
    
    private func parseMarkdown() {
        print("📋 마크다운 텍스트 길이: \(markdownText.count)")
        
        guard !markdownText.isEmpty && markdownText != "대시보드 파일이 없습니다." else {
            print("⚠️ 대시보드가 비어있거나 파일이 없습니다")
            newsItems = []
            return
        }
        
        let lines = markdownText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var items: [AINewsItem] = []
        
        // 메타데이터 추출 (상단)
        var metaLines: [String] = []
        var i = 0
        while i < lines.count && i < 20 {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "##") { break }
            if !trimmed.isEmpty && (trimmed.contains("생성 시각") || trimmed.contains("윈도우") || trimmed.contains("소스")) {
                metaLines.append(lines[i])
            }
            i += 1
        }
        metadata = metaLines.joined(separator: "\n")
        
        // 뉴스 항목 파싱
        var currentProvider = ""
        var currentTitle = ""
        var currentSummary = ""
        var currentSource = ""
        var currentTimestamp = ""
        var currentURL = ""
        var currentScore = 0
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Provider 헤더: ## OpenAI, ## Anthropic, ## Google AI
            if trimmed.starts(with: "## ") && !trimmed.contains("트렌딩") && !trimmed.contains("다이제스트") {
                // 이전 항목 저장
                if !currentTitle.isEmpty {
                    let item = AINewsItem(
                        provider: currentProvider,
                        title: currentTitle,
                        summary: currentSummary,
                        source: currentSource,
                        timestamp: currentTimestamp,
                        url: currentURL,
                        score: currentScore
                    )
                    items.append(item)
                }
                
                currentProvider = String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))
                currentTitle = ""
                currentSummary = ""
                currentSource = ""
                currentTimestamp = ""
                currentURL = ""
                currentScore = 0
            }
            // 뉴스 항목: ### 제목
            else if trimmed.starts(with: "### ") {
                // 이전 항목 저장
                if !currentTitle.isEmpty {
                    let item = AINewsItem(
                        provider: currentProvider,
                        title: currentTitle,
                        summary: currentSummary,
                        source: currentSource,
                        timestamp: currentTimestamp,
                        url: currentURL,
                        score: currentScore
                    )
                    items.append(item)
                }
                
                currentTitle = String(trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces))
                currentSummary = ""
                currentSource = ""
                currentTimestamp = ""
                currentURL = ""
                currentScore = 0
            }
            // 메타데이터
            else if trimmed.starts(with: "**출처**:") || trimmed.starts(with: "출처:") {
                currentSource = trimmed
                    .replacingOccurrences(of: "**출처**:", with: "")
                    .replacingOccurrences(of: "출처:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            else if trimmed.starts(with: "**시각**:") || trimmed.starts(with: "시각:") {
                currentTimestamp = trimmed
                    .replacingOccurrences(of: "**시각**:", with: "")
                    .replacingOccurrences(of: "시각:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            else if trimmed.starts(with: "**링크**:") || trimmed.starts(with: "링크:") {
                let linkPart = trimmed
                    .replacingOccurrences(of: "**링크**:", with: "")
                    .replacingOccurrences(of: "링크:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                // 마크다운 링크 파싱: [text](url)
                if let match = linkPart.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
                    currentURL = String(linkPart[match].dropFirst().dropLast())
                } else {
                    currentURL = linkPart
                }
            }
            else if trimmed.starts(with: "**점수**:") || trimmed.starts(with: "점수:") {
                let scoreStr = trimmed
                    .replacingOccurrences(of: "**점수**:", with: "")
                    .replacingOccurrences(of: "점수:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentScore = Int(scoreStr) ?? 0
            }
            // 요약 (일반 텍스트)
            else if !trimmed.isEmpty && !trimmed.starts(with: "#") && !trimmed.starts(with: "**") {
                if currentSummary.isEmpty {
                    currentSummary = trimmed
                } else {
                    currentSummary += " " + trimmed
                }
            }
        }
        
        // 마지막 항목 저장
        if !currentTitle.isEmpty {
            let item = AINewsItem(
                provider: currentProvider,
                title: currentTitle,
                summary: currentSummary,
                source: currentSource,
                timestamp: currentTimestamp,
                url: currentURL,
                score: currentScore
            )
            items.append(item)
        }
        
        newsItems = items.sorted { $0.score > $1.score }
        print("🎉 총 \(items.count)개 AI 뉴스 항목 파싱 완료")
        
        if !items.isEmpty {
            let highPriority = items.filter { $0.isHighPriority }.count
            statusText = "총 \(items.count)건 중 \(highPriority)건 중요"
        }
    }
    
    func openDashboard() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AINewsPaths.dashboardHTML))
    }
    
    func requestFolderAccess() {
        let panel = NSOpenPanel()
        panel.message = "AI News Brief가 작동하려면 스크립트 폴더에 접근해야 합니다"
        panel.prompt = "접근 허용"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: AINewsPaths.root)
        
        if panel.runModal() == .OK {
            if let url = panel.url {
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
    }
    
    func runCollector() {
        guard !isRunning else { return }
        isRunning = true
        statusText = "AI 뉴스 수집 중... 🤖"
        
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
        
        Task {
            do {
                try task.run()
                
                Task.detached {
                    task.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    await MainActor.run {
                        self.isRunning = false
                        
                        if task.terminationStatus == 0 {
                            self.statusText = "AI 뉴스 수집 완료 ✅"
                            print("✅ AI 뉴스 수집 성공")
                            print("출력:", output.prefix(500))
                        } else {
                            self.statusText = "수집 실패 (코드: \(task.terminationStatus)) ❌"
                            print("❌ AI 뉴스 수집 실패")
                            print("출력:", output)
                        }
                        
                        self.refresh()
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.statusText = "수집 실행 오류: \(error.localizedDescription)"
                    print("❌ 실행 오류:", error)
                }
            }
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

// MARK: - AI News Content View

struct AINewsContentView: View {
    @StateObject private var vm = AINewsViewModel()
    @State private var showRawText = false
    @State private var hasCheckedAccess = false
    @State private var showModeSelector = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    // 로고
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.pink.opacity(0.8), Color.orange.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI News Brief")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusIndicatorColor(vm.statusText))
                                .frame(width: 6, height: 6)
                            Text(vm.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 액션 버튼
                    HStack(spacing: 12) {
                        // 모드 전환
                        Button(action: { showModeSelector = true }) {
                            Image(systemName: "arrow.left.arrow.right.circle")
                                .font(.callout)
                                .padding(10)
                        }
                        .buttonStyle(ModernButtonStyle(color: .gray))
                        .help("모드 전환")
                        
                        // 새로고침
                        Button(action: { vm.refresh() }) {
                            Label("새로고침", systemImage: "arrow.clockwise")
                                .font(.callout)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(ModernButtonStyle(color: .gray))
                        
                        // 정보 수집
                        Button(action: { vm.runCollector() }) {
                            HStack(spacing: 6) {
                                if vm.isRunning {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "brain")
                                }
                                Text(vm.isRunning ? "수집 중..." : "AI 뉴스 수집")
                            }
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(ModernButtonStyle(color: .pink, isProminent: true))
                        .disabled(vm.isRunning)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                // 메타데이터
                if !vm.metadata.isEmpty {
                    HStack(spacing: 20) {
                        ForEach(parseMetadata(vm.metadata), id: \.key) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.value)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle(isOn: $showRawText) {
                            Label("원본", systemImage: "doc.plaintext")
                                .font(.caption)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                }
                
                Divider()
            }
            
            // 접근 권한 경고
            if vm.needsFolderAccess {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("폴더 접근 권한 필요")
                            .font(.callout.weight(.semibold))
                        Text("앱이 정상적으로 작동하려면 스크립트 폴더에 대한 접근 권한이 필요합니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("허용") {
                        vm.requestFolderAccess()
                    }
                    .buttonStyle(ModernButtonStyle(color: .orange, isProminent: true))
                }
                .padding(16)
                .background(Color.orange.opacity(0.08))
                .overlay(
                    Rectangle()
                        .fill(Color.orange.opacity(0.3))
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                } else {
                    ScrollView {
                        if vm.newsItems.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "tray")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                                
                                Text("AI 뉴스를 불러오는 중...")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                
                                Text("'AI 뉴스 수집' 버튼을 눌러 최신 데이터를 가져오세요")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(60)
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(vm.newsItems) { item in
                                    AINewsItemCard(item: item)
                                }
                            }
                            .padding(24)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 400, idealHeight: 520)
        .sheet(isPresented: $showModeSelector) {
            ModeSelectionView()
        }
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
    
    private func statusIndicatorColor(_ status: String) -> Color {
        if status.contains("완료") {
            return .green
        } else if status.contains("실패") || status.contains("오류") {
            return .red
        } else if status.contains("수집 중") {
            return .blue
        } else {
            return .gray
        }
    }
    
    private func parseMetadata(_ metadata: String) -> [(key: String, value: String, icon: String)] {
        var result: [(String, String, String)] = []
        let lines = metadata.split(separator: "\n")
        
        for line in lines {
            let text = String(line)
            if text.contains("생성 시각") {
                let value = text.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                result.append(("time", value, "clock"))
            } else if text.contains("윈도우") {
                let value = text.components(separatedBy: ":").last ?? ""
                result.append(("window", value, "calendar"))
            }
        }
        
        return result
    }
}

// MARK: - AI News Item Card

struct AINewsItemCard: View {
    let item: AINewsItem
    @State private var isExpanded = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(alignment: .center, spacing: 12) {
                // 프로바이더 아이콘
                ZStack {
                    Circle()
                        .fill(item.providerColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: iconForProvider(item.provider))
                        .font(.title3)
                        .foregroundStyle(item.providerColor)
                }
                
                // 타이틀
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(isExpanded ? nil : 2)
                        
                        if item.isHighPriority {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text("중요")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.2))
                            .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Label(item.provider, systemImage: "building.2")
                            .font(.caption2)
                            .foregroundStyle(item.providerColor)
                        
                        Label(item.source, systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        if !item.timestamp.isEmpty {
                            Label(item.timestamp, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // 확장 버튼
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 32, height: 32)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            // 요약
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.callout)
                    .foregroundStyle(item.isHighPriority ? .primary : .secondary)
                    .lineLimit(isExpanded ? nil : 3)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            
            // 상세 정보 (확장 시)
            if isExpanded && !item.url.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 20)
                    
                    Button(action: {
                        if let url = URL(string: item.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("원문 보기")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 20 : 10, x: 0, y: isHovered ? 8 : 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    item.isHighPriority ?
                        LinearGradient(colors: [item.providerColor.opacity(0.5), item.providerColor.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [.clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: item.isHighPriority ? 2 : 0
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func iconForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case let p where p.contains("openai"):
            return "sparkles"
        case let p where p.contains("anthropic"):
            return "brain"
        case let p where p.contains("google"):
            return "magnifyingglass"
        default:
            return "star"
        }
    }
}

#Preview {
    AINewsContentView()
}
