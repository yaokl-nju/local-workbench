import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let gold = Color(red: 0.72, green: 0.49, blue: 0.06)
private let paper = Color(red: 0.995, green: 0.99, blue: 0.975)
private let sidebarColor = Color(red: 0.945, green: 0.94, blue: 0.925)

struct RootView: View {
    @ObservedObject var store: AppStore
    @FocusState private var searchFocused: Bool
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Sidebar(store: store).frame(width: 174)
                Divider()
                listColumn.frame(width: 310)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(paper)
            .disabled(store.loadError != nil || store.immersive)
            if store.immersive { FocusStage(store: store) }
            if let error = store.loadError { recovery(error) }
            if let id = store.dragging, let (b, i) = store.state.locate(id) {
                Label(store.state[b][i].title, systemImage: "note.text").font(.callout)
                    .padding(12).frame(maxWidth: 220).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 8).position(x: store.dragPoint.x + 60, y: store.dragPoint.y - 25).allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "taskBoard")
        .onPreferenceChange(DragFrames.self) { store.dragFrames = $0 }
        .tint(gold).preferredColorScheme(.light)
        .sheet(item: $store.sheet) { route in
            switch route {
            case .capture: CaptureSheet(store: store)
            case .plan: PlanSheet(store: store)
            case .commands: CommandSheet(store: store)
            case .shortcuts: ShortcutSheet(store: store)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = store.saveError {
                HStack { Image(systemName: "exclamationmark.triangle.fill"); Text("保存失败：" + error).font(.caption); Spacer(); Button("重试保存") { store.save() } }.padding(10).background(Color.orange.opacity(0.16))
            } else if !store.message.isEmpty {
                HStack { Text(store.message).font(.caption); Spacer(); if store.undoLabel != nil { Button("撤销") { store.undo() }.buttonStyle(.borderless) } }.padding(.horizontal, 18).padding(.vertical, 8).background(sidebarColor)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }
    }
    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.bucket.name).font(.system(size: 21, weight: .bold))
                    Text("\(store.items.filter { !$0.done }.count) 待办 · \(store.items.filter(\.done).count) 已完成").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.sheet = .capture } label: { Image(systemName: "square.and.pencil").font(.system(size: 19)) }.buttonStyle(.borderless).help("添加任务 ⌘N").accessibilityLabel("添加任务")
            }.padding(18)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索任务或标签", text: Binding(get: { store.queries[store.bucket] ?? "" }, set: { store.queries[store.bucket] = $0 })).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("搜索当前列表")
                if !(store.queries[store.bucket] ?? "").isEmpty {
                    Button { store.queries[store.bucket] = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除搜索")
                }
            }.padding(8).background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 16)
            Picker("筛选", selection: Binding(get: { store.filters[store.bucket] ?? .all }, set: { store.filters[store.bucket] = $0 })) {
                ForEach(TaskFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.bucket == .today {
                        Button { store.selected = nil } label: {
                            HStack { Image(systemName: "rectangle.grid.1x2").foregroundStyle(gold); Text("今日概览").font(.system(size: 13, weight: .medium)); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }.padding(14).background(store.selected == nil ? gold.opacity(0.09) : Color.clear)
                        }.buttonStyle(.plain).accessibilityLabel("今日概览")
                        Divider().padding(.leading, 14)
                    }
                    let pending = store.visible.filter { !$0.done }
                    let completed = store.visible.filter(\.done)
                    if pending.isEmpty && completed.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: store.items.isEmpty ? "note.text" : "magnifyingglass").font(.system(size: 30, weight: .light)).foregroundStyle(gold.opacity(0.55))
                            Text(store.items.isEmpty ? "给\(store.bucket.name)留一件事" : "没有符合条件的任务").font(.callout).foregroundStyle(.secondary)
                            if store.items.isEmpty { Button("添加第一条任务") { store.sheet = .capture }.buttonStyle(.borderless) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 50)
                    }
                    ForEach(pending) { task in TaskRow(store: store, task: task) }
                    if !completed.isEmpty {
                        HStack {
                            Button {
                                store.collapsed[store.bucket] = !(store.collapsed[store.bucket] ?? true)
                            } label: {
                                HStack(spacing: 6) { Image(systemName: (store.collapsed[store.bucket] ?? true) ? "chevron.right" : "chevron.down"); Text("已完成 \(completed.count)") }.font(.caption).foregroundStyle(.secondary)
                            }.buttonStyle(.plain).accessibilityLabel("展开或折叠已完成")
                            Spacer()
                            Button("清除") { store.clearDone() }.buttonStyle(.borderless).font(.caption).help("清除当前列表全部已完成任务，可撤销")
                        }.padding(14)
                        if !(store.collapsed[store.bucket] ?? true) { ForEach(completed) { task in TaskRow(store: store, task: task) } }
                    }
                }
            }
            Divider()
            InlineCapture(store: store)
            HStack {
                Text("\(store.visible.count) / \(store.items.count) 条").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(store.saveError == nil ? "已在本机保存" : "尚未保存").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 9)
        }.background(Color.white)
    }
    @ViewBuilder private var detail: some View {
        if let task = store.selection {
            TaskDetail(store: store, task: task).id(task.id)
        } else {
            Overview(store: store)
        }
    }
    private func recovery(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle).foregroundStyle(gold)
            Text("暂时无法打开数据").font(.title2.bold())
            Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack { Button("查看数据文件") { store.revealData() }; Button("重新读取") { store.reload() }.buttonStyle(.borderedProminent) }
        }.padding(32).frame(width: 430).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).shadow(radius: 30)
    }
}

