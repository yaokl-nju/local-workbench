import AppKit
import SwiftUI
import WebKit
import CryptoKit

enum AskProvider: String, CaseIterable, Identifiable {
    case chatgpt, deepseek, doubao
    var id: String { rawValue }
    var name: String { switch self { case .chatgpt: return "ChatGPT"; case .deepseek: return "DeepSeek"; case .doubao: return "豆包" } }
    var home: URL {
        let address: String
        switch self {
        case .chatgpt: address = "https://chatgpt.com/"
        case .deepseek: address = "https://chat.deepseek.com/"
        case .doubao: address = "https://www.doubao.com/chat/"
        }
        return URL(string: address)!
    }
    // Fixed identifiers preserve cookies/storage across launches, separately per provider.
    func profileID(namespace: String = "production") -> UUID {
        let bytes = Array(SHA256.hash(data: Data("LocalNotes.ask.\(namespace).\(rawValue)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

enum WebPolicy {
    static func isNavigationCancellation(_ failure: Error) -> Bool {
        let error = failure as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
            || error.domain == "WebKitErrorDomain" && error.code == 102
    }
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" || scheme == "http" { return url.host != nil && url.user == nil && url.password == nil }
        let base = url.absoluteString.components(separatedBy: "#").first ?? ""
        return scheme == "about" && ["about:blank", "about:srcdoc"].contains(base) || scheme == "blob"
    }
    static func testOrigin(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "http", url.host == "127.0.0.1", url.port != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

@MainActor final class AskBrowser: ObservableObject {
    @Published var selected: AskProvider = .chatgpt
    @Published private(set) var sessions: [AskProvider: WebSession] = [:]
    @Published private(set) var opened = false
    func open() { opened = true; select(selected) }
    func select(_ provider: AskProvider) {
        selected = provider
        if sessions[provider] == nil {
            let env = ProcessInfo.processInfo.environment
            let test = WebPolicy.testOrigin(env["LOCAL_NOTES_WEB_TEST_ORIGIN"])
            let home = test?.appendingPathComponent(provider.rawValue) ?? provider.home
            let profile = provider.profileID(namespace: env["LOCAL_NOTES_DATA_DIR"] ?? "production")
            let session = WebSession(provider: provider, home: home, dataStore: WKWebsiteDataStore(forIdentifier: profile))
            sessions[provider] = session
            session.start()
        }
    }
}

@MainActor final class WebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let provider: AskProvider
    let home: URL
    let webView: WKWebView
    @Published var loading = false
    @Published var progress = 0.0
    @Published var canBack = false
    @Published var canForward = false
    @Published var address = ""
    @Published var error: String?
    @Published var notice = ""
    private var observations: [NSKeyValueObservation] = []
    private(set) var popups: [WebPopup] = []
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var cancelledDownloads: Set<ObjectIdentifier> = []
    private(set) var started = false
    private var pendingURL: URL?
    private var failedURL: URL?
    init(provider: AskProvider, home: URL, dataStore: WKWebsiteDataStore) {
        self.provider = provider; self.home = home
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityLabel("\(provider.name) 网页")
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.syncLater() },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.syncLater() },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.syncLater() },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.syncLater() },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.syncLater() }
        ]
    }
    nonisolated private func syncLater() { Task { @MainActor [weak self] in self?.sync() } }
    private func sync() {
        loading = webView.isLoading; progress = webView.estimatedProgress
        canBack = webView.canGoBack; canForward = webView.canGoForward
        address = webView.url?.host ?? home.host ?? ""
    }
    func start() { guard !started else { return }; started = true; load(home) }
    func load(_ url: URL) {
        guard WebPolicy.allows(url) else { return }
        error = nil; notice = ""; webView.load(URLRequest(url: url, timeoutInterval: 60))
    }
    func refresh() {
        if error != nil, let failedURL { load(failedURL); return }
        error = nil; notice = ""; if webView.url != nil { webView.reload() } else { load(home) }
    }
    func goHome() { load(home) }
    func external() {
        let url = webView.url ?? home
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), WebPolicy.allows(url) else { return }
        NSWorkspace.shared.open(url)
    }
    func find(_ text: String, backwards: Bool = false, completion: @escaping (Bool) -> Void) {
        guard !text.isEmpty else { completion(false); return }
        let config = WKFindConfiguration(); config.backwards = backwards; config.wraps = true; config.caseSensitive = false
        webView.find(text, configuration: config) { result in completion(result.matchFound) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { error = nil; notice = ""; sync() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { error = nil; failedURL = nil; sync() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(webView, error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(webView, error) }
    private func failed(_ view: WKWebView, _ failure: Error) {
        // Turning a navigation into a download intentionally interrupts its frame load.
        guard !WebPolicy.isNavigationCancellation(failure) else { return }
        let message = "网页加载失败：\(failure.localizedDescription)"
        if view === webView { failedURL = pendingURL; error = message; loading = false } else { notice = "登录窗口\(message)" }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { error = "网页进程已停止，请重新加载。"; loading = false }
        else { notice = "登录窗口网页进程已停止，请关闭窗口后重试。" }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let inlineFrame = navigationAction.targetFrame?.isMainFrame == false && url.scheme == "data"
        guard WebPolicy.allows(url) || inlineFrame else {
            if navigationAction.targetFrame?.isMainFrame != false { notice = "此链接需要其他应用打开，请使用默认浏览器入口。" }
            decisionHandler(.cancel); return
        }
        if webView === self.webView, navigationAction.targetFrame?.isMainFrame == true, !navigationAction.shouldPerformDownload { pendingURL = url }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, navigationAction.request.url.map(WebPolicy.allows) ?? true else { return nil }
        let popup = WebPopup(configuration: configuration, session: self)
        popups.append(popup); popup.window.makeKeyAndOrderFront(nil)
        return popup.webView
    }
    func webViewDidClose(_ webView: WKWebView) { popups.first(where: { $0.webView === webView })?.window.close() }
    func closePopup(_ popup: WebPopup) { popups.removeAll { $0 === popup } }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories; panel.canChooseFiles = true
        if let window = webView.window { panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) } }
        else { completionHandler(nil) }
    }
    private func javascriptAlert(_ view: WKWebView, message: String) -> NSAlert {
        let alert = NSAlert(); alert.messageText = "\(provider.name) · \(view.url?.host ?? "网页")"; alert.informativeText = message
        return alert
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = javascriptAlert(webView, message: message); alert.addButton(withTitle: "好")
        guard let window = webView.window else { completionHandler(); return }
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = javascriptAlert(webView, message: message); alert.addButton(withTitle: "确认"); alert.addButton(withTitle: "取消")
        guard let window = webView.window else { completionHandler(false); return }
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = javascriptAlert(webView, message: prompt); alert.addButton(withTitle: "确认"); alert.addButton(withTitle: "取消")
        let field = NSTextField(string: defaultText ?? ""); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24); alert.accessoryView = field
        guard let window = webView.window else { completionHandler(nil); return }
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { track(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { track(download) }
    private func track(_ download: WKDownload) { downloads[ObjectIdentifier(download)] = download; download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath: suggestedFilename).lastPathComponent; panel.title = "保存 \(provider.name) 下载文件"
        guard let window = webView.window else { cancelledDownloads.insert(ObjectIdentifier(download)); completionHandler(nil); return }
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { self?.cancelledDownloads.insert(ObjectIdentifier(download)); completionHandler(nil); return }
            // WKDownload requires a destination that does not already exist. Never delete an existing file to satisfy it.
            guard !FileManager.default.fileExists(atPath: url.path) else { self?.notice = "下载未保存，请选择一个尚不存在的文件名。"; self?.cancelledDownloads.insert(ObjectIdentifier(download)); completionHandler(nil); return }
            self?.notice = "正在下载…"; completionHandler(url)
        }
    }
    func downloadDidFinish(_ download: WKDownload) { downloads.removeValue(forKey: ObjectIdentifier(download)); notice = "下载已保存。" }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download); downloads.removeValue(forKey: id)
        if cancelledDownloads.remove(id) != nil { return }
        notice = "下载失败：\(error.localizedDescription)"
    }
}

