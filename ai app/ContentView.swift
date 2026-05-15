import AppKit
import SwiftUI
import Combine
// Ollama (qwen3:8b) 번역 지원

private enum BriefPaths {
    static let root = NSHomeDirectory() + "/ai app/stock-space-brief"
    static let reportHTML = root + "/stock_feed.html"
    static let inboxMarkdown = root + "/stock_feed_inbox.md"
    static let collectorScript = root + "/run_space_stock_collector.sh"
    // 로그는 홈 디렉토리로 (쓰기 권한 확실)
    static let collectorLog = NSHomeDirectory() + "/space_stock_collector.log"
}

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

    var hasIssue: Bool { issueCount > 0 || (!summary.contains("큰 이슈 없음") && !summary.isEmpty) }
    var isSpaceEconomy: Bool {
        title.contains("우주경제") || title.contains("Space Economy")
    }

    /// 회사 이름인 경우 로고 이미지 에셋 이름 반환
    var logoImageName: String? {
        let t = title.lowercased()
        if t.contains("spacex") || t.contains("space x") { return "logo_spacex" }
        if t.contains("rocket lab") || t.contains("rocketlab") { return "logo_rocketlab" }
        if t.contains("planet lab") || t.contains("planetlab") { return "logo_planetlabs" }
        if t.contains("openai") { return "logo_openai" }
        if t.contains("anthropic") { return "logo_anthropic" }
        if t.contains("google") { return "logo_google_ai" }
        if t.contains("deepmind") { return "logo_deepmind" }
        if t.contains("notebooklm") { return "logo_notebooklm" }
        return nil
    }
}

@MainActor
final class BriefViewModel: ObservableObject {
    @Published var briefItems: [BriefItem] = []
    @Published var inboxText: String = ""
    @Published var statusText: String = "준비됨"
    @Published var isRunning: Bool = false
    @Published var reportUpdatedAt: String = "-"
    @Published var inboxUpdatedAt: String = "-"
    @Published var metadata: String = ""
    @Published var needsFolderAccess: Bool = false