struct Sidebar: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) { Image(systemName: "note.text").font(.title2).foregroundStyle(gold); Text("本地便签").font(.system(size: 16, weight: .semibold)) }.padding(.horizontal, 18).padding(.top, 24)
            Text("把想法，变成今天。 ").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 8)
            Text("我的任务").font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 33).padding(.bottom, 10)
            ForEach(Bucket.allCases) { b in
                Button { store.switchTo(b) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: b.symbol).frame(width: 18).foregroundStyle(store.bucket == b ? gold : Color.secondary)
                        Text(b.name).font(.system(size: 14, weight: store.bucket == b ? .semibold : .regular))
                        Spacer()
                        Text("\(store.state[b].count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }.padding(.horizontal, 12).padding(.vertical, 11).background(store.bucket == b ? Color(red: 0.91, green: 0.85, blue: 0.69) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
                .background(GeometryReader { proxy in Color.clear.preference(key: DragFrames.self, value: ["bucket-" + b.rawValue: proxy.frame(in: .named("taskBoard"))]) })
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(store.dragging != nil && store.dragFrames["bucket-" + b.rawValue]?.contains(store.dragPoint) == true ? gold : Color.clear, lineWidth: 2).padding(.horizontal, 10))
                .accessibilityLabel("\(b.name)，\(store.state[b].count) 条任务")
            }
            Divider().padding(.horizontal, 18).padding(.vertical, 20)
            Button { store.sheet = .capture } label: { Label("快速捕获", systemImage: "plus.circle") }.buttonStyle(.plain).padding(.horizontal, 18).padding(.bottom, 17)
            Button { store.sheet = .commands } label: { Label("命令与搜索", systemImage: "command") }.buttonStyle(.plain).padding(.horizontal, 18).font(.callout)
            Spacer()
            if store.clock.running || store.clock.remaining < store.clock.mode * 60 {
                Button { if store.clock.running { store.immersive = true } else { store.startFocus() } } label: {
                    HStack { Image(systemName: "timer"); Text(store.clock.display).monospacedDigit(); Spacer(); Image(systemName: "arrow.up.right") }.font(.callout).foregroundStyle(gold)
                }.buttonStyle(.plain).padding(14).background(gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12).padding(.bottom, 12)
            }
            HStack {
                Text("仅存于这台 Mac").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("导出任务备份…") { store.exportData() }
                    Button("导入工作台 JSON…") { store.importData() }
                    Button("查看数据文件") { store.revealData() }
                    Divider()
                    Button("快捷键") { store.sheet = .shortcuts }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("数据与帮助")
            }.padding(16)
        }.frame(maxHeight: .infinity).background(sidebarColor)
    }
}

struct DragFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, latest in latest } }
}

