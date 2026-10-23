import Foundation
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Yerel bildirimler ve widget verisi.
/// - Günlük hatırlatma: her akşam 20:00, o gün 10 soru bitmediyse.
/// - Sınav geri sayımı: randevudan 7, 3 ve 1 gün önce.
/// Sunucu tarafında push anahtarı gerektirmez.
enum DailyReminder {
    static let appGroup = "group.com.melihcaliskan.ehliyet"
    private static let hour = 20
    private static var enabled: Bool { UserDefaults.standard.object(forKey: "dailyReminder") as? Bool ?? true }

    /// Kullanıcı ilk kez günlük soruyu bitirince izin istenir (soğuk açılışta değil)
    static func didCompleteToday() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func update(streak: Int, completedToday: Bool) {
        shared?.set(streak, forKey: "streak")
        shared?.set(completedToday, forKey: "dailyCompleted")
        shared?.set(Date.now, forKey: "dailyUpdatedAt")
        reloadWidgets()

        let center = UNUserNotificationCenter.current()
        let ids = (0..<7).map { "daily-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }

        let cal = Calendar.current
        for offset in (completedToday ? 1 : 0)..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: .now),
                  let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Günün 10 sorusu hazır"
            content.body = streak > 0 && offset <= 1
                ? "\(streak) günlük serini kaybetme. 3 dakikanı al."
                : "Yanlışlarını tekrar ettiren 10 soru seni bekliyor."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
            center.add(UNNotificationRequest(identifier: "daily-\(offset)", content: content, trigger: trigger))
        }
    }

    static func scheduleExamCountdown(_ appointment: Appointment?) {
        shared?.set(appointment?.startsAt, forKey: "nextExamDate")
        shared?.set(appointment?.title, forKey: "nextExamTitle")
        reloadWidgets()

        let center = UNUserNotificationCenter.current()
        let ids = [7, 3, 1].map { "exam-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled, let appointment else { return }

        let cal = Calendar.current
        for days in [7, 3, 1] {
            guard let day = cal.date(byAdding: .day, value: -days, to: appointment.startsAt),
                  let fire = cal.date(bySettingHour: 19, minute: 0, second: 0, of: day), fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(appointment.title): \(days) gün kaldı"
            content.body = days == 1 ? "Yarın sınavın var. Kontrol listeni gözden geçir, erken yat." : "Bir gerçek sınav provası çözerek hazırlığını ölç."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
            center.add(UNNotificationRequest(identifier: "exam-\(days)", content: content, trigger: trigger))
        }
    }

    static func updateReadiness(_ score: Int?) {
        shared?.set(score, forKey: "readiness")
        reloadWidgets()
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
