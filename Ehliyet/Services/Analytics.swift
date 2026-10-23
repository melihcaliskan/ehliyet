import Foundation
import UIKit

/// Uygulama içi olay takibi. Olaylar bellekte biriktirilir ve toplu olarak `/v1/events`'e gönderilir.
/// Kişisel veri (e-posta, isim, soru metni) özelliklere yazılmaz; yalnızca kimlikler ve sayılar.
@MainActor
final class Analytics {
    static let shared = Analytics()

    typealias Props = [String: AnalyticsValue]

    private struct Event: Encodable { let name: String; let props: Props?; let at: String }
    private struct Batch: Encodable { let deviceId: String; let sessionId: String; let appVersion: String; let events: [Event] }

    private var queue: [Event] = []
    private var sessionId = UUID().uuidString
    private var backgroundedAt: Date?
    private var flushTask: Task<Void, Never>?
    private let iso = ISO8601DateFormatter()

    /// Kurulum başına anonim kimlik
    private let deviceId: String = {
        let key = "analytics.deviceId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    nonisolated static func track(_ name: String, _ props: [String: Any]? = nil) {
        let converted: Props? = props?.compactMapValues { v in
            switch v {
            case let b as Bool: .bool(b)
            case let i as Int: .int(i)
            case let d as Double: .double(d)
            case let s as String: .string(String(s.prefix(200)))
            default: nil
            }
        }
        Task { @MainActor in shared.enqueue(name, converted) }
    }

    private func enqueue(_ name: String, _ props: Props?) {
        queue.append(Event(name: name, props: props, at: iso.string(from: .now)))
        if queue.count >= 20 { flush() } else { scheduleFlush() }
    }

    // MARK: Yaşam döngüsü

    func didBecomeActive() {
        // 30 dakikadan uzun arka plan yeni oturum sayılır
        if let at = backgroundedAt, Date.now.timeIntervalSince(at) > 30 * 60 { sessionId = UUID().uuidString }
        backgroundedAt = nil
        enqueue("app_open", nil)
    }

    func didEnterBackground() {
        enqueue("app_background", nil)
        backgroundedAt = .now
        // Arka plana geçerken gönderim için kısa süre iste
        let id = UIApplication.shared.beginBackgroundTask(withName: "analytics")
        Task {
            await send()
            UIApplication.shared.endBackgroundTask(id)
        }
    }

    // MARK: Gönderim

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(for: .seconds(20))
            flushTask = nil
            await send()
        }
    }

    private func flush() {
        flushTask?.cancel()
        flushTask = nil
        Task { await send() }
    }

    private func send() async {
        guard !queue.isEmpty else { return }
        let events = Array(queue.prefix(100))
        queue.removeFirst(events.count)
        let batch = Batch(deviceId: deviceId, sessionId: sessionId, appVersion: appVersion, events: events)
        do {
            try await APIClient.shared.send("POST", "/v1/events", body: batch)
        } catch {
            // Ağ yoksa geri koy; kuyruk sınırsız büyümesin
            queue.insert(contentsOf: events, at: 0)
            if queue.count > 500 { queue.removeFirst(queue.count - 500) }
        }
    }
}

/// Olay özelliği: metin, sayı veya mantıksal değer
enum AnalyticsValue: Encodable, Sendable {
    case string(String), int(Int), double(Double), bool(Bool)

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }
}