struct TaskRow: View {
    @ObservedObject var store: AppStore
    private let initial: NoteTask
    private var task: NoteTask { guard let (b, i) = store.state.locate(initial.id) else { return initial }; return store.state[b][i] }
    init(store: AppStore, task: NoteTask) { self.store = store; initial = task }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary)
                .frame(width: 10, height: 22).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("taskBoard"))
                    .onChanged { value in store.dragging = task.id; store.dragPoint = value.location }
                    .onEnded { value in store.finishDrag(at: value.location) })
                .help("拖拽排序，或拖到左侧分类移动")
                .accessibilityLabel("拖拽任务：\(task.title)")
            Button { store.toggle(task.id) } label: { Image(systemName: task.done ? "checkmark.circle.fill" : "circle").font(.system(size: 19, weight: .light)).foregroundStyle(task.done ? gold : Color.gray.opacity(0.6)) }.buttonStyle(.plain).padding(.top, 1).accessibilityLabel(task.done ? "恢复任务：\(task.title)" : "完成任务：\(task.title)")
            Button { store.select(task) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title).font(.system(size: 14, weight: .medium)).lineLimit(3).strikethrough(task.done).foregroundStyle(task.done ? Color.secondary : Color.primary).frame(maxWidth: .infinity, alignment: .leading)
                    if !task.en.isEmpty { Text(task.en).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Text(task.metadata).font(.system(size: 10)).foregroundStyle(task.priority == 1 ? gold : Color.secondary).lineLimit(1)
                    if !task.note.isEmpty { Text(task.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("查看任务：\(task.title)")
            if store.state.preferences.focusedTodoId == task.id && !task.done { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(gold).help("今日聚焦") }
        }.padding(.horizontal, 16).padding(.vertical, 15)
        .background(store.dragging != nil && store.dragFrames["task-" + task.id]?.contains(store.dragPoint) == true ? gold.opacity(0.18) : store.selected == task.id ? gold.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 44) }
        .background(GeometryReader { proxy in Color.clear.preference(key: DragFrames.self, value: ["task-" + task.id: proxy.frame(in: .named("taskBoard"))]) })
        .contextMenu { TaskMenu(store: store, task: task) }
    }
}

struct TaskMenu: View {
    @ObservedObject var store: AppStore
    let task: NoteTask
    var body: some View {
        Button("编辑任务") { store.select(task) }
        Button(task.done ? "恢复为未完成" : "标记完成") { store.toggle(task.id) }
        if store.bucket == .today && !task.done { Button("设为今日聚焦") { store.setFocus(task.id) } }
        Menu("移动到") { ForEach(Bucket.allCases.filter { $0 != store.bucket }) { b in Button(b.name) { store.move(task.id, to: b) } } }
        Menu("优先级") { ForEach(0..<4) { value in Button(value == 0 ? "无优先级" : "P\(value)") { store.update(task.id) { $0.priority = value } } } }
        Menu("预计用时") { ForEach([0, 15, 25, 45, 60], id: \.self) { value in Button(value == 0 ? "未估时" : duration(value)) { store.update(task.id) { $0.estimate = value } } } }
        Menu("计划时间") { ForEach(["", "08:00", "09:00", "10:00", "14:00", "16:00", "18:00", "20:00"], id: \.self) { value in Button(value.isEmpty ? "清除时间" : value) { store.update(task.id) { $0.scheduledTime = value } } } }
        Button("筛选标签 \(task.tag)") { store.queries[store.bucket] = task.tag }
        Divider()
        Button("删除任务", role: .destructive) { store.delete(task.id) }
    }
}

struct InlineCapture: View {
    @ObservedObject var store: AppStore
    private var text: String { store.inlineDrafts[store.bucket] ?? "" }
    private var tag: String { store.selectedTags[store.bucket] ?? "TODO" }
    private var tags: [String] { store.bucket == .later ? ["IDEA", "READ", "TRY", "MAYBE"] : ["FOCUS", "WORK", "GROW", "BODY", "MIND"] }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("添加\(store.bucket.name)任务…", text: Binding(get: { text }, set: { store.inlineDrafts[store.bucket] = $0 })).textFieldStyle(.plain).onSubmit(add).accessibilityLabel("快速添加任务")
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(gold) }.buttonStyle(.plain).accessibilityLabel("提交任务")
            }
            HStack(spacing: 5) {
                ForEach(tags, id: \.self) { value in
                    Button(value) { store.selectedTags[store.bucket] = value }.font(.system(size: 9, weight: .medium)).buttonStyle(.plain).padding(.horizontal, 6).padding(.vertical, 4).background(tag == value ? gold.opacity(0.15) : Color.gray.opacity(0.07), in: Capsule())
                }
            }
            Text("#work   !P1   ~30m   @14:30").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(16)
    }
    private func add() { if store.add(text, to: store.bucket, tag: tag) { store.inlineDrafts[store.bucket] = "" } }
}

