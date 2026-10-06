import Foundation

enum Bucket: String, Codable, CaseIterable, Identifiable {
    case today, week, later
    var id: String { rawValue }
    var name: String { switch self { case .today: return "今日"; case .week: return "本周"; case .later: return "待定" } }
    var symbol: String { switch self { case .today: return "sun.max"; case .week: return "calendar"; case .later: return "tray" } }
    var subtitle: String { switch self { case .today: return "留给今天最重要的事"; case .week: return "让一周的计划慢慢成形"; case .later: return "先收下，等一个合适的时机" } }
}

struct NoteTask: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var done = false
    var tag = "TODO"
    var priority = 0
    var estimate = 0
    var scheduledTime = ""
    var en = ""
    var note = ""
    var createdAt = Date()
    var updatedAt = Date()

    enum CodingKeys: String, CodingKey { case id, title, done, tag, priority, estimate, scheduledTime, en, note, createdAt, updatedAt }
    init(title: String) { self.title = title }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? "TODO"
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        estimate = try c.decodeIfPresent(Int.self, forKey: .estimate) ?? 0
        scheduledTime = try c.decodeIfPresent(String.self, forKey: .scheduledTime) ?? ""
        en = try c.decodeIfPresent(String.self, forKey: .en) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
    var metadata: String {
        ([tag] + (priority > 0 ? ["P\(priority)"] : []) + (estimate > 0 ? [duration(estimate)] : []) + (scheduledTime.isEmpty ? [] : [scheduledTime])).joined(separator: " · ")
    }
}

struct Review: Codable, Equatable { var win = ""; var next = "" }
struct Preferences: Codable, Equatable {
    var focusedTodoId: String?
    var dailyReviews: [String: Review] = [:]
    var focusSessions: [String: Int] = [:]
    var completionDays: [String: Bool] = [:]
    enum CodingKeys: String, CodingKey { case focusedTodoId, dailyReviews, focusSessions, completionDays }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusedTodoId = try c.decodeIfPresent(String.self, forKey: .focusedTodoId)
        dailyReviews = try c.decodeIfPresent([String: Review].self, forKey: .dailyReviews) ?? [:]
        focusSessions = try c.decodeIfPresent([String: Int].self, forKey: .focusSessions) ?? [:]
        completionDays = try c.decodeIfPresent([String: Bool].self, forKey: .completionDays) ?? [:]
    }
}

struct Workspace: Codable, Equatable {
    var version = 1
    var today: [NoteTask] = []
    var week: [NoteTask] = []
    var later: [NoteTask] = []
    var preferences = Preferences()
    enum CodingKeys: String, CodingKey { case version, today, week, later, preferences }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        today = try c.decodeIfPresent([NoteTask].self, forKey: .today) ?? []
        week = try c.decodeIfPresent([NoteTask].self, forKey: .week) ?? []
        later = try c.decodeIfPresent([NoteTask].self, forKey: .later) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }
    subscript(bucket: Bucket) -> [NoteTask] {
        get { switch bucket { case .today: return today; case .week: return week; case .later: return later } }
        set { switch bucket { case .today: today = newValue; case .week: week = newValue; case .later: later = newValue } }
    }
    func locate(_ id: String) -> (Bucket, Int)? {
        for b in Bucket.allCases { if let i = self[b].firstIndex(where: { $0.id == id }) { return (b, i) } }
        return nil
    }
    var focus: NoteTask? { today.first(where: { !$0.done && $0.id == preferences.focusedTodoId }) ?? today.first(where: { !$0.done }) }
    mutating func reconcile(date: Date = Date()) {
        preferences.focusedTodoId = focus?.id
        if !today.isEmpty && today.allSatisfy(\.done) { preferences.completionDays[dayKey(date)] = true }
    }
    mutating func add(_ raw: String, to bucket: Bucket, fallbackTag: String = "TODO") -> String? {
        let p = ParsedTask(raw, fallbackTag: fallbackTag)
        guard !p.title.isEmpty else { return nil }
        var task = NoteTask(title: p.title)
        task.tag = p.tag; task.priority = p.priority; task.estimate = p.estimate; task.scheduledTime = p.time
        self[bucket].append(task); reconcile()
        return task.id
    }
    mutating func update(_ id: String, _ change: (inout NoteTask) -> Void) {
        guard let (b, i) = locate(id) else { return }
        change(&self[b][i]); self[b][i].updatedAt = Date(); reconcile()
    }
    mutating func move(_ id: String, to target: Bucket) {
        guard let (b, i) = locate(id), b != target else { return }
        var task = self[b].remove(at: i); task.done = false; task.updatedAt = Date()
        self[target].append(task); reconcile()
    }
    mutating func reorder(_ id: String, onto target: String) {
        guard let (b, from) = locate(id), let (other, to) = locate(target), b == other, from != to else { return }
        let task = self[b].remove(at: from); self[b].insert(task, at: to)
    }
    mutating func delete(_ id: String) {
        guard let (b, i) = locate(id) else { return }; self[b].remove(at: i); reconcile()
    }
    func streak(date: Date = Date()) -> Int {
        var day = date; var n = 0
        while preferences.completionDays[dayKey(day)] == true {
            n += 1; guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }; day = previous
        }
        return n
    }
    func validate() throws {
        guard version == 1 else { throw DataError.invalid("不支持的数据版本") }
        var ids = Set<String>()
        for b in Bucket.allCases {
            for t in self[b] {
                guard !t.id.isEmpty, ids.insert(t.id).inserted, !t.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      t.title.count <= 200, t.note.count <= 100_000, (0...3).contains(t.priority), (0...720).contains(t.estimate),
                      !t.tag.isEmpty, t.tag.count <= 32, validTime(t.scheduledTime) else { throw DataError.invalid("任务数据不完整或超出范围") }
            }
        }
        guard preferences.focusSessions.values.allSatisfy({ $0 >= 0 }) else { throw DataError.invalid("专注次数无效") }
    }
}

