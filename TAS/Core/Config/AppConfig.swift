import Foundation

/// App-wide configuration.
///
/// The base URL points at the takeaseat (TAS) web backend, which exposes the
/// data API under `/api/*` (see the `tas` repo, `server/api/`). Override it per
/// build configuration via the `TAS_API_BASE_URL` key in Info.plist, or change
/// the default below for local development (`http://localhost:3000`).
enum AppConfig {
    static let apiBaseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "TAS_API_BASE_URL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        // TODO: replace with the production takeaseat host once available.
        return URL(string: "https://takeaseat.app")!
    }()

    /// Cookie name carrying the invite code during social login — GUIDE.md §1-1.
    static let inviteCookieName = "tas-invite-code"
}