struct TaskDetail: View {
    @ObservedObject var store: AppStore
    private let initial: NoteTask
    private var task: NoteTask { guard let (b, i) = store.state.locate(initial.id) else { return initial }; return store.state[b][i] }
    init(store: AppStore, task: NoteTask) { self.store = store; initial = task }
    @State private var title = ""
    @State private var tag = ""
    @State private var time = ""
    @State private var note = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var tagFocused: Bool
    @FocusState private var timeFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.selected = nil } label: { Image(systemName: "chevron.left"); Text(store.bucket == .today ? "今日概览" : "\(store.bucket.name)概览") }.buttonStyle(.borderless).font(.caption)
                Spacer()
                Button { store.toggle(task.id) } label: { Image(systemName: task.done ? "checkmark.circle.fill" : "checkmark.circle") }.buttonStyle(.borderless).help(task.done ? "恢复未完成" : "完成任务").accessibilityLabel("切换当前任务完成状态")
                Menu { TaskMenu(store: store, task: task) } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("任务操作")
            }.padding(.horizontal, 28).padding(.vertical, 18)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    TextField("任务标题", text: $title, axis: .vertical).textFieldStyle(.plain).font(.system(size: 27, weight: .bold)).focused($titleFocused).onSubmit(commitTitle).accessibilityLabel("编辑任务标题")
                    if !task.en.isEmpty { Text(task.en).font(.callout).foregroundStyle(.secondary) }
                    HStack {
                        Label(task.done ? "已完成" : "未完成", systemImage: task.done ? "checkmark.circle.fill" : "circle").foregroundStyle(task.done ? gold : Color.secondary)
                        Spacer()
                        if store.bucket == .today && !task.done {
                            Button { store.setFocus(task.id) } label: { Label(store.state.preferences.focusedTodoId == task.id ? "今日聚焦" : "设为聚焦", systemImage: "pin") }.buttonStyle(.borderless)
                        }
                    }.font(.caption)
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        metadataRow("标签", symbol: "number") {
                            TextField("TODO", text: $tag).textFieldStyle(.roundedBorder).focused($tagFocused).onSubmit(commitTag).accessibilityLabel("任务标签")
                        }
                        metadataRow("优先级", symbol: "flag") {
                            Picker("优先级", selection: Binding(get: { task.priority }, set: { value in store.update(task.id) { $0.priority = value } })) {
                                Text("普通").tag(0); Text("P1 · 高").tag(1); Text("P2 · 中").tag(2); Text("P3 · 低").tag(3)
                            }.labelsHidden().accessibilityLabel("任务优先级")
                        }
                        metadataRow("预计用时", symbol: "hourglass") {
                            HStack {
                                TextField("分钟", value: Binding(get: { task.estimate }, set: { value in store.update(task.id) { $0.estimate = min(720, max(0, value)) } }), format: .number).textFieldStyle(.roundedBorder).accessibilityLabel("预计用时分钟")
                                Text("分钟").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        metadataRow("计划时间", symbol: "clock") {
                            TextField("HH:mm", text: $time).textFieldStyle(.roundedBorder).focused($timeFocused).onSubmit(commitTime).accessibilityLabel("计划时间")
                        }
                        metadataRow("所在列表", symbol: "folder") {
                            Picker("所在列表", selection: Binding(get: { store.bucket }, set: { store.move(task.id, to: $0) })) { ForEach(Bucket.allCases) { Text($0.name).tag($0) } }.labelsHidden()
                        }
                    }
                    Divider()
                    Text("补充笔记").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextEditor(text: $note).font(.system(size: 15)).scrollContentBackground(.hidden).frame(minHeight: 200).accessibilityLabel("任务补充笔记")
                    HStack {
                        Text("标题支持快速语法；回车或离开编辑框后保存。").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                    }
                }.padding(28)
            }
        }.background(paper)
        .onAppear { title = task.title; tag = task.tag; time = task.scheduledTime; note = task.note }
        .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
        .onChange(of: tagFocused) { _, focused in if !focused { commitTag() } }
        .onChange(of: timeFocused) { _, focused in if !focused { commitTime() } }
        .onChange(of: note) { _, value in if value != task.note { store.update(task.id) { $0.note = String(value.prefix(100_000)) } } }
        .onChange(of: task.title) { _, value in if !titleFocused { title = value } }
        .onChange(of: task.tag) { _, value in tag = value }
        .onChange(of: task.scheduledTime) { _, value in time = value }
        .onChange(of: task.note) { _, value in if note != value { note = value } }
        .onDisappear { commitTitle(); commitTag(); commitTime() }
    }
    private func metadataRow<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary).frame(width: 94, alignment: .leading); content().frame(maxWidth: .infinity) }
    }
    private func commitTitle() {
        if title != task.title && !title.isEmpty {
            _ = store.editTitle(task.id, raw: title)
            title = task.title
        }
    }
    private func commitTag() {
        let value = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)).uppercased()
        if !value.isEmpty && value != task.tag { store.update(task.id) { $0.tag = value } }; tag = value.isEmpty ? task.tag : value
    }
    private func commitTime() {
        if validTime(time) { if time != task.scheduledTime { store.update(task.id) { $0.scheduledTime = time } } }
        else { store.toast("时间格式为 HH:mm，例如 14:30"); time = task.scheduledTime }
    }
}

