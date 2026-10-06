import Foundation

final class DiskStore {
    static let limit = 2 * 1024 * 1024
    let directory: URL
    var file: URL { directory.appendingPathComponent("workbench.json") }
    var backup: URL { directory.appendingPathComponent("workbench.json.bak") }
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    func decode(_ data: Data) throws -> Workspace {
        guard data.count <= Self.limit else { throw DataError.tooLarge }
        let state = try decoder.decode(Workspace.self, from: data); try state.validate(); return state
    }
    func load() throws -> (Workspace, String?) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) && !fm.fileExists(atPath: backup.path) { return (Workspace(), nil) }
        if let bytes = try? Data(contentsOf: file), let state = try? decode(bytes) { return (state, nil) }
        if let bytes = try? Data(contentsOf: backup), let state = try? decode(bytes) {
            if fm.fileExists(atPath: file.path) {
                let damaged = directory.appendingPathComponent("workbench.damaged-\(UUID().uuidString).json")
                try fm.copyItem(at: file, to: damaged)
            }
            try atomicWrite(bytes, to: file)
            return (state, "主数据无法读取，已从上一版备份恢复。")
        }
        throw DataError.damaged
    }
    func save(_ state: Workspace) throws {
        try state.validate()
        let bytes = try encoder.encode(state)
        guard bytes.count <= Self.limit else { throw DataError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep only a previously verified snapshot as the recovery point.
        if let old = try? Data(contentsOf: file), (try? decode(old)) != nil { try atomicWrite(old, to: backup) }
        try atomicWrite(bytes, to: file)
    }
    private func atomicWrite(_ data: Data, to target: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: target, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    func export(_ state: Workspace, to target: URL) throws { try state.validate(); try encoder.encode(state).write(to: target, options: .atomic) }
}
