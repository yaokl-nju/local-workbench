import AppKit
import SwiftUI
import Darwin

@MainActor final class AppDelegate: NSResponder, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var store: AppStore!
    private var eventMonitor: Any?
    private var lockFD: Int32 = -1
    private var discardOnExit = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let base: URL
        if let override = ProcessInfo.processInfo.environment["LOCAL_NOTES_DATA_DIR"] { base = URL(fileURLWithPath: override, isDirectory: true) }
        else { base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalNotes", isDirectory: true) }
        do { try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        catch { let alert = NSAlert(); alert.messageText = "无法创建数据目录"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil); return }
        lockFD = Darwin.open(base.appendingPathComponent(".instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "cn.localnotes.desktop").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { other.activate(options: [.activateAllWindows]) }
            NSApp.terminate(nil); return
        }
        store = AppStore(directory: base)
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "本地便签"; window.minSize = NSSize(width: 900, height: 680); window.delegate = self
        window.isReleasedWhenClosed = false; window.center()
        window.contentView = NSHostingView(rootView: RootView(store: store))
        window.setFrameAutosaveName("LocalNotesMain")
        if CommandLine.arguments.contains("--compact") { window.setContentSize(NSSize(width: 900, height: 652)); window.center() }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        installKeys()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !discardOnExit, let store, store.saveError != nil else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "还有任务变更未保存"; alert.informativeText = store.saveError!; alert.addButton(withTitle: "重试保存"); alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "放弃未保存变更并退出")
        switch alert.runModal() {
        case .alertFirstButtonReturn: store.save(); return store.saveError == nil ? .terminateNow : .terminateCancel
        case .alertThirdButtonReturn: discardOnExit = true; return .terminateNow
        default: return .terminateCancel
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Ask while the window still exists, so cancellation keeps the edits visible.
        guard store.saveError != nil else { return true }
        return applicationShouldTerminate(NSApp) == .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { if lockFD >= 0 { flock(lockFD, LOCK_UN); Darwin.close(lockFD) } }
    private func makeMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "本地便签")
        let appRoot = NSMenuItem(); appRoot.submenu = appMenu; menu.addItem(appRoot)
        add("关于本地便签", #selector(about), "", to: appMenu)
        appMenu.addItem(.separator()); add("隐藏本地便签", #selector(NSApplication.hide(_:)), "h", to: appMenu, target: NSApp)
        appMenu.addItem(.separator()); add("退出本地便签", #selector(NSApplication.terminate(_:)), "q", to: appMenu, target: NSApp)
        let fileMenu = submenu("文件", in: menu)
        add("快速捕获…", #selector(capture), "n", to: fileMenu)
        add("今日规划…", #selector(plan), "p", to: fileMenu, modifiers: [.command, .shift])
        fileMenu.addItem(.separator()); add("导入工作台 JSON…", #selector(importData), "", to: fileMenu); add("导出任务备份…", #selector(exportData), "e", to: fileMenu, modifiers: [.command, .shift]); add("查看数据文件", #selector(revealData), "", to: fileMenu)
        fileMenu.addItem(.separator()); add("关闭窗口", #selector(NSWindow.performClose(_:)), "w", to: fileMenu, target: nil)
        let edit = submenu("编辑", in: menu)
        add("撤销", #selector(undo), "z", to: edit, target: nil)
        add("重做文字编辑", Selector(("redo:")), "z", to: edit, target: nil, modifiers: [.command, .shift])
        edit.addItem(.separator())
        add("剪切", #selector(NSText.cut(_:)), "x", to: edit, target: nil); add("拷贝", #selector(NSText.copy(_:)), "c", to: edit, target: nil); add("粘贴", #selector(NSText.paste(_:)), "v", to: edit, target: nil); add("全选", #selector(NSText.selectAll(_:)), "a", to: edit, target: nil)
        let view = submenu("显示", in: menu)
        add("今日", #selector(today), "1", to: view); add("本周", #selector(week), "2", to: view); add("待定", #selector(later), "3", to: view)
        view.addItem(.separator()); add("命令与搜索…", #selector(commands), "k", to: view); add("搜索当前列表", #selector(search), "f", to: view)
        let help = submenu("帮助", in: menu); add("快捷键", #selector(shortcuts), "?", to: help)
        NSApp.mainMenu = menu
        // The responder chain handles editing undo; the delegate handles task undo otherwise.
        NSApp.nextResponder = self
    }
    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu { let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); let sub = NSMenu(title: title); item.submenu = sub; parent.addItem(item); return sub }
    private func add(_ title: String, _ action: Selector, _ key: String, to menu: NSMenu, target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = .command) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = modifiers
        item.target = target ?? (action == #selector(undo) || action == #selector(NSWindow.performClose(_:)) || [#selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:)), Selector(("redo:"))].contains(action) ? nil : self)
        menu.addItem(item)
    }
    private func installKeys() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.store.immersive && event.keyCode == 53 { self.store.pauseFocus(); return nil }
            if self.store.sheet == .commands {
                if event.keyCode == 126 || event.keyCode == 125 { NotificationCenter.default.post(name: .commandMove, object: event.keyCode == 126 ? -1 : 1); return nil }
                if event.keyCode == 36 || event.keyCode == 76 { NotificationCenter.default.post(name: .commandExecute, object: nil); return nil }
            }
            if self.window.attachedSheet != nil || self.store.sheet != nil { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == [.command, .option], let id = self.store.selected, event.keyCode == 126 || event.keyCode == 125 { self.store.shift(id, by: event.keyCode == 126 ? -1 : 1); return nil }
            if self.window.firstResponder is NSTextView { return event }
            guard modifiers.isEmpty || modifiers == .shift else { return event }
            switch event.charactersIgnoringModifiers {
            case "1": self.store.switchTo(.today)
            case "2": self.store.switchTo(.week)
            case "3": self.store.switchTo(.later)
            case "n", "N": self.capture()
            case "p", "P": self.store.toggleFocus()
            case "/": self.search()
            case "?": self.shortcuts()
            default: return event
            }
            return nil
        }
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "本地便签", .applicationVersion: "1.0", .credits: NSAttributedString(string: "今日 · 本周 · 待定\n基于极简工作台任务功能的独立 macOS 应用。")]) }
    @objc func capture() { store.sheet = .capture }
    @objc func plan() { store.sheet = .plan }
    @objc func commands() { store.sheet = .commands }
    @objc func search() { NotificationCenter.default.post(name: .focusSearch, object: nil) }
    @objc func shortcuts() { store.sheet = .shortcuts }
    @objc func today() { store.switchTo(.today) }
    @objc func week() { store.switchTo(.week) }
    @objc func later() { store.switchTo(.later) }
    @objc func undo() { store.undo() }
    @objc func importData() { store.importData() }
    @objc func exportData() { store.exportData() }
    @objc func revealData() { store.revealData() }
}

@main struct LocalNotesApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}