enum TaskFilter: String, CaseIterable { case all = "全部", priority = "P1", timed = "TIME" }
func matches(_ task: NoteTask, query: String, filter: TaskFilter) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let found = q.isEmpty || [task.title, task.en, task.tag, task.scheduledTime, task.note].contains { $0.localizedCaseInsensitiveContains(q) }
    return found && (filter == .all || filter == .priority && task.priority == 1 || filter == .timed && (task.estimate > 0 || !task.scheduledTime.isEmpty))
}
func dayKey(_ date: Date = Date()) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}
func duration(_ minutes: Int) -> String { minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : "\(minutes % 60)m") }
func validTime(_ value: String) -> Bool { value.isEmpty || value.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil }

struct ParsedTask {
    var title: String; var tag: String; var priority = 0; var estimate = 0; var time = ""
    var hasTag = false; var hasPriority = false; var hasEstimate = false; var hasTime = false
    init(_ raw: String, fallbackTag: String = "TODO") {
        title = raw; tag = fallbackTag
        func consume(_ pattern: String, _ visit: (NSTextCheckingResult, NSString) -> Void) {
            let text = title as NSString
            let regex = try! NSRegularExpression(pattern: pattern)
            let found = regex.matches(in: title, range: NSRange(location: 0, length: text.length))
            found.forEach { visit($0, text) }
            let result = NSMutableString(string: title)
            for match in found.reversed() { result.replaceCharacters(in: match.range, with: text.substring(with: match.range(at: 1))) }
            title = result as String
        }
        consume("(?i)(^|\\s)#([a-z][a-z0-9_-]{0,15})\\b") { m, s in tag = s.substring(with: m.range(at: 2)).uppercased(); hasTag = true }
        consume("(?i)(^|\\s)!p?([123])\\b") { m, s in priority = Int(s.substring(with: m.range(at: 2)))!; hasPriority = true }
        consume("(?i)(^|\\s)~([0-9]{1,3})(m|h)?\\b") { m, s in
            let unit = m.range(at: 3).location == NSNotFound ? "" : s.substring(with: m.range(at: 3)).lowercased()
            estimate = min(720, Int(s.substring(with: m.range(at: 2)))! * (unit == "h" ? 60 : 1)); hasEstimate = true
        }
        consume("(^|\\s)@([01]?[0-9]|2[0-3]):([0-5][0-9])\\b") { m, s in
            time = String(format: "%02d", Int(s.substring(with: m.range(at: 2)))!) + ":" + s.substring(with: m.range(at: 3)); hasTime = true
        }
        title = title.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct FocusClock {
    var mode = 25
    var remaining = 1500
    var deadline: Date?
    var recorded = false
    var running: Bool { deadline != nil }
    mutating func setMode(_ minutes: Int) { mode = minutes; reset() }
    mutating func reset() { deadline = nil; remaining = mode * 60; recorded = false }
    mutating func start(now: Date = Date()) { guard !running else { return }; if remaining == 0 { reset() }; deadline = now.addingTimeInterval(Double(remaining)) }
    mutating func pause(now: Date = Date()) -> Bool { let completed = tick(now: now); deadline = nil; return completed }
    mutating func tick(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        remaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        guard remaining == 0 else { return false }
        self.deadline = nil
        guard !recorded else { return false }; recorded = true
        return mode != 5
    }
    var display: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
}

enum DataError: LocalizedError {
    case invalid(String), tooLarge, damaged
    var errorDescription: String? { switch self { case .invalid(let text): return text; case .tooLarge: return "数据超过 2 MiB，请减少笔记内容后重试"; case .damaged: return "数据和备份都无法读取。原文件已保留，请恢复有效 JSON 后重试。" } }
}
