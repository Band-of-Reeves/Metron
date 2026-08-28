import Foundation

/// A tiny on-disk cache of the last reading a glance managed to take.
///
/// Sources go quiet — a CLI stops printing, a NAS sleeps, a server restarts.
/// When that happens the honest thing is not a blank panel; it is the last
/// number you had, labelled with its age. This keeps that number across
/// launches so a restart during an outage doesn't erase it too.
enum LastGood {

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Metron", isDirectory: true)
    }

    private static func url(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    static func save<T: Encodable>(_ value: T, as key: String) {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: url(key), options: .atomic)
        } catch {
            // A cache that cannot be written is not worth failing a refresh over.
        }
    }

    static func load<T: Decodable>(_ type: T.Type, as key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }
}
