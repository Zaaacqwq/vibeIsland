import AppKit
import Foundation
import WebKit
import os

/// A visible in-app login window for Cursor. The user signs in to cursor.com
/// inside a `WKWebView`; once the `WorkosCursorSessionToken` cookie is set,
/// VibeIsland reads it straight from the web view's cookie store (the cookie is
/// HttpOnly, so `document.cookie` can't see it, but `WKHTTPCookieStore` returns
/// HttpOnly cookies), validates it, saves it to the Keychain, and closes.
///
/// Mirrors `OpenCodeLoginWindowController`, but Cursor exposes a real cookie we
/// can extract rather than a DOM we scrape.
@MainActor
final class CursorLoginWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    static let shared = CursorLoginWindowController()

    /// cursor.com bounces an unauthenticated visit here through the login flow
    /// and sets the session cookie once the dashboard renders.
    private static let dashboardURL = URL(string: "https://cursor.com/dashboard")!
    private static let cookieName = "WorkosCursorSessionToken"

    private var webView: WKWebView?
    private var pollTask: Task<Void, Never>?
    private var didCapture = false
    private let logger = os.Logger(
        subsystem: "com.zaaacqwq.VibeIsland",
        category: "CursorLogin"
    )

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Cursor — this window closes automatically once you're in"
        window.minSize = NSSize(width: 700, height: 520)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        didCapture = false

        let webView: WKWebView
        if let existing = self.webView {
            webView = existing
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

        webView.load(URLRequest(url: Self.dashboardURL))
        startPolling()
    }

    // MARK: - Cookie capture

    /// Polls the web view's cookie store until the session cookie appears. A
    /// timer is used in addition to `didFinish` because cursor.com sets the
    /// cookie via an async auth exchange that can land after navigation events
    /// have stopped firing.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            for _ in 0..<600 { // ~5 min at 500ms
                guard let self, !Task.isCancelled, !self.didCapture else { return }
                await self.captureCookieIfPresent()
                if self.didCapture { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func captureCookieIfPresent() async {
        guard let webView, !didCapture else { return }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard let token = Self.sessionToken(in: cookies) else { return }
        didCapture = true

        logger.debug("captured Cursor session cookie; validating")
        let succeeded = await CursorUsageSyncManager.shared.signIn(withToken: token)
        if succeeded {
            close()
        } else {
            // Let the user keep the window open to retry login; allow re-capture.
            didCapture = false
        }
    }

    private static func sessionToken(in cookies: [HTTPCookie]) -> String? {
        cookies.first {
            $0.name == cookieName
                && $0.domain.contains("cursor.com")
                && !$0.value.isEmpty
        }?.value
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in await self?.captureCookieIfPresent() }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        pollTask?.cancel()
        pollTask = nil
    }
}

private extension WKHTTPCookieStore {
    /// Async wrapper over the completion-based `getAllCookies`.
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
