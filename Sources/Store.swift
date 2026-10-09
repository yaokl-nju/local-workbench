import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SheetRoute: String, Identifiable { case capture, plan, commands, shortcuts; var id: String { rawValue } }

@MainActor final class AppStore: ObservableObject {
    @Published var state = Workspace()
    @Published var bucket: Bucket = .today
    @Published var asking = false
    @Published var selected: String?
    @Published var queries: [Bucket: String] = [:]
    @Published var filters: [Bucket: TaskFilter] = [:]
    @Published var collapsed: [Bucket: Bool] = [:]
    @Published var selectedTags: [Bucket: String] = [:]
    @Published var inlineDrafts: [Bucket: String] = [:]
    @Published var sheet: SheetRoute?
    @Published var clock = FocusClock()
    @Published var immersive = false
    @Published var message = ""
    @Published var saveError: String?
    @Published var loadError: String?
    @Published var undoLabel: String?
    @Published var currentDay = dayKey()
    @Published var dragging: String?
    @Published var dragPoint: CGPoint = .zero
    var dragFrames: [String: CGRect] = [:]
    let disk: DiskStore
    private var undoStates: [(Workspace, String)] = []
    private var timer: Timer?
    private var messageTimer: Timer?
    private var hasLoaded = false
    init(directory: URL) {
        disk = DiskStore(directory: directory)
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    var items: [NoteTask] { state[bucket] }
    var visible: [NoteTask] { items.filter { matches($0, query: queries[bucket] ?? "", filter: filters[bucket] ?? .all) } }
    var selection: NoteTask? {
        guard let selected, let (b, i) = state.locate(selected) else { return nil }; return state[b][i]
    }
    var sessions: Int { state.preferences.focusSessions[currentDay] ?? 0 }
    func reload() {
        do {
            let (loaded, notice) = try disk.load(); state = loaded; state.reconcile(); loadError = nil; hasLoaded = true
            if let notice { toast(notice) }
        } catch { loadError = error.localizedDescription; hasLoaded = false }
    }
    func save() {
        guard hasLoaded else { return }
        do { try disk.save(state); saveError = nil } catch { saveError = error.localizedDescription }
    }
    func change(_ label: String, undoable: Bool = true, _ action: (inout Workspace) -> Void) {
        guard hasLoaded else { return }
        let before = state
        action(&state); state.reconcile()
        guard before != state else { return }
        if undoable { undoStates.append((before, label)); if undoStates.count > 50 { undoStates.removeFirst() }; undoLabel = label }
        save()
    }
    func undo() {
        guard let (previous, label) = undoStates.popLast() else { return }
        let sessions = state.preferences.focusSessions
        let completionDays = state.preferences.completionDays
        state = previous
        state.preferences.focusSessions = sessions
        state.preferences.completionDays.merge(completionDays) { _, latest in latest }
        state.reconcile(); undoLabel = undoStates.last?.1
        if let selected, state.locate(selected) == nil { self.selected = nil }
        save(); toast("已撤销\(label)")
    }
    func toast(_ text: String) {
        message = text; messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in Task { @MainActor in self?.message = "" } }
    }
    func switchTo(_ b: Bucket) { asking = false; bucket = b; selected = nil }
    func showAsk() { asking = true; dragging = nil }
    @discardableResult func add(_ text: String, to b: Bucket, tag: String = "TODO") -> Bool {
        let parsed = ParsedTask(text, fallbackTag: tag)
        guard !parsed.title.isEmpty else { toast("请输入任务内容"); return false }
        guard parsed.title.count <= 200 else { toast("任务标题最多 200 字"); return false }
        var id: String?
        change("添加任务") { id = $0.add(text, to: b, fallbackTag: tag) }
        guard let id else { return false }; asking = false; bucket = b; selected = id; queries[b] = ""; filters[b] = .all
        toast("已添加到\(b.name)"); return true
    }
    func select(_ task: NoteTask) {
        selected = task.id
        if bucket == .today && !task.done { setFocus(task.id) }
    }
    func update(_ id: String, _ action: (inout NoteTask) -> Void) { change("编辑任务") { $0.update(id, action) } }
    func editTitle(_ id: String, raw: String) -> Bool {
        guard let (b, i) = state.locate(id) else { return false }
        let parsed = ParsedTask(raw, fallbackTag: state[b][i].tag)
        guard !parsed.title.isEmpty, parsed.title.count <= 200 else { toast("标题需要 1–200 字"); return false }
        update(id) {
            $0.title = parsed.title
            if parsed.hasTag { $0.tag = parsed.tag }; if parsed.hasPriority { $0.priority = parsed.priority }
            if parsed.hasEstimate { $0.estimate = parsed.estimate }; if parsed.hasTime { $0.scheduledTime = parsed.time }
        }
        return true
    }
    func toggle(_ id: String) { change("完成状态") { $0.update(id) { $0.done.toggle() } } }
    func delete(_ id: String) { change("删除任务") { $0.delete(id) }; if selected == id { selected = nil }; toast("已删除，可撤销") }
    func clearDone() { let b = bucket; change("清除已完成") { $0[b].removeAll(where: \.done) }; if let selected, state.locate(selected) == nil { self.selected = nil }; toast("已清除已完成，可撤销") }
    func move(_ id: String, to b: Bucket) {
        change("移动任务") { $0.move(id, to: b) }; if selected == id { selected = nil }; toast("已移到\(b.name)")
    }
    func reorder(_ id: String, onto target: String) { change("调整顺序") { $0.reorder(id, onto: target) } }
    func finishDrag(at point: CGPoint) {
        defer { dragging = nil }
        guard let id = dragging else { return }
        for b in Bucket.allCases {
            if dragFrames["bucket-" + b.rawValue]?.contains(point) == true { move(id, to: b); return }
        }
        if let target = dragFrames.first(where: { $0.key.hasPrefix("task-") && $0.value.contains(point) }) {
            reorder(id, onto: String(target.key.dropFirst(5)))
        }
    }
    func shift(_ id: String, by delta: Int) {
        guard let (b, position) = state.locate(id) else { return }
        let done = state[b][position].done
        let rows = state[b].filter { $0.done == done && matches($0, query: queries[b] ?? "", filter: filters[b] ?? .all) }
        guard let index = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(index + delta) else { return }
        reorder(id, onto: rows[index + delta].id)
    }
    func setFocus(_ id: String) { change("设置聚焦", undoable: false) { $0.preferences.focusedTodoId = id } }
    func cycleFocus() {
        let pending = state.today.filter { !$0.done }; guard !pending.isEmpty else { toast("请先添加今日任务"); return }
        let i = pending.firstIndex(where: { $0.id == state.focus?.id }) ?? -1; setFocus(pending[(i + 1) % pending.count].id)
    }
    func savePlan(_ estimates: [String: Int], focus: String?, start: Bool) {
        change("今日规划") {
            for i in $0.today.indices { if let amount = estimates[$0.today[i].id] { $0.today[i].estimate = amount } }
            $0.preferences.focusedTodoId = focus
        }
        switchTo(.today); sheet = nil
        if start { setMode(25); startFocus() } else { toast("今日计划已保存") }
    }
    func saveReview(_ review: Review) { let key = currentDay; change("保存复盘") { $0.preferences.dailyReviews[key] = review }; toast("今日复盘已保存") }
    func recordSession() { let key = currentDay; change("完成专注", undoable: false) { $0.preferences.focusSessions[key, default: 0] += 1 } }
    func tick(now: Date = Date()) {
        let day = dayKey(now)
        if currentDay != day { currentDay = day; state.reconcile(date: now); save() }
        guard clock.running else { return }
        let wasRunning = clock.running
        if clock.tick(now: now) { recordSession() }
        if wasRunning && !clock.running { immersive = false; toast(clock.mode == 5 ? "休息结束，准备回来吧" : "专注完成，休息一下"); NSSound.beep() }
    }
    func setMode(_ minutes: Int) { clock.setMode(minutes); immersive = false }
    func startFocus() { clock.start(); immersive = true }
    func pauseFocus() { if clock.pause() { recordSession() }; immersive = false }
    func toggleFocus() { if clock.running { pauseFocus() } else { startFocus() } }
    func resetFocus() { clock.reset(); immersive = false }
    func exportData() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "本地工作台-\(currentDay).json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try disk.export(state, to: url); toast("已导出备份") } catch { toast("导出失败：\(error.localizedDescription)") }
    }
    func importData() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try disk.decode(Data(contentsOf: url))
            let alert = NSAlert(); alert.messageText = "用这个文件替换当前任务？"; alert.informativeText = "将导入今日 \(incoming.today.count) 条、本周 \(incoming.week.count) 条、待定 \(incoming.later.count) 条。可通过撤销恢复当前数据。"; alert.addButton(withTitle: "导入"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            change("导入数据") { $0 = incoming }; selected = nil; toast("任务已导入")
        } catch { toast("导入失败：\(error.localizedDescription)") }
    }
    func revealData() { NSWorkspace.shared.selectFile(disk.file.path, inFileViewerRootedAtPath: disk.directory.path) }
}