struct Overview: View {
    @ObservedObject var store: AppStore
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide))).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.sheet = .shortcuts } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.borderless).accessibilityLabel("快捷键帮助")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.bucket == .today ? "今天，专心一点。" : store.bucket == .week ? "为这一周留些空间。" : "好想法，不必急着开始。").font(.system(size: 29, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text(store.bucket.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                StatsCard(store: store)
                if store.bucket == .today {
                    focusCard
                    TimerCard(store: store)
                    HStack {
                        Label("今日规划", systemImage: "list.bullet.clipboard").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("安排一下") { store.sheet = .plan }.buttonStyle(.borderless)
                    }.padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    completionHistory
                    ReviewCard(store: store).id("review")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: store.bucket.symbol).font(.system(size: 33, weight: .light)).foregroundStyle(gold.opacity(0.7))
                        Text(store.bucket == .week ? "从计划，到行动。" : "给灵感一个收件箱。").font(.title3.weight(.semibold))
                        Text(store.bucket == .week ? "选择一条任务，补充估时和优先级。准备好开始时，将它移到今日。" : "暂时没有安排的事项都放在这里。准备好了，再移到本周或今日。").font(.callout).foregroundStyle(.secondary).lineSpacing(5)
                        Button("添加\(store.bucket.name)任务") { store.sheet = .capture }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                }
                Text("⌘N 快速捕获    ⌘K 全局搜索    ⌘1 / 2 / 3 切换列表").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(30).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(paper)
        .onReceive(NotificationCenter.default.publisher(for: .showReview)) { _ in withAnimation { proxy.scrollTo("review", anchor: .bottom) } }
        }
    }
    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Label("今日聚焦", systemImage: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(gold); Spacer(); Button("换一件") { store.cycleFocus() }.buttonStyle(.borderless).font(.caption) }
            Text(store.state.focus?.title ?? "先选今天最重要的一件事").font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(store.state.focus?.metadata ?? "添加任务后，在列表中选择或进入今日规划").font(.caption).foregroundStyle(.secondary)
            if let focus = store.state.focus { HStack { Button("查看任务") { store.selected = focus.id }.buttonStyle(.borderless); Spacer(); Button("完成这件事") { store.toggle(focus.id) }.buttonStyle(.borderless) }.font(.caption) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(gold.opacity(0.075), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.13)))
    }
    private var completionHistory: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text("连续完成 \(store.state.streak()) 天").font(.caption.weight(.medium)); Text("完成当天全部任务后点亮").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            HStack(spacing: 6) {
                ForEach((0..<7).reversed(), id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
                    Circle().fill(store.state.preferences.completionDays[dayKey(date)] == true ? gold : Color.gray.opacity(0.16)).frame(width: 10, height: 10).help(dayKey(date))
                }
            }
        }
    }
}

struct StatsCard: View {
    @ObservedObject var store: AppStore
    var body: some View {
        let tasks = store.items
        let done = tasks.filter(\.done).count
        let pending = tasks.count - done
        let load = tasks.filter { !$0.done }.reduce(0) { $0 + $1.estimate }
        let rate = tasks.isEmpty ? 0 : Int((Double(done) / Double(tasks.count) * 100).rounded())
        VStack(spacing: 15) {
            HStack(spacing: 0) {
                stat("\(done) / \(tasks.count)", "完成任务")
                Divider().frame(height: 30)
                stat("\(pending)", "待处理")
                Divider().frame(height: 30)
                stat(store.bucket == .later ? "\(Set(tasks.map(\.tag)).count)" : "\(rate)%", store.bucket == .later ? "标签分类" : "完成率")
            }
            ProgressView(value: Double(done), total: Double(max(1, tasks.count))).progressViewStyle(.linear).tint(gold).frame(height: 6).accessibilityLabel("完成进度")
            HStack { Text("剩余估时 \(load > 0 ? duration(load) : pending > 0 ? "未估时" : "0m")"); Spacer(); if store.bucket == .today { Text("今日专注 \(store.sessions) 次") } }.font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }
    private func stat(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 21, weight: .semibold)).monospacedDigit(); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 9) }
}

