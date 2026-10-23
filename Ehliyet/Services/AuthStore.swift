import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    private(set) var user: APIUser?
    private(set) var isLoading = false
    var showLogin = false

    var isSignedIn: Bool { user != nil }
    var entitlements: APIEntitlements { user?.entitlements ?? .none }

    private let api = APIClient.shared

    /// Uygulama açılışında kayıtlı oturumu yükler
    func restore() async {
        guard await api.isSignedIn else { return }
        do {
            user = try await api.send("GET", "/v1/auth/me")
        } catch {
            // Ağ yoksa oturumu silme; yalnızca sunucu reddettiyse çık
            if error is APIError { await api.clear() }
        }
    }

    func login(email: String, password: String) async throws {
        try await authenticate("/v1/auth/login", body: ["email": email, "password": password])
    }

    func register(email: String, password: String, name: String?) async throws {
        var body = ["email": email, "password": password]
        if let name, !name.isEmpty { body["name"] = name }
        try await authenticate("/v1/auth/register", body: body)
    }

    func signInWithApple(identityToken: String, name: String?) async throws {
        var body = ["identityToken": identityToken]
        if let name, !name.isEmpty { body["name"] = name }
        try await authenticate("/v1/auth/apple", body: body)
    }

    func logout() async {
        if let refresh = await api.refreshToken() {
            try? await api.send("POST", "/v1/auth/logout", body: ["refreshToken": refresh], auth: false)
        }
        await api.clear()
        user = nil
    }

    func deleteAccount() async throws {
        try await api.send("DELETE", "/v1/auth/me")
        await api.clear()
        user = nil
    }

    func update(_ entitlements: APIEntitlements) {
        guard let u = user else { return }
        user = APIUser(id: u.id, email: u.email, name: u.name, entitlements: entitlements)
    }

    private func authenticate(_ path: String, body: [String: String]) async throws {
        isLoading = true
        defer { isLoading = false }
        let session: AuthSession = try await api.send("POST", path, body: body, auth: false)
        await api.store(session)
        user = session.user
        showLogin = false
    }
}