@MainActor final class WebPopup: NSObject, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    weak var session: WebSession?
    init(configuration: WKWebViewConfiguration, session: WebSession) {
        self.session = session
        webView = WKWebView(frame: .zero, configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "\(session.provider.name) · 网页窗口"; window.isReleasedWhenClosed = false
        window.contentView = webView; window.delegate = self; window.center()
        webView.navigationDelegate = session; webView.uiDelegate = session
    }
    func windowWillClose(_ notification: Notification) { webView.stopLoading(); session?.closePopup(self) }
}

struct WebSurface: NSViewRepresentable {
    let session: WebSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct AskView: View {
    @ObservedObject var browser: AskBrowser
    var active: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                Text("随时问").font(.system(size: 21, weight: .bold))
                Picker("AI 网页", selection: Binding(get: { browser.selected }, set: { browser.select($0) })) {
                    ForEach(AskProvider.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 360)
                Spacer(minLength: 0)
            }.padding(18)
            if let session = browser.sessions[browser.selected] { BrowserPane(session: session, active: active).id(browser.selected) }
        }.background(Color.white)
    }
}

struct BrowserPane: View {
    @ObservedObject var session: WebSession
    var active: Bool
    @State private var finding = false
    @State private var query = ""
    @State private var found: Bool?
    @FocusState private var findFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { session.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!session.canBack).accessibilityLabel("网页后退")
                Button { session.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!session.canForward).accessibilityLabel("网页前进")
                Button { session.refresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新网页")
                Button { session.goHome() } label: { Image(systemName: "house") }.accessibilityLabel("平台首页")
                Text(session.address.isEmpty ? session.home.host ?? "" : session.address).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button { session.external() } label: { Label("默认浏览器", systemImage: "arrow.up.right.square") }.accessibilityLabel("在默认浏览器打开网页")
            }.buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 11)
            if finding {
                HStack {
                    TextField("查找网页文字", text: $query).textFieldStyle(.roundedBorder).focused($findFocused).onSubmit { search() }.accessibilityLabel("查找网页文字")
                    if let found { Text(found ? "已定位" : "未找到").font(.caption).foregroundStyle(.secondary) }
                    Button("上一处") { search(backwards: true) }; Button("下一处") { search() }
                    Button { finding = false } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭网页查找")
                }.padding(.horizontal, 18).padding(.bottom, 10)
            }
            Divider()
            if session.loading { ProgressView(value: session.progress).progressViewStyle(.linear).accessibilityLabel("网页加载进度") }
            if let error = session.error {
                HStack { Image(systemName: "wifi.exclamationmark"); Text(error).font(.caption); Spacer(); Button("重试") { session.refresh() } }.padding(12).background(Color.orange.opacity(0.12))
            }
            WebSurface(session: session).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(session.notice.isEmpty ? "登录与对话由\(session.provider.name)提供 · 登录状态保存在本机" : session.notice).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                if session.loading { Button("停止加载") { session.webView.stopLoading() }.font(.caption).buttonStyle(.borderless) }
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }.onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            guard active else { return }; finding = true; findFocused = true
        }
    }
    private func search(backwards: Bool = false) { session.find(query, backwards: backwards) { found = $0 } }
}