struct TimerCard: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("留一段专注时间", systemImage: "timer").font(.caption.weight(.semibold))
                Spacer()
                Picker("计时模式", selection: Binding(get: { store.clock.mode }, set: { store.setMode($0) })) { Text("25m").tag(25); Text("50m").tag(50); Text("休息 5m").tag(5) }.labelsHidden().pickerStyle(.segmented).frame(width: 185)
            }
            HStack {
                Text(store.clock.display).font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit().accessibilityLabel("剩余时间 \(store.clock.display)")
                Spacer()
                Button { store.resetFocus() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.borderless).help("重置计时").accessibilityLabel("重置计时")
                Button(store.clock.running ? "暂停" : store.clock.remaining < store.clock.mode * 60 && store.clock.remaining > 0 ? "继续" : "开始") { store.toggleFocus() }.buttonStyle(.borderedProminent)
            }
            Text(store.clock.mode == 5 ? "起身走动，给注意力一点休息。" : "专注结束后自动记录次数；任务由你勾选完成。").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ReviewCard: View {
    @ObservedObject var store: AppStore
    @State private var win = ""
    @State private var next = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Label("收工复盘", systemImage: "pencil.line").font(.caption.weight(.semibold)); Spacer(); if store.state.preferences.dailyReviews[store.currentDay] != nil { Image(systemName: "checkmark.circle").foregroundStyle(gold) } }
            TextField("今日亮点 · 今天做成了什么？", text: $win).textFieldStyle(.roundedBorder).accessibilityLabel("今日亮点")
            TextField("明日第一步 · 明天从哪里开始？", text: $next).textFieldStyle(.roundedBorder).accessibilityLabel("明日第一步")
            HStack { Text(store.currentDay).font(.caption2).foregroundStyle(.secondary); Spacer(); Button("保存复盘") { store.saveReview(Review(win: win.trimmingCharacters(in: .whitespacesAndNewlines), next: next.trimmingCharacters(in: .whitespacesAndNewlines))) }.buttonStyle(.borderless) }
        }.padding(18).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .onAppear(perform: load)
        .onChange(of: store.currentDay) { _, _ in load() }
        .onChange(of: store.state.preferences.dailyReviews) { _, _ in load() }
    }
    private func load() { let review = store.state.preferences.dailyReviews[store.currentDay] ?? Review(); win = review.win; next = review.next }
}

struct FocusStage: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing: 28) {
            HStack { Label(store.clock.mode == 5 ? "休息中" : "专注中", systemImage: "circle.dotted").font(.caption).foregroundStyle(gold); Spacer(); Button("返回任务列表") { store.immersive = false }.buttonStyle(.borderless).help("计时将继续") }.padding(28)
            Spacer()
            Image(systemName: store.clock.mode == 5 ? "cup.and.saucer" : "leaf").font(.system(size: 35, weight: .light)).foregroundStyle(gold)
            Text(store.clock.mode == 5 ? "先停一下。" : "此刻，只做这一件事。").font(.system(size: 30, weight: .semibold))
            Text(store.clock.mode == 5 ? "起身走动、喝口水，暂时离开屏幕。" : store.state.focus?.title ?? "留一段时间，给正在做的事。 ").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 80)
            Text(store.clock.display).font(.system(size: 94, weight: .ultraLight, design: .rounded)).monospacedDigit().accessibilityLabel("专注剩余时间 \(store.clock.display)")
            ProgressView(value: Double(store.clock.mode * 60 - store.clock.remaining), total: Double(store.clock.mode * 60)).frame(width: 300).tint(gold)
            HStack(spacing: 16) { Button("重置") { store.resetFocus() }.buttonStyle(.bordered); Button("暂停专注") { store.pauseFocus() }.buttonStyle(.borderedProminent) }
            Text("今日已完成 \(store.sessions) 次专注 · Esc 暂停").font(.caption).foregroundStyle(.secondary)
            Spacer(); Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(paper)
    }
}

