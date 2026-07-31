import AppKit
import Foundation
import OpenIslandCore
import WebKit
import os

struct OpenCodeWebQuotaFetcher: ProviderQuotaFetching {
    let providerID: AgentUsageProviderID = .opencode

    func fetchQuota() async throws -> ProviderQuotaSnapshot? {
        try await OpenCodeQuotaSessionManager.shared.fetchQuota()
    }
}

@MainActor
final class OpenCodeQuotaSessionManager: ObservableObject {
    static let shared = OpenCodeQuotaSessionManager()

    private static let dashboardBaseURLs = [
        URL(string: "https://opencode.ai")!,
        URL(string: "https://console.opencode.ai")!
    ]

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var workspaceID: String?
    @Published private(set) var errorMessage: String?
    private var lastAcceptedSnapshot: ProviderQuotaSnapshot?
    private var sharedNavigator: OpenCodeWebNavigator?
    private var backgroundLoopTask: Task<Void, Never>?
    private let logger = os.Logger(
        subsystem: "com.zaaacqwq.VibeIsland",
        category: "OpenCodeQuota"
    )

    /// Idle cadence: re-read the Go dashboard this often when nothing is
    /// happening. Active OpenCode turns trigger an immediate refresh instead
    /// (see `refreshAfterOpenCodeTurnCompleted`).
    private static let backgroundRefreshInterval: TimeInterval = 15 * 60
    private static let workspaceIDDefaultsKey = "OpenCodeQuotaWorkspaceID"

    private init() {
        workspaceID = Self.persistedWorkspaceID()
    }