    /// 보안 범위 북마크 URL (샌드박스 환경에서 파일 접근용)
    private var securityScopedURL: URL?

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func checkFolderAccess() {
        // 북마크가 있는지 확인
        if let bookmarkData = UserDefaults.standard.data(forKey: "folderBookmark") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                // 보안 범위 접근 시작 (샌드박스 환경에서 필수)
                if url.startAccessingSecurityScopedResource() {
                    securityScopedURL = url
                }
                needsFolderAccess = false
                return
            }
        }

        // 직접 파일 읽기 시도
        let fm = FileManager.default
        if fm.isReadableFile(atPath: BriefPaths.inboxMarkdown) {
            needsFolderAccess = false
        } else {
            needsFolderAccess = true
            statusText = "폴더 접근 권한 필요 - '폴더 접근 허용' 버튼 클릭"
        }
    }

    func refresh() {
        inboxText = (try? String(contentsOfFile: BriefPaths.inboxMarkdown, encoding: .utf8)) ?? "인박스 파일이 없습니다."
        reportUpdatedAt = formatDate(path: BriefPaths.reportHTML)
        inboxUpdatedAt = formatDate(path: BriefPaths.inboxMarkdown)

        // 인박스 파싱
        parseInbox()
    }

    private func parseInbox() {
        // 디버깅: 원본 텍스트 길이 확인
        print("📋 인박스 텍스트 길이: \(inboxText.count)")

        guard !inboxText.isEmpty && inboxText != "인박스 파일이 없습니다." else {
            print("⚠️ 인박스가 비어있거나 파일이 없습니다")
            briefItems = []
            return
        }

        let lines = inboxText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var items: [BriefItem] = []
        var totalArticles = 0
        var totalIssues = 0

        print("📝 총 라인 수: \(lines.count)")

        // 메타데이터 추출 (상단 정보)
        // 필드 접두사 (섹션 헤더가 아닌 줄)
        let fieldPrefixes = ["무슨 일", "왜 중요한지", "날짜", "출처", "HTML 대시보드",
                             "[리포트", "리포트 파일", "리포트 URL", "에이전트 버전",
                             "생성 시각", "신규 윈도우", "검색 윈도우", "워치리스트"]

        var metaLines: [String] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if lines[i].starts(with: "## ") { break }

            if trimmed.isEmpty {
                // 빈 줄은 건너뜀
            } else if fieldPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                metaLines.append(lines[i])
            } else if !metaLines.isEmpty {
                // 메타/필드가 아닌 텍스트 = 섹션 시작
                break
            }
            i += 1
            // 처음 20줄까지만 메타데이터로 간주
            if i > 20 { break }
        }
        metadata = metaLines.joined(separator: "\n")
        print("📊 메타데이터: \(metadata.prefix(100))...")

        // 각 섹션 파싱 (## 로 시작하는 항목)
        var currentTitle = ""
        var currentSummary = ""
        var currentReason = ""
        var currentArticleCount = 0
        var currentIssueCount = 0
        var currentHeadlines: [String] = []
        var currentTimestamp = ""
        var currentSources = ""

        var sectionCount = 0

        for (index, line) in lines.enumerated() {
            // 섹션 헤더 감지: "## " 접두사 또는 빈 줄 뒤에 오는 비-필드 텍스트
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let isSectionHeader = line.starts(with: "## ") || (
                !trimmedLine.isEmpty
                && index > 0
                && lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
                && !fieldPrefixes.contains(where: { trimmedLine.hasPrefix($0) })
            )
            if isSectionHeader {
                sectionCount += 1
                print("🔍 섹션 \(sectionCount) 발견: \(line)")

                // 이전 항목 저장
                if !currentTitle.isEmpty {
                    let item = BriefItem(
                        title: currentTitle,
                        summary: currentSummary,
                        reason: currentReason,
                        articleCount: currentArticleCount,
                        issueCount: currentIssueCount,
                        headlines: currentHeadlines,
                        timestamp: currentTimestamp,
                        sources: currentSources
                    )
                    items.append(item)
                    print("✅ 항목 저장: \(currentTitle) - \(currentArticleCount)건")
                }

                // 새 항목 시작
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

                // 통계 추출
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
                                totalArticles += count
                                print("  📰 기사 수: \(count)")
                            }
                        }
                    }
                }

                if line.contains("이슈 기준 충족") {
                    let components = line.components(separatedBy: " ")
                    for (idx, comp) in components.enumerated() {
                        if comp.contains("충족") && idx < components.count - 1 {
                            let numStr = components[idx + 1].replacingOccurrences(of: "건)", with: "").replacingOccurrences(of: "건,", with: "").replacingOccurrences(of: "건", with: "")
                            if let count = Int(numStr) {
                                currentIssueCount = count
                                totalIssues += count
                                print("  🚨 이슈 수: \(count)")
                            }
                        }
                    }
                }

            } else if line.contains("왜 중요한지") && line.contains(":") {
                currentReason = line.replacingOccurrences(of: "**왜 중요한지**:", with: "")
                    .replacingOccurrences(of: "왜 중요한지:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // 참고 헤드라인 추출
                if line.contains("참고 헤드라인:") || line.contains("헤드라인:") {
                    let headlinePart = line.components(separatedBy: "헤드라인:").last ?? ""
                    let headlines = headlinePart.components(separatedBy: " / ")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    currentHeadlines = headlines
                    print("  📌 헤드라인 수: \(headlines.count)")
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

        // 마지막 항목 저장
        if !currentTitle.isEmpty {
            let item = BriefItem(
                title: currentTitle,
                summary: currentSummary,
                reason: currentReason,
                articleCount: currentArticleCount,
                issueCount: currentIssueCount,
                headlines: currentHeadlines,
                timestamp: currentTimestamp,
                sources: currentSources
            )
            items.append(item)
            print("✅ 마지막 항목 저장: \(currentTitle)")
        }

        briefItems = items
        print("🎉 총 \(items.count)개 항목 파싱 완료")

        if totalArticles > 0 {
            statusText = "마지막 수집: 총 \(totalArticles)건 기사 중 \(totalIssues)건 이슈 발견"
        } else if !items.isEmpty {
            statusText = "\(items.count)개 항목 로드 완료"
        }
    }

    func openReport() {
        NSWorkspace.shared.open(URL(fileURLWithPath: BriefPaths.reportHTML))
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: BriefPaths.collectorLog))
    }

    func testScriptExists() {
        let fm = FileManager.default
        let scriptPath = BriefPaths.collectorScript

        do {
            let _ = try fm.contentsOfDirectory(atPath: BriefPaths.root)

            if fm.fileExists(atPath: scriptPath) {
                let isExecutable = fm.isExecutableFile(atPath: scriptPath)
                let isReadable = fm.isReadableFile(atPath: scriptPath)

                if isReadable {
                    statusText = "스크립트 존재: \(isExecutable ? "실행 가능 ✅" : "읽기 가능 (bash로 실행 가능) ✅")"
                } else {
                    statusText = "스크립트 존재하지만 읽기 불가 ❌"
                }
            } else {
                statusText = "스크립트 없음: \(scriptPath)"
            }
        } catch {
            statusText = "폴더 접근 불가: \(error.localizedDescription). 시스템 설정에서 권한 부여 필요"
        }
    }

    func fixScriptPermissions() {
        let script = """
        tell application "Terminal"
            activate
            do script "chmod +x '\(BriefPaths.collectorScript)' && echo '✅ 실행 권한 부여 완료!' && sleep 2"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if let error = error {
                statusText = "터미널 실행 실패: \(error)"
            } else {
                statusText = "터미널에서 권한 부여 중... 터미널 창 확인"

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    self?.testScriptExists()
                }
            }
        } else {
            statusText = "AppleScript 생성 실패"
        }
    }

    func requestFolderAccess() {
        let panel = NSOpenPanel()
        panel.message = "Space News가 작동하려면 스크립트 폴더에 접근해야 합니다"
        panel.prompt = "접근 허용"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: BriefPaths.root)

        if panel.runModal() == .OK {
            if let url = panel.url {
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    UserDefaults.standard.set(bookmarkData, forKey: "folderBookmark")
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
        } else {
            statusText = "폴더 선택 취소됨 - 앱이 제대로 작동하지 않을 수 있습니다"
        }
    }

    func runCollectorAlternative() {
        let script = """
        tell application "Terminal"
            if not (exists window 1) then
                activate
            end if
            do script "cd '\(BriefPaths.root)' && '\(BriefPaths.collectorScript)'; echo '완료! 이 창을 닫아도 됩니다.'" in window 1
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if let error = error {
                let script2 = """
                tell application "Terminal"
                    do script "cd '\(BriefPaths.root)' && '\(BriefPaths.collectorScript)'; echo '완료!'"
                end tell
                """
                if let appleScript2 = NSAppleScript(source: script2) {
                    var error2: NSDictionary?
                    appleScript2.executeAndReturnError(&error2)
                }
                statusText = "터미널에서 수집 시작 (새 탭 확인)"
            } else {
                statusText = "터미널에서 수집 실행 중..."
            }
        }

        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                self.refresh()
            }
        }
    }

    func runCollector() {
        guard !isRunning else { return }
        isRunning = true
        statusText = "수집 실행 중..."

        let task = Process()
        task.executableURL = URL(fileURLWithPath: BriefPaths.collectorScript)
        task.arguments = []

        task.currentDirectoryURL = URL(fileURLWithPath: BriefPaths.root)

        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        env["HOME"] = NSHomeDirectory()
        env["WORKSPACE"] = BriefPaths.root
        env["BRIEF_PREFLIGHT_WAIT_S"] = "30"
        env["BRIEF_PREFLIGHT_RETRY_S"] = "20"
        task.environment = env

        do {
            try task.run()

            // DispatchQueue 사용 — Swift concurrency cooperative thread 차단 방지
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // 두 파이프 동시 읽기 (데드락 방지)
                var outData = Data()
                var errData = Data()
                let readGroup = DispatchGroup()
                readGroup.enter()
                DispatchQueue.global().async {
                    outData = out.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.wait()
                task.waitUntilExit()

                let rc = task.terminationStatus
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    self?.isRunning = false
                    if rc == 0 || rc == 1 {
                        self?.statusText = rc == 0 ? "수집 완료 ✅" : "수집 완료 (로그 쓰기 실패) ⚠️"
                    } else {
                        let errorMsg = errStr.isEmpty ? outStr : errStr
                        let preview = String(errorMsg.prefix(200))
                        self?.statusText = "수집 실패 (rc=\(rc)): \(preview)"
                        print("=== 수집 스크립트 출력 ===")
                        print("STDOUT:", outStr)
                        print("STDERR:", errStr)
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

// MARK: - Space News Main View (Apple Style)

struct StockSpaceContentView: View {
    @ObservedObject var vm: BriefViewModel
    let onBackToHome: () -> Void
    @State private var showRawText = false
    @State private var hasCheckedAccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar Header with Material Background
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    // Back Button - System Style
                    Button(action: onBackToHome) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("첫 화면으로")

                    // Title Section
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Space News")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        // Status Indicator Capsule
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

                    // Collect Button — macOS 네이티브
                    ActionButton(
                        vm.isRunning ? "수집 중..." : "정보 수집",
                        icon: vm.isRunning ? nil : "antenna.radiowaves.left.and.right",
                        color: AppStyle.spaceBlue,
                        isLoading: vm.isRunning,
                        action: { vm.runCollector() }
                    )
                }
                .padding(.horizontal, AppStyle.contentInset)
                .padding(.vertical, 12)

                // Metadata Bar — 조건부 뷰 없음, 동일 구조 유지
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(metadataSummary)
                            .font(.caption2)
                            .foregroundStyle(vm.metadata.isEmpty ? .tertiary : .secondary)
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

            // Warning Banner - Folder Access
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
                            .font(.caption2)
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

            // Main Content
            Group {
                if showRawText {
                    ScrollView {
                        Text(vm.inboxText.isEmpty ? "내용 없음" : vm.inboxText)
                            .textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppStyle.contentInset)
                    }
                    .background(AppStyle.pageBg)
                } else {
                    ScrollView {
                        if vm.briefItems.isEmpty {
                            // Empty State - Apple Style
                            VStack(spacing: 14) {
                                Image(systemName: "tray")
                                    .font(.system(size: 44, weight: .light))
                                    .foregroundStyle(.tertiary)

                                Text("데이터를 불러오는 중...")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                Text("'정보 수집' 버튼을 눌러 최신 데이터를 가져오세요")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(60)
                        } else {
                            LazyVStack(spacing: AppStyle.sectionSpacing) {
                                ForEach(vm.briefItems) { item in
                                    BriefItemCard(item: item)
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

    // MARK: - Metadata 요약 (단일 텍스트, 조건부 뷰 없음)

    private var metadataSummary: String {
        guard !vm.metadata.isEmpty else { return "대기 중" }
        let parsed = parseMetadata(vm.metadata)
        return parsed.map { $0.value }.joined(separator: " · ")
    }

    private func statusIndicatorColor(_ status: String) -> Color {
        if status.contains("완료") {
            return AppStyle.successGreen
        } else if status.contains("실패") || status.contains("오류") {
            return AppStyle.importantRed
        } else if status.contains("실행 중") {
            return AppStyle.spaceBlue
        } else {
            return .gray
        }
    }

    private func parseMetadata(_ metadata: String) -> [(key: String, value: String, icon: String)] {
        var result: [(String, String, String)] = []
        let lines = metadata.split(separator: "\n")

        for line in lines {
            let text = String(line)
            if text.contains("생성 시각:") {
                let value = text.components(separatedBy: ": ").last ?? ""
                result.append(("time", value, "clock"))
            } else if text.contains("워치리스트 항목") {
                let value = text.components(separatedBy: ": ").last ?? ""
                result.append(("items", value, "list.bullet"))
            } else if text.contains("검색 윈도우:") {
                result.append(("window", "24시간", "calendar"))
            }
        }

        return result
    }
}

// MARK: - Brief Item Card (Apple Style)

struct BriefItemCard: View {
    let item: BriefItem
    @State private var isExpanded = false
    @State private var isHovered = false
    // 번역은 Python 수집기가 처리 — 인앱 이중 번역 제거 (GPU 경합 방지)

    var displayHeadlines: [String] {
        isExpanded ? item.headlines : Array(item.headlines.prefix(3))
    }

    private var accentColor: Color {
        if item.isSpaceEconomy { return AppStyle.trendingPurple }
        if item.hasIssue { return AppStyle.importantRed }
        return AppStyle.spaceBlue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row
            HStack(alignment: .center, spacing: 12) {
                // Icon - Company Logo or System Icon
                if let logoName = item.logoImageName {
                    Image(logoName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.12), accentColor.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)

                        Image(systemName: item.isSpaceEconomy ? "globe.asia.australia.fill" :
                              item.hasIssue ? "exclamationmark.triangle.fill" : "chart.bar.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(accentColor)
                            .symbolRenderingMode(.hierarchical)
                    }
                }

                // Title and Metadata
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if item.hasIssue {
                            BadgeLabel("중요", color: AppStyle.importantRed)
                        }
                    }

                    HStack(spacing: 10) {
                        Label("\(item.articleCount)", systemImage: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if item.issueCount > 0 {
                            Label("\(item.issueCount) 이슈", systemImage: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(AppStyle.importantRed)
                        }

                        if !item.headlines.isEmpty {
                            Label("\(item.headlines.count) 뉴스", systemImage: "newspaper.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()
            }
            .padding(AppStyle.cardPadding)

            // Summary
            Text(item.summary)
                .font(.body)
                .foregroundStyle(item.hasIssue || item.isSpaceEconomy ? .primary : .secondary)
                .lineLimit(isExpanded ? nil : 3)
                .padding(.horizontal, AppStyle.cardPadding)
                .padding(.bottom, item.headlines.isEmpty ? AppStyle.cardPadding : 10)

            // Headlines Section
            if !displayHeadlines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(displayHeadlines, id: \.self) { headline in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(accentColor.opacity(0.35))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)

                            Text(headline.replacingOccurrences(of: " KST", with: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }

                    // Show More / Collapse Button
                    if !isExpanded && item.headlines.count > 3 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("외 \(item.headlines.count - 3)건 더보기")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else if isExpanded && item.headlines.count > 3 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("접기")
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 9))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, AppStyle.cardPadding)
                .padding(.bottom, AppStyle.cardPadding)
            }

            // Expanded Details Section
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ListRowDivider()
                        .padding(.horizontal, AppStyle.cardPadding)

                    if !item.reason.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.yellow)
                                Text("왜 중요한가")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }

                            Text(item.reason)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, AppStyle.cardPadding)
                    }

                    HStack(spacing: 12) {
                        if !item.timestamp.isEmpty {
                            Label(item.timestamp.replacingOccurrences(of: " KST", with: ""), systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if !item.sources.isEmpty {
                            Text(item.sources)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, AppStyle.cardPadding)
                    .padding(.bottom, 12)
                }
                .transition(.opacity)
            }
        }
        .appleCard(
            isHovered: isHovered,
            hasBorder: item.hasIssue || item.isSpaceEconomy,
            borderColor: accentColor
        )
        .scaleEffect(isHovered ? 1.003 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onHover { hovering in
            isHovered = hovering
        }
        // 인앱 번역 제거 — Python 수집기가 마크다운에 번역 완료 후 저장
    }

}

#Preview {
    StockSpaceContentView(vm: BriefViewModel(), onBackToHome: {})
}