struct CaptureSheet: View {
    @ObservedObject var store: AppStore
    @State private var text = ""
    @State private var bucket: Bucket = .today
    @FocusState private var focused: Bool
    private var parsed: ParsedTask { ParsedTask(text, fallbackTag: store.selectedTags[bucket] ?? "TODO") }
    private var previewMetadata: String {
        let value = parsed
        var parts = ["#" + value.tag]
        if value.priority > 0 { parts.append("P\(value.priority)") }
        if value.estimate > 0 { parts.append(duration(value.estimate)) }
        if !value.time.isEmpty { parts.append(value.time) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            sheetHeading("快速捕获", subtitle: "先记下来，让想法有个落脚点。")
            Picker("添加到", selection: $bucket) { ForEach(Bucket.allCases) { Text($0.name).tag($0) } }.pickerStyle(.segmented)
            TextField("想做些什么？", text: $text, axis: .vertical).font(.title3).textFieldStyle(.roundedBorder).focused($focused).onSubmit(add).accessibilityLabel("新任务内容")
            VStack(alignment: .leading, spacing: 8) {
                Text("解析为 · \(bucket.name)").font(.caption2).foregroundStyle(.secondary)
                Text(parsed.title.isEmpty ? "等待输入任务内容" : parsed.title).font(.callout).lineLimit(2)
                Text(previewMetadata).font(.caption).foregroundStyle(gold)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("解析为\(bucket.name)：\(parsed.title)，\(previewMetadata)")
            VStack(alignment: .leading, spacing: 7) { Text("写方案 #work !P1 ~30m @14:30").font(.callout); Text("标签 · 优先级 · 预计用时 · 计划时间").font(.caption).foregroundStyle(.secondary) }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            HStack { Button("取消") { store.sheet = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("添加任务", action: add).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 470).background(paper).onAppear { bucket = store.bucket; focused = true }
    }
    private func add() { if store.add(text, to: bucket, tag: store.selectedTags[bucket] ?? "TODO") { store.sheet = nil } }
}

struct PlanSheet: View {
    @ObservedObject var store: AppStore
    @State private var estimates: [String: Int] = [:]
    @State private var focus: String?
    private var pending: [NoteTask] { store.state.today.filter { !$0.done } }
    private var load: Int { estimates.values.reduce(0, +) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeading("给今天一个计划", subtitle: "选一件最重要的事，再为其他任务留出时间。")
            HStack { Text("\(pending.count) 件事 · \(duration(load)) · \(estimates.values.filter { $0 == 0 }.count) 件未估时"); Spacer(); if load > 480 { Label("超过 8 小时", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }.font(.caption)
            Divider()
            if pending.isEmpty { Text("今天还没有任务，先捕获一件事吧。").foregroundStyle(.secondary).padding(.vertical, 30) }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(pending) { task in
                        HStack(spacing: 12) {
                            Button { focus = task.id } label: { Image(systemName: focus == task.id ? "largecircle.fill.circle" : "circle").foregroundStyle(gold).font(.title3) }.buttonStyle(.plain).accessibilityLabel("规划焦点：\(task.title)")
                            VStack(alignment: .leading, spacing: 5) { Text(task.title).font(.callout.weight(.medium)); Text(task.metadata).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                            Picker("估时", selection: Binding(get: { estimates[task.id] ?? 0 }, set: { estimates[task.id] = $0 })) {
                                ForEach(Array(Set([0, 15, 25, 30, 45, 60, 90, 120, task.estimate])).sorted(), id: \.self) { amount in Text(amount == 0 ? "未估时" : duration(amount)).tag(amount) }
                            }.labelsHidden().frame(width: 100).accessibilityLabel("规划估时：\(task.title)")
                        }.padding(.vertical, 15)
                        Divider()
                    }
                }
            }.frame(maxHeight: 300)
            HStack {
                Button("取消") { store.sheet = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(pending.isEmpty ? "去快速捕获" : "仅保存计划") { if pending.isEmpty { store.sheet = .capture } else { store.savePlan(estimates, focus: focus, start: false) } }
                Button("保存并专注") { store.savePlan(estimates, focus: focus, start: true) }.buttonStyle(.borderedProminent).disabled(pending.isEmpty)
            }
        }.padding(28).frame(width: 570).background(paper).onAppear { focus = store.state.focus?.id; estimates = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0.estimate) }) }
    }
}

struct CommandSheet: View {
    @ObservedObject var store: AppStore
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool
    struct Entry: Identifiable { var id: String; var title: String; var subtitle: String; var symbol: String; var run: () -> Void }
    private var entries: [Entry] {
        var commands = Bucket.allCases.map { b in Entry(id: b.rawValue, title: "前往\(b.name)", subtitle: "切换列表", symbol: b.symbol, run: { store.switchTo(b) }) }
        commands += [
            Entry(id: "capture", title: "快速捕获", subtitle: "记录一件新任务", symbol: "square.and.pencil", run: { store.sheet = .capture }),
            Entry(id: "plan", title: "今日规划", subtitle: "安排焦点和预计用时", symbol: "list.bullet.clipboard", run: { store.sheet = .plan }),
            Entry(id: "focus", title: store.clock.running ? "暂停专注" : "开始专注", subtitle: "番茄计时器", symbol: "timer", run: { store.toggleFocus() }),
            Entry(id: "undo", title: "撤销", subtitle: store.undoLabel ?? "没有可撤销的操作", symbol: "arrow.uturn.backward", run: { store.undo() }),
            Entry(id: "review", title: "收工复盘", subtitle: "记录今日亮点和明日第一步", symbol: "pencil.line", run: { store.switchTo(.today); NotificationCenter.default.post(name: .showReview, object: nil) })
        ]
        commands = commands.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
        for b in Bucket.allCases {
            for task in store.state[b] where query.isEmpty || matches(task, query: query, filter: .all) {
                commands.append(Entry(id: task.id, title: task.title, subtitle: "\(b.name) · \(task.metadata)\(task.done ? " · 已完成" : "")", symbol: task.done ? "checkmark.circle" : "circle", run: { store.switchTo(b); store.selected = task.id; if task.done { store.collapsed[b] = false } }))
            }
        }
        return Array(commands.prefix(60))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(gold); TextField("输入命令，或搜索所有任务…", text: $query).textFieldStyle(.plain).font(.title3).focused($focused).onSubmit(runSelected).accessibilityLabel("全局命令搜索") }.padding(22)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Button { run(entry) } label: {
                                HStack(spacing: 12) { Image(systemName: entry.symbol).foregroundStyle(gold).frame(width: 22); VStack(alignment: .leading, spacing: 4) { Text(entry.title).font(.callout); Text(entry.subtitle).font(.caption2).foregroundStyle(.secondary) }; Spacer(); if index == selectedIndex { Image(systemName: "return").foregroundStyle(.secondary).font(.caption) } }.padding(13).contentShape(Rectangle()).background(index == selectedIndex ? gold.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).id(entry.id)
                        }
                        if entries.isEmpty { Text("没有找到命令或任务").foregroundStyle(.secondary).padding(40) }
                    }.padding(8)
                }.frame(height: 350)
                .onChange(of: selectedIndex) { _, i in if entries.indices.contains(i) { proxy.scrollTo(entries[i].id) } }
            }
            Divider()
            HStack { Text("↑ ↓ 选择 · 回车执行 · Esc 关闭").font(.caption2).foregroundStyle(.secondary); Spacer(); Button("关闭") { store.sheet = nil }.keyboardShortcut(.cancelAction) }.padding(15)
        }.frame(width: 550).background(paper).onAppear { focused = true }.onChange(of: query) { _, _ in selectedIndex = 0 }
        .onMoveCommand { direction in if direction == .down { selectedIndex = min(max(0, entries.count - 1), selectedIndex + 1) } else if direction == .up { selectedIndex = max(0, selectedIndex - 1) } }
        .onReceive(NotificationCenter.default.publisher(for: .commandMove)) { note in
            guard let delta = note.object as? Int else { return }
            selectedIndex = min(max(0, entries.count - 1), max(0, selectedIndex + delta))
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandExecute)) { _ in runSelected() }
    }
    private func runSelected() { guard entries.indices.contains(selectedIndex) else { return }; run(entries[selectedIndex]) }
    private func run(_ entry: Entry) { store.sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { entry.run() } }
}