    func startBackgroundRefresh() {
        guard backgroundLoopTask == nil else { return }
        backgroundLoopTask = Task { @MainActor [weak self] in
            guard self != nil else { return }
            AgentMonitorManager.shared.refreshProviderQuota(.opencode, force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Int(Self.backgroundRefreshInterval)))
                guard !Task.isCancelled else { return }
                AgentMonitorManager.shared.refreshProviderQuota(.opencode, force: true)
            }
        }
    }

    func stopBackgroundRefresh() {
        backgroundLoopTask?.cancel()
        backgroundLoopTask = nil
    }

    /// Called the moment an OpenCode turn completes so the Go dashboard quota
    /// updates without waiting for the idle cadence. Runs headlessly against
    /// the persisted opencode.ai session — no browser window is opened.
    func refreshAfterOpenCodeTurnCompleted() {
        AgentMonitorManager.shared.refreshProviderQuota(.opencode, force: true)
    }

    func fetchQuota() async throws -> ProviderQuotaSnapshot? {
        guard !isRefreshing else { return nil }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        return try await fetchQuotaInternal()
    }

    /// Manual "Refresh" button. Re-reads the Go dashboard headlessly through
    /// the persisted opencode.ai session — no browser window is opened. Only
    /// the explicit "Sign in" actions surface a visible login window.
    func refresh() {
        AgentMonitorManager.shared.refreshProviderQuota(.opencode, force: true)
    }

    /// Reuses a single off-screen web view across refreshes. The view is hosted
    /// in an invisible window so WebKit actually lays out and hydrates the
    /// client-rendered dashboard (see `OpenCodeWebNavigator`).
    private func sharedWebNavigator() -> OpenCodeWebNavigator {
        if let sharedNavigator { return sharedNavigator }
        let created = OpenCodeWebNavigator()
        sharedNavigator = created
        return created
    }

    private func fetchQuotaInternal() async throws -> ProviderQuotaSnapshot? {
        do {
            let navigator = sharedWebNavigator()

            // The only page that actually exposes the Rolling/Weekly/Monthly
            // windows is the workspace-scoped Go dashboard:
            //   https://opencode.ai/workspace/<wrk_id>/go
            // Bare /go is an overview page (has "Usage" but no windows) and
            // /workspace/go bounces to auth, so we go straight for the
            // workspace-scoped URL, discovering the id when we don't have it.
            if let knownID = workspaceID ?? Self.persistedWorkspaceID(),
               let snapshot = try await loadWorkspaceGoSnapshot(
                   knownID, with: navigator
               ) {
                return snapshot
            }

            guard let resolvedID = try await resolveWorkspaceID(with: navigator) else {
                throw OpenCodeQuotaError.workspaceNotFound
            }
            rememberWorkspaceID(resolvedID)

            if let snapshot = try await loadWorkspaceGoSnapshot(
                resolvedID, with: navigator
            ) {
                return snapshot
            }
            throw OpenCodeQuotaError.usageNotFound
        } catch {
            logger.error("fetchQuota failed: \(error.localizedDescription, privacy: .public)")
            if lastAcceptedSnapshot == nil {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// Loads the workspace-scoped Go dashboard and parses its quota windows.
    /// Returns `nil` only when the page renders but never exposes parseable
    /// quota; navigation/auth failures throw.
    private func loadWorkspaceGoSnapshot(
        _ workspaceID: String,
        with navigator: OpenCodeWebNavigator
    ) async throws -> ProviderQuotaSnapshot? {
        try await loadSnapshot(
            with: navigator,
            url: Self.dashboardURL(path: "/workspace/\(workspaceID)/go"),
            workspaceID: workspaceID
        )
    }

    /// Discovers the account's workspace id from a logged-in page. The id lives
    /// in the rendered HTML/SSR payload even when it isn't a plain `<a href>`
    /// (the dashboard navigates via JS), so we regex-scan the full page source
    /// across a few candidate pages rather than relying on anchor links.
    private func resolveWorkspaceID(
        with navigator: OpenCodeWebNavigator
    ) async throws -> String? {
        for path in ["/workspace", "/go", "/"] {
            let landingURL = try await navigator.load(Self.dashboardURL(path: path))
            if Self.isLoginURL(landingURL) { continue }
            if let id = Self.workspaceID(from: landingURL) {
                logger.debug("resolved workspace id \(id, privacy: .public) from url")
                return id
            }

            for _ in 0..<12 {
                if let html = try? await navigator.stringByEvaluatingJavaScript(
                    "document.documentElement.outerHTML"
                ), let id = Self.firstWorkspaceID(in: html) {
                    logger.debug("resolved workspace id \(id, privacy: .public) from \(path, privacy: .public)")
                    return id
                }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        logger.error("workspace id resolution failed across candidate pages")
        return nil
    }

    /// First `wrk_<alphanumeric>` token found in arbitrary page text.
    private static func firstWorkspaceID(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"wrk_[A-Za-z0-9]+"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matched = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matched])
    }

    private static func persistedWorkspaceID() -> String? {
        UserDefaults.standard.string(forKey: workspaceIDDefaultsKey)
    }

    private func rememberWorkspaceID(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        workspaceID = id
        UserDefaults.standard.set(id, forKey: Self.workspaceIDDefaultsKey)
    }

    func disconnect() {
        Task {
            await Self.clearWebsiteData(matching: ["opencode.ai"])
            isAuthenticated = false
            workspaceID = nil
            UserDefaults.standard.removeObject(forKey: Self.workspaceIDDefaultsKey)
            lastAcceptedSnapshot = nil
            errorMessage = nil
            AgentMonitorManager.shared.clearProviderQuota(.opencode)
        }
    }

    func acceptSnapshot(_ snapshot: ProviderQuotaSnapshot, workspaceID: String?) {
        rememberWorkspaceID(workspaceID)
        lastAcceptedSnapshot = snapshot
        isAuthenticated = true
        errorMessage = nil
        AgentMonitorManager.shared.recordProviderQuota(snapshot)
    }

    private static func workspaceID(from url: URL) -> String? {
        let components = url.pathComponents
        guard let workspaceIndex = components.firstIndex(of: "workspace"),
              components.indices.contains(workspaceIndex + 1) else {
            return nil
        }
        let candidate = components[workspaceIndex + 1]
        return candidate.hasPrefix("wrk_") ? candidate : nil
    }

    private static func isLoginURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        let path = url.path.lowercased()
        let isOpenCodeHost = host == "opencode.ai" || host.hasSuffix(".opencode.ai")
        return !isOpenCodeHost
            || host == "auth.opencode.ai"
            || path.contains("/auth")
            || path.contains("/login")
            || path.contains("/signin")
    }

    private static func dashboardURL(
        path: String,
        baseURL: URL = dashboardBaseURLs[0]
    ) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private func loadSnapshot(
        with navigator: OpenCodeWebNavigator,
        url: URL,
        workspaceID resolvedWorkspaceID: String?
    ) async throws -> ProviderQuotaSnapshot? {
        logger.debug("navigating to \(url.absoluteString, privacy: .public)")
        let finalURL = try await navigator.load(url)
        let isLogin = Self.isLoginURL(finalURL)
        logger.debug("landed on \(finalURL.absoluteString, privacy: .public) isLogin=\(isLogin)")
        guard !isLogin else {
            if lastAcceptedSnapshot == nil {
                isAuthenticated = false
            }
            throw OpenCodeQuotaError.notAuthenticated
        }

        var lastSource = ""
        for _ in 0..<20 {
            let source = try await navigator.stringByEvaluatingJavaScript(
                "document.documentElement.outerHTML + '\\n' + (document.body?.innerText || '')"
            )
            lastSource = source
            if let snapshot = OpenCodeQuotaParser.parse(
                pageSource: source,
                fetchedAt: .now
            ) {
                rememberWorkspaceID(resolvedWorkspaceID ?? Self.workspaceID(from: finalURL))
                isAuthenticated = true
                errorMessage = nil
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        logger.error(
            "parse failed url=\(finalURL.absoluteString, privacy: .public) textLen=\(lastSource.count) hasUsage=\(lastSource.contains("Usage")) hasRolling=\(lastSource.contains("Rolling")) snippet=\(Self.usageSnippet(from: lastSource), privacy: .public)"
        )
        throw OpenCodeQuotaError.usageNotFound
    }

    /// Extracts a short, whitespace-collapsed window around the first "Usage"
    /// occurrence so a parse failure reveals the page's real labels in the log.
    private static func usageSnippet(from source: String) -> String {
        guard let range = source.range(of: "Usage") else { return "<no-usage>" }
        let start = source.index(range.lowerBound, offsetBy: -40, limitedBy: source.startIndex)
            ?? source.startIndex
        let end = source.index(range.upperBound, offsetBy: 220, limitedBy: source.endIndex)
            ?? source.endIndex
        return source[start..<end]
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func clearWebsiteData(matching domains: [String]) async {
        let dataStore = WKWebsiteDataStore.default()
        let records = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()
            ) { continuation.resume(returning: $0) }
        }
        let matchingRecords = records.filter { record in
            let displayName = record.displayName.lowercased()
            return domains.contains { domain in
                displayName == domain || displayName.hasSuffix(".\(domain)")
            }
        }
        guard !matchingRecords.isEmpty else { return }
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: matchingRecords
            ) {
                continuation.resume()
            }
        }
    }
}

