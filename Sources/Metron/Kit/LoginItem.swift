import Foundation
import ServiceManagement

/// Wraps SMAppService so Metron can register itself as a login item.
/// Requires the app to live in /Applications (or another Launch Services
/// location) — macOS refuses to register a bundle it can't resolve.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a message worth showing the user.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Couldn't \(enabled ? "enable" : "disable") launch at login: "
                + error.localizedDescription
        }
    }
}
