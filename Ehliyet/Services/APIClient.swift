import Foundation
import Security

// MARK: - Modeller (sunucu yanıtları)

struct APIUser: Codable, Equatable {
    let id: UUID
    let email: String?
    let name: String?
    let entitlements: APIEntitlements
}

struct APIEntitlements: Codable, Equatable {
    struct Active: Codable, Equatable {
        let productId: String
        let expiresAt: Date?
        let environment: String
    }
    let isPremium: Bool
    let scopes: [String]
    let active: [Active]

    static let none = APIEntitlements(isPremium: false, scopes: [], active: [])
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let user: APIUser?
}

struct APIError: LocalizedError, Decodable {
    let error: String
    let message: String?
    var errorDescription: String? { message ?? "Bir hata oluştu (\(error))" }
}

// MARK: - İstemci

/// Sunucuyla konuşan tek nokta. 401 alınca refresh token ile bir kez yenileyip tekrar dener.
actor APIClient {
    static let shared = APIClient()

    #if DEBUG
    // Simülatör, Mac'teki sunucuya localhost ile ulaşır
    let baseURL = URL(string: "http://localhost:3000")!
    #else
    let baseURL = URL(string: "https://ehliyet-api.melihcaliskan.com")!
    #endif

    private let keychain = Keychain(service: "com.melihcaliskan.ehliyet.auth")
    private var refreshTask: Task<Void, Error>?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Tarih okunamadı: \(s)"))
        }
        return d
    }()

    var isSignedIn: Bool { keychain.get("refresh") != nil }

    func store(_ session: AuthSession) {
        keychain.set(session.accessToken, for: "access")
        keychain.set(session.refreshToken, for: "refresh")
    }

    func clear() {
        keychain.delete("access")
        keychain.delete("refresh")
    }

    func refreshToken() -> String? { keychain.get("refresh") }

    // MARK: İstek

    func send<T: Decodable>(_ method: String, _ path: String, query: [String: String?] = [:], body: (any Encodable)? = nil, auth: Bool = true, as: T.Type = T.self) async throws -> T {
        let data = try await raw(method, path, query: query, body: body, auth: auth)
        return try decoder.decode(T.self, from: data)
    }

    func send(_ method: String, _ path: String, query: [String: String?] = [:], body: (any Encodable)? = nil, auth: Bool = true) async throws {
        _ = try await raw(method, path, query: query, body: body, auth: auth)
    }

    /// Kısayol: GET
    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await send("GET", path, query: query)
    }

    private func raw(_ method: String, _ path: String, query: [String: String?], body: (any Encodable)?, auth: Bool, retried: Bool = false) async throws -> Data {
        var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { comps.queryItems = items.sorted { $0.name < $1.name } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth, let token = keychain.get("access") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401, auth, !retried, keychain.get("refresh") != nil {
            try await refreshSession()
            return try await raw(method, path, query: query, body: body, auth: auth, retried: true)
        }
        guard (200..<300).contains(status) else {
            throw (try? decoder.decode(APIError.self, from: data)) ?? APIError(error: "http_\(status)", message: nil)
        }
        return data
    }

    /// Aynı anda gelen 401'ler tek bir yenileme isteğini paylaşır
    private func refreshSession() async throws {
        if let refreshTask { return try await refreshTask.value }
        let task = Task {
            defer { refreshTask = nil }
            guard let refresh = keychain.get("refresh") else { throw APIError(error: "unauthorized", message: "Oturum açmanız gerekiyor") }
            do {
                let s: AuthSession = try await send("POST", "/v1/auth/refresh", body: ["refreshToken": refresh], auth: false)
                store(s)
            } catch {
                clear()
                throw error
            }
        }
        refreshTask = task
        try await task.value
    }
}

// MARK: - Keychain

struct Keychain {
    let service: String

    func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, for key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }

    func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