private final class OpenCodeWebNavigator: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var navigationContinuation: CheckedContinuation<URL, Error>?
    private var timeoutTask: Task<Void, Never>?

    @MainActor
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
        webView = WKWebView(frame: frame, configuration: configuration)

        // Host the web view in a transparent, click-through window that sits
        // *within* the screen's geometry. A zero-frame, window-less, or
        // off-screen WKWebView is treated as non-visible by the window server,
        // so WebKit throttles/suspends the compositor and JS — the SolidStart
        // dashboard's client-rendered usage widgets never hydrate and the
        // parser times out. That is why quota previously only refreshed while
        // the visible sign-in window was open. Keeping the window on-screen but
        // fully transparent and mouse-transparent renders the page for real
        // while staying invisible to the user.
        let origin = NSScreen.main?.visibleFrame.origin ?? .zero
        hostWindow = NSWindow(
            contentRect: NSRect(origin: origin, size: frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.alphaValue = 0
        hostWindow.ignoresMouseEvents = true
        hostWindow.isExcludedFromWindowsMenu = true
        hostWindow.hasShadow = false
        hostWindow.isReleasedWhenClosed = false
        hostWindow.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        hostWindow.contentView = webView

        super.init()
        webView.navigationDelegate = self
        hostWindow.orderFrontRegardless()
    }

    @MainActor
    func load(_ url: URL) async throws -> URL {
        guard navigationContinuation == nil else {
            throw OpenCodeQuotaError.navigationInProgress
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                navigationContinuation = continuation
                webView.load(URLRequest(url: url, timeoutInterval: 15))
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(OpenCodeQuotaError.timedOut))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.webView.stopLoading()
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    @MainActor
    func stringByEvaluatingJavaScript(_ script: String) async throws -> String {
        let value = try await webView.evaluateJavaScript(script)
        return value as? String ?? ""
    }

    @MainActor
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation = navigationContinuation else { return }
        navigationContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }

    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else {
            finish(.failure(OpenCodeQuotaError.invalidResponse))
            return
        }
        finish(.success(url))
    }

    @MainActor
    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    @MainActor
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }
}