struct ShortcutSheet: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeading("随手可用的快捷键", subtitle: "沿用工作台习惯，也适配 Mac 的常用操作。")
            ForEach([("⌘1 / ⌘2 / ⌘3", "今日 / 本周 / 待定"), ("⌘N 或 N", "快速捕获"), ("⌘K", "命令面板与全局搜索"), ("⌘F 或 /", "搜索当前列表"), ("⌘Z", "撤销最近的任务操作"), ("P", "开始 / 暂停专注"), ("⌘⌥↑ / ⌘⌥↓", "上移 / 下移选中任务"), ("Esc", "关闭弹窗 / 暂停沉浸专注"), ("?", "查看快捷键")], id: \.0) { key, action in
                HStack { Text(action).font(.callout); Spacer(); Text(key).font(.system(size: 12, design: .monospaced)).foregroundStyle(gold) }
            }
            Text("单键快捷键只在未编辑文字时生效。拖动任务可排序，拖到左侧分类可跨列表移动。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("知道了") { store.sheet = nil }.buttonStyle(.borderedProminent).keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 510).background(paper)
    }
}

private func sheetHeading(_ title: String, subtitle: String) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 23, weight: .bold)); Text(subtitle).font(.callout).foregroundStyle(.secondary) } }
extension Notification.Name {
    static let focusSearch = Notification.Name("LocalNotes.focusSearch")
    static let showReview = Notification.Name("LocalNotes.showReview")
    static let commandMove = Notification.Name("LocalNotes.commandMove")
    static let commandExecute = Notification.Name("LocalNotes.commandExecute")
}
