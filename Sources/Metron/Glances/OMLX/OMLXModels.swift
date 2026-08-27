import Foundation

/// The slice of oMLX's `/api/status` a glance needs.
///
/// Every field is optional: oMLX is a fast-moving local server, and a widget
/// that stops reporting because one key was renamed is worse than one that
/// quietly drops a line.
struct OMLXStatus: Decodable, Equatable {
    var status: String?
    var version: String?
    var uptime_seconds: Double?
    var models_discovered: Int?
    var models_loaded: Int?
    var models_loading: Int?
    var default_model: String?
    var loaded_models: [String]?
    var total_requests: Int?
    var active_requests: Int?
    var waiting_requests: Int?
    var total_prompt_tokens: Int?
    var total_completion_tokens: Int?
    var total_cached_tokens: Int?
    var cache_efficiency: Double?
    var avg_prefill_tps: Double?
    var avg_generation_tps: Double?
    var model_memory_used: Double?
    var model_memory_max: Double?

    var memoryFraction: Double {
        guard let used = model_memory_used, let max = model_memory_max, max > 0 else { return 0 }
        return used / max
    }
    var isBusy: Bool { (active_requests ?? 0) + (waiting_requests ?? 0) > 0 }
}

/// `/admin/api/device-info` — the machine oMLX is running on.
struct OMLXDevice: Decodable, Equatable {
    var chip_name: String?
    var chip_variant: String?
    var memory_gb: Int?
    var gpu_cores: Int?

    var label: String {
        let chip = [chip_name, chip_variant].compactMap { $0 }.joined(separator: " ")
        var parts: [String] = []
        if !chip.isEmpty { parts.append(chip) }
        if let g = gpu_cores { parts.append("\(g) GPU cores") }
        if let m = memory_gb { parts.append("\(m) GB") }
        return parts.joined(separator: " · ")
    }
}

/// `/admin/api/activity` — what each resident model is doing right now.
struct OMLXActivity: Decodable, Equatable {
    struct Active: Decodable, Equatable {
        var models: [Model]?
    }
    struct Model: Decodable, Equatable, Identifiable {
        var id: String
        var actual_size: Double?
        var estimated_size: Double?
        var pinned: Bool?
        var is_loading: Bool?
        var active_requests: Int?
        var waiting_requests: Int?
        var idle_seconds: Double?
        var ttl_remaining_seconds: Double?
        var generating: [String]?
        var prefilling: [String]?

        var size: Double { (actual_size ?? 0) > 0 ? actual_size! : (estimated_size ?? 0) }
        var busy: Bool {
            (active_requests ?? 0) > 0
                || !(generating ?? []).isEmpty
                || !(prefilling ?? []).isEmpty
        }
        var state: String {
            if is_loading == true { return "loading" }
            if !(prefilling ?? []).isEmpty { return "prefilling" }
            if !(generating ?? []).isEmpty { return "generating" }
            if (waiting_requests ?? 0) > 0 { return "queued" }
            if let ttl = ttl_remaining_seconds { return "evicts in \(compactDuration(ttl))" }
            if let idle = idle_seconds, idle > 60 { return "idle \(compactDuration(idle))" }
            return "resident"
        }
    }

    var active_models: Active?
    var model_memory_used: Double?
    var model_memory_max: Double?

    var models: [Model] { active_models?.models ?? [] }
}

/// Reads the local oMLX server.
///
/// oMLX binds its admin API to localhost and does not ask for a key there, so
/// like Metron's usage readout this needs no credential of its own. It also
/// never touches `/admin/api/stats`: that endpoint returns the server's API
/// key in cleartext, and a widget has no business holding one.
enum OMLXFetcher {

    static func base() -> URL {
        let raw = UserDefaults.standard.string(forKey: "omlx.baseURL")
            ?? "http://127.0.0.1:8000"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:8000")!
    }

    static func fetch<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: base().appendingPathComponent(path))
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OMLXError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum OMLXError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "oMLX answered HTTP \(code)"
        }
    }
}