enum OpenCodeQuotaError: LocalizedError {
    case notAuthenticated
    case workspaceNotFound
    case usageNotFound
    case navigationInProgress
    case timedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Sign in to opencode.ai first."
        case .workspaceNotFound:
            "The OpenCode Go usage page was not found for this account."
        case .usageNotFound:
            "The OpenCode Go usage page did not expose quota data."
        case .navigationInProgress:
            "An OpenCode page is already loading."
        case .timedOut:
            "The OpenCode dashboard took too long to load."
        case .invalidResponse:
            "OpenCode returned an invalid page."
        }
    }
}

@MainActor
final class OpenCodeLoginWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    static let shared = OpenCodeLoginWindowController()

    private var webView: WKWebView?
    private var parseTask: Task<Void, Never>?

    var hasVisibleWebView: Bool {
        webView != nil && window?.isVisible == true
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Sign in to OpenCode — close this window when finished")
        window.minSize = NSSize(width: 700, height: 500)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(reload: Bool = true) {
        guard let window else { return }
        let webView: WKWebView
        if let existingWebView = self.webView {
            webView = existingWebView
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            webView = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.autoresizingMask = [.width, .height]
            self.webView = webView
            window.contentView = webView
        }

        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        if reload || webView.url == nil {
            webView.load(URLRequest(url: URL(string: "https://opencode.ai/auth")!))
        } else {
            scheduleParseCurrentPage()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleParseCurrentPage()
    }

    func windowWillClose(_ notification: Notification) {
        parseTask?.cancel()
        parseTask = nil
        scheduleParseCurrentPage()
    }

    private func scheduleParseCurrentPage() {
        parseTask?.cancel()
        parseTask = Task { @MainActor [weak self, weak webView] in
            for _ in 0..<20 {
                guard let self, let webView, !Task.isCancelled else { return }
                if await self.parseCurrentPageNow(webView: webView) {
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func parseCurrentPageNow() async -> Bool {
        guard let webView else { return false }
        return await parseCurrentPageNow(webView: webView)
    }

    private func parseCurrentPageNow(webView: WKWebView) async -> Bool {
        let source = (try? await webView.evaluateJavaScript(
            "document.documentElement.outerHTML + '\\n' + (document.body?.innerText || '')"
        )) as? String ?? ""
        guard let snapshot = OpenCodeQuotaParser.parse(pageSource: source, fetchedAt: .now) else {
            return false
        }
        OpenCodeQuotaSessionManager.shared.acceptSnapshot(
            snapshot,
            workspaceID: Self.workspaceID(from: webView.url)
        )
        return true
    }

    private static func workspaceID(from url: URL?) -> String? {
        guard let url else { return nil }
        let components = url.pathComponents
        guard let workspaceIndex = components.firstIndex(of: "workspace"),
              components.indices.contains(workspaceIndex + 1) else {
            return nil
        }
        let candidate = components[workspaceIndex + 1]
        return candidate.hasPrefix("wrk_") ? candidate : nil
    }
}
