import Foundation
import AppKit

@main struct Tests {
    static var count = 0
    static func expect(_ value: Bool, _ message: String) {
        guard value else { print("FAIL: \(message)"); exit(1) }; count += 1; print("PASS: \(message)")
    }
    static func expectThrows(_ message: String, action: () throws -> Void) {
        do { try action(); print("FAIL: \(message)"); exit(1) } catch { count += 1; print("PASS: \(message)") }
    }
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-notes-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let parsed = ParsedTask("写方案 #work !P1 ~2h @9:05")
        expect(parsed.title == "写方案" && parsed.tag == "WORK" && parsed.priority == 1 && parsed.estimate == 120 && parsed.time == "09:05", "快速语法剥离并保存全部元数据")
        let capped = ParsedTask("任务 #life !2 ~999h @23:59")
        expect(capped.estimate == 720 && capped.priority == 2 && capped.time == "23:59", "估时限制与优先级简写")
        expect(ParsedTask("#work !P1 ~30m").title.isEmpty, "仅有元数据时不创建空任务")
        expect(ParsedTask("任务 @25:88").title == "任务 @25:88", "无效计划时间保留为标题文字")
        var state = Workspace()
        let first = state.add("第一件事 #work !P1 ~30m", to: .today)!
        let second = state.add("第二件事 @14:30", to: .today)!
        expect(state.focus?.id == first, "首次添加自动选择今日聚焦")
        expect(matches(state.today[0], query: "work", filter: .priority), "标签和 P1 筛选")
        expect(matches(state.today[1], query: "14:30", filter: .timed), "时间搜索与 TIME 筛选")
        expect(!matches(state.today[1], query: "", filter: .priority), "P1 筛选排除普通任务")
        state.update(first) { $0.done = true }
        expect(state.focus?.id == second, "完成聚焦任务后自动回退")
        state.move(first, to: .week)
        expect(state.week.first?.id == first && state.week.first?.done == false && state.week.first?.estimate == 30 && state.today.count == 1, "跨列表移动保留 ID 元数据并恢复未完成")
        state.move(first, to: .today); state.reorder(first, onto: second)
        expect(state.today.map(\.id) == [first, second], "拖拽向前排序")
        state.reorder(first, onto: second)
        expect(state.today.map(\.id) == [second, first], "拖拽向后排序")
        state.delete(second); expect(state.locate(second) == nil, "删除任务")
        let date = ISO8601DateFormatter().date(from: "2026-10-04T04:00:00Z")!
        state.update(first) { $0.done = true }; state.reconcile(date: date)
        state.preferences.completionDays[dayKey(Calendar.current.date(byAdding: .day, value: -1, to: date)!)] = true
        expect(state.streak(date: date) == 2, "连续完成按当地日期统计")
        var clock = FocusClock(); let now = Date(timeIntervalSince1970: 10_000)
        clock.start(now: now); _ = clock.tick(now: now.addingTimeInterval(123)); expect(clock.remaining == 1377, "专注以实际截止时间计算，休眠后不会漂移")
        _ = clock.pause(now: now.addingTimeInterval(125)); expect(!clock.running && clock.remaining == 1375, "暂停保留剩余时间")
        clock.start(now: now.addingTimeInterval(200)); expect(clock.tick(now: now.addingTimeInterval(1575)), "完整专注记录一次")
        expect(!clock.tick(now: now.addingTimeInterval(1600)), "完成后不重复记录")
        clock.setMode(5); clock.start(now: now); expect(!clock.tick(now: now.addingTimeInterval(301)) && clock.remaining == 0, "休息结束不计入专注次数")
        clock.setMode(50); expect(clock.remaining == 3000 && !clock.running, "切换 50 分钟模式会重置计时")
        let disk = DiskStore(directory: root.appendingPathComponent("disk"))
        expect(try disk.load().0 == Workspace(), "无数据首次启动为空工作区")
        try disk.save(state)
        expect(try disk.load().0 == state, "保存和重启加载保持任务元数据")
        let previous = state; _ = state.add("新一版", to: .later); try disk.save(state)
        try Data("broken".utf8).write(to: disk.file)
        let recovered = try disk.load()
        expect(recovered.0 == previous && recovered.1 != nil, "主文件损坏从有效备份恢复并提示")
        expect(try FileManager.default.contentsOfDirectory(atPath: disk.directory.path).contains(where: { $0.hasPrefix("workbench.damaged-") }), "保留损坏原文件")
        try FileManager.default.removeItem(at: disk.file)
        expect(try disk.load().0 == previous, "主文件丢失时恢复备份")
        try Data("broken".utf8).write(to: disk.file); try Data("broken".utf8).write(to: disk.backup)
        expectThrows("两份都损坏时拒绝当作空数据覆盖") { _ = try disk.load() }
        expectThrows("超出 2 MiB 拒绝读取") { _ = try disk.decode(Data(repeating: 0, count: DiskStore.limit + 1)) }
        var invalid = previous; invalid.today.append(invalid.today[0]); expectThrows("拒绝重复任务 ID") { try invalid.validate() }
        invalid = previous; invalid.today[0].scheduledTime = "99:00"; expectThrows("拒绝非法计划时间") { try invalid.validate() }
        let source = Data("{\"today\":[{\"id\":\"old-1\",\"title\":\"旧工作台任务\",\"done\":false,\"tag\":\"WORK\",\"priority\":1,\"estimate\":25,\"scheduledTime\":\"14:00\"}],\"week\":[],\"later\":[],\"preferences\":{\"dailyReviews\":{\"2026-10-04\":{\"win\":\"完成方案\",\"next\":\"复核\"}}},\"news\":{}}".utf8)
        let imported = try disk.decode(source)
        expect(imported.today[0].id == "old-1" && imported.preferences.dailyReviews["2026-10-04"]?.win == "完成方案", "兼容原工作台 JSON 并忽略不相关内容")
        let storeRoot = root.appendingPathComponent("store")
        let store = AppStore(directory: storeRoot)
        store.showAsk()
        expect(store.asking && store.state == Workspace(), "进入随时问不修改任务数据")
        store.switchTo(.week)
        expect(!store.asking && store.bucket == .week, "返回任务分类离开网页视图")
        store.showAsk()
        expect(store.add("测试任务 #work !P1 ~25m", to: .today), "应用操作创建任务")
        expect(!store.asking && store.bucket == .today, "网页视图快速捕获后返回对应任务")
        let id = store.state.today[0].id
        _ = store.editTitle(id, raw: "更新标题")
        expect(store.state.today[0].priority == 1 && store.state.today[0].estimate == 25, "只编辑标题时保留元数据")
        store.delete(id); expect(store.state.today.isEmpty, "应用删除")
        store.undo(); expect(store.state.today.first?.id == id, "撤销删除恢复原 ID 和元数据")
        store.toggle(id); store.clearDone(); store.undo()
        expect(store.state.today.first?.done == true, "清除已完成后撤销保留完成状态")
        let another = AppStore(directory: storeRoot)
        expect(another.state == store.state, "应用操作写入后重启仍存在")
        store.savePlan([id: 45], focus: id, start: false)
        store.saveReview(Review(win: "今日亮点", next: "明日第一步"))
        expect(store.state.today.first?.estimate == 45 && store.state.preferences.dailyReviews[dayKey()]?.next == "明日第一步", "规划与每日复盘持久化")
        store.setMode(25); store.clock.start(now: now); store.tick(now: now.addingTimeInterval(1501))
        expect(store.sessions == 1, "应用完整专注写入每日次数")
        store.tick(now: now.addingTimeInterval(1502)); expect(store.sessions == 1, "应用重复 tick 不重复统计")
        store.undo(); expect(store.sessions == 1, "撤销任务操作不撤销已完成的专注记录")
        _ = store.add("用于排序的任务", to: .today)
        let dragTarget = store.state.today.last!.id
        store.dragFrames = ["task-" + dragTarget: CGRect(x: 200, y: 100, width: 100, height: 50), "bucket-week": CGRect(x: 0, y: 50, width: 100, height: 50)]
        store.dragging = id; store.finishDrag(at: CGPoint(x: 10, y: 60))
        expect(store.state.week.first?.id == id && store.state.week.first?.done == false && store.dragging == nil, "拖拽到分类命中移动操作并恢复未完成")
        store.move(id, to: .today)
        store.dragging = id; store.finishDrag(at: CGPoint(x: 220, y: 110))
        expect(store.state.today.first?.id == id, "拖拽到任务行命中排序操作")
        let unchanged = store.state; store.dragging = id; store.finishDrag(at: CGPoint(x: 900, y: 900))
        expect(store.state == unchanged && store.dragging == nil, "拖拽到空白位置不改动任务")
        let badRoot = root.appendingPathComponent("not-a-directory"); try Data("x".utf8).write(to: badRoot)
        let failedStore = AppStore(directory: badRoot); _ = failedStore.add("不可写目录", to: .today)
        expect(failedStore.saveError != nil && failedStore.state.today.count == 1, "保存失败可见且保留内存变更以供重试")
        expect(Set(AskProvider.allCases.map { $0.profileID() }).count == 3, "三个平台使用独立网页数据空间")
        expect(AskProvider.chatgpt.profileID() == AskProvider.chatgpt.profileID() && AskProvider.chatgpt.profileID(namespace: root.path) != AskProvider.chatgpt.profileID(), "登录空间跨启动稳定且测试与真实用户隔离")
        expect(AskProvider.allCases.allSatisfy { $0.home.scheme == "https" && WebPolicy.allows($0.home) }, "三个平台入口使用有效 HTTPS 官方网址")
        expect(["file:///etc/passwd", "javascript:alert(1)", "localnotes://exec", "https://user:secret@example.com"].allSatisfy { !WebPolicy.allows(URL(string: $0)!) }, "网页导航拒绝本机文件、脚本、任意协议与 URL 凭据")
        expect(WebPolicy.allows(URL(string: "about:blank")!) && WebPolicy.allows(URL(string: "blob:https://chatgpt.com/test")!), "允许登录空白窗口及网页生成附件")
        expect(WebPolicy.testOrigin("http://127.0.0.1:18765") != nil && WebPolicy.testOrigin("https://evil.example") == nil && WebPolicy.testOrigin("http://localhost") == nil, "测试网页入口仅接受显式回环端口")
        expect(WebPolicy.isNavigationCancellation(NSError(domain: "WebKitErrorDomain", code: 102)) && WebPolicy.isNavigationCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)) && !WebPolicy.isNavigationCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)), "下载导航中断不误报加载失败，真实网络错误仍报告")
        print("\n\(count) checks passed; all data isolated in a temporary directory.")
    }
}
