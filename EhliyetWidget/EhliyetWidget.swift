import SwiftUI
import WidgetKit

/// Ana ekran widget'ı: sınava kalan gün, günlük seri ve hazırlık skoru.
/// Veriyi uygulama App Group üzerinden yazar (DailyReminder).
struct Snapshot: TimelineEntry {
    let date: Date
    let examTitle: String?
    let examDate: Date?
    let streak: Int
    let dailyDone: Bool
    let readiness: Int?

    var daysLeft: Int? {
        guard let examDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: examDate)).day
    }

    static let placeholder = Snapshot(date: .now, examTitle: "E-Sınav (Teorik)", examDate: .now.addingTimeInterval(12 * 86_400), streak: 4, dailyDone: false, readiness: 72)

    static func load(at date: Date = .now) -> Snapshot {
        let d = UserDefaults(suiteName: "group.com.melihcaliskan.ehliyet")
        let updated = d?.object(forKey: "dailyUpdatedAt") as? Date
        // Gün değiştiyse "bugün yapıldı" bilgisi geçersiz
        let doneToday = (d?.bool(forKey: "dailyCompleted") ?? false) && updated.map { Calendar.current.isDate($0, inSameDayAs: date) } == true
        return Snapshot(
            date: date,
            examTitle: d?.string(forKey: "nextExamTitle"),
            examDate: d?.object(forKey: "nextExamDate") as? Date,
            streak: d?.integer(forKey: "streak") ?? 0,
            dailyDone: doneToday,
            readiness: d?.object(forKey: "readiness") as? Int
        )
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Snapshot { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (Snapshot) -> Void) {
        completion(context.isPreview ? .placeholder : .load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Snapshot>) -> Void) {
        // Gece yarısı gün sayısı ve "bugün" durumu yenilenir
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [.load(), .load(at: midnight)], policy: .after(midnight)))
    }
}

private let brandTint = Color(red: 0, green: 0.384, blue: 0.8)
private let brandOrange = Color(red: 0.95, green: 0.45, blue: 0.05)

struct EhliyetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Snapshot

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        case .accessoryCircular: circular
        case .systemMedium: medium
        default: small
        }
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let days = entry.daysLeft, days >= 0 {
                Text(days == 0 ? "Bugün" : "\(days)")
                    .font(.system(size: days == 0 ? 30 : 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(days == 0 ? (entry.examTitle ?? "Sınav") : "gün kaldı").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            } else {
                Image(systemName: "calendar.badge.plus").font(.system(size: 28, weight: .semibold)).foregroundStyle(brandTint)
                Text("Sınav tarihini ekle").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private var streakPill: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.dailyDone ? "checkmark.circle.fill" : "flame.fill")
            Text(entry.dailyDone ? "Bugün tamam" : entry.streak > 0 ? "\(entry.streak) gün seri" : "10 soru çöz")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(entry.dailyDone ? .green : brandOrange)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = entry.examTitle, entry.daysLeft != nil { Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(brandTint).lineLimit(1) }
            countdown
            Spacer(minLength: 0)
            streakPill
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "ehliyet://daily"))
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if let t = entry.examTitle, entry.daysLeft != nil { Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(brandTint).lineLimit(1) }
                countdown
                Spacer(minLength: 0)
                streakPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let r = entry.readiness {
                VStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                        Circle().trim(from: 0, to: Double(r) / 100).stroke(brandTint, style: .init(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("%\(r)").font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    .frame(width: 76, height: 76)
                    Text("Hazırlık").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "ehliyet://daily"))
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let days = entry.daysLeft, days >= 0 {
                Text(days == 0 ? "Sınav bugün" : "Sınava \(days) gün").font(.headline)
            } else {
                Text("Ehliyet").font(.headline)
            }
            Label(entry.dailyDone ? "Bugünkü 10 soru tamam" : "Günün 10 sorusu bekliyor", systemImage: entry.dailyDone ? "checkmark" : "flame")
                .font(.caption)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.system(size: 12))
                Text("\(entry.streak)").font(.system(size: 18, weight: .bold, design: .rounded))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct EhliyetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EhliyetWidget", provider: Provider()) { EhliyetWidgetView(entry: $0) }
            .configurationDisplayName("Sınav Geri Sayımı")
            .description("Sınavına kalan gün, günlük seri ve hazırlık skorun.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct EhliyetWidgetBundle: WidgetBundle {
    var body: some Widget { EhliyetWidget() }
}

#Preview(as: .systemMedium) { EhliyetWidget() } timeline: { Snapshot.placeholder }
