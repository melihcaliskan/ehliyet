import SwiftUI

// Sunucu yanıtlarının modelleri. Alan adları API ile birebir aynıdır.

struct Topic: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let questionCount: Int
    var tint: Color { Color(hex: color) }
}

struct TopicProgress: Codable, Hashable {
    let topicId: String
    let total: Int
    let correct: Int
    let progress: Double
}

struct StudyProgress: Codable, Hashable {
    struct MockExams: Codable, Hashable { let used: Int; let limit: Int?; let remaining: Int? }
    let topics: [TopicProgress]
    let wrongCount: Int
    let mockExams: MockExams

    func progress(for topicId: String) -> Double { topics.first { $0.topicId == topicId }?.progress ?? 0 }
}

struct SignImage: Codable, Hashable {
    enum Shape: String, Codable { case warning, prohibitory, mandatory, info, stop, yield, end }
    let shape: Shape
    let symbol: String?
    let text: String?
    let slash: Bool?
}

struct Question: Codable, Identifiable, Hashable {
    let id: String
    let topicId: String
    let topic: String
    let text: String
    let options: [String]
    /// Gerçek sınav modunda sınav bitene kadar nil
    let answer: Int?
    let explanation: String?
    let image: SignImage?
}

enum ExamKind: String, Codable, Hashable {
    case mock, real, topic, wrongs, daily
    /// Cevap anında gösterilmez, sonunda toplu döküm
    var hidesFeedback: Bool { self == .real }
}

struct ExamRequest: Hashable {
    var kind: ExamKind
    var topicId: String? = nil
    var title: String? = nil
}

struct Exam: Codable, Hashable {
    struct Answered: Codable, Hashable { let questionId: String; let choice: Int }
    let id: String
    let kind: ExamKind
    let timeLimitSec: Int?
    let passScore: Int
    let finished: Bool?
    let questions: [Question]
    let answered: [Answered]?
}

struct ExamReview: Codable {
    struct Item: Codable, Identifiable {
        let question: Question
        let choice: Int?
        let correct: Bool
        var id: String { question.id }
    }
    let summary: ExamSummary
    let items: [Item]
}

struct Readiness: Codable, Hashable {
    struct Weakest: Codable, Hashable { let topicId: String; let name: String; let progress: Double }
    let score: Int
    let level: String
    let advice: String
    let examAverage: Int?
    let examsCounted: Int
    let coverage: Int
    let weakestTopic: Weakest?
}

struct DailyStatus: Codable, Hashable {
    let date: String
    let size: Int
    let started: Bool
    let completed: Bool
    let correct: Int?
    let streak: Int
    let best: Int
}

struct Checklist: Codable {
    struct Item: Codable, Identifiable, Hashable { let id: String; let title: String; let detail: String }
    struct Section: Codable, Identifiable, Hashable {
        let id: String
        let title: String
        let icon: String
        let warning: Bool?
        let items: [Item]
    }
    let updatedAt: String
    let sections: [Section]
}

struct ExamSummary: Codable, Hashable, Identifiable {
    let id: String
    let kind: ExamKind
    let topicId: String?
    let total: Int
    let correct: Int
    let wrong: Int
    let score: Int
    let passed: Bool
    let durationSec: Int
    let startedAt: Date
    let finishedAt: Date?
}

struct Lesson: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Hashable { case theory, driving }
    let id: String
    let kind: Kind
    let chapter: String
    let title: String
    let minutes: Int
    let isPremium: Bool
    let locked: Bool
    let videoUrl: URL?
    var positionSec: Int
    var completed: Bool
}

struct LessonList: Codable { let lessons: [Lesson]; let resumeLessonId: String? }

struct Checkpoint: Codable, Hashable { let title: String; let detail: String; let lat: Double; let lng: Double }

struct DrivingRoute: Codable, Identifiable, Hashable {
    let id: String
    let city: String
    let district: String
    let name: String
    let distanceKm: Double
    let isPremium: Bool
    let locked: Bool
    let center: [Double]?
    let path: [[Double]]
    let checkpoints: [Checkpoint]
    let checkpointCount: Int
    let videoLessonId: String?
}

struct City: Codable, Hashable { let name: String; let districts: [String] }

struct FeeTable: Codable, Hashable {
    struct Item: Codable, Hashable, Identifiable { let id: String; let title: String; let amountKurus: Int; let isCourseFee: Bool; let isEstimate: Bool }
    struct Section: Codable, Hashable, Identifiable { let id: String; let title: String; let items: [Item]; let subtotalKurus: Int }
    let licenseClass: String
    let validFrom: String
    let totalKurus: Int
    let isEstimate: Bool
    let sources: [String]
    let sections: [Section]
    let note: String
}

struct CalendarInfo: Codable, Hashable {
    let eSinav: String
    let direksiyon: String
    let source: String
}

struct SessionsResponse: Codable {
    let sessions: [ExamSession]
    let info: CalendarInfo?
}

struct ExamSession: Codable, Hashable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let date: String // YYYY-MM-DD
    let city: String?
    let note: String?
}

struct Appointment: Codable, Hashable, Identifiable {
    let id: String
    var kind: String
    var title: String
    var startsAt: Date
    var location: String?
    var color: Color { kind == "direksiyon" ? Palette.orange : Palette.tint }
}

struct AppNotification: Codable, Hashable, Identifiable {
    let id: String
    let kind: String
    let icon: String
    let color: String
    let title: String
    let body: String
    let date: Date
}

// MARK: - Yardımcılar

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension Int {
    /// Kuruş → "42.279,44 ₺"
    var lira: String { (Double(self) / 100).lira }
}

extension Double {
    var lira: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: self)) ?? "\(self)") + " ₺"
    }
}

extension TimeInterval {
    var clock: String {
        let s = Int(self)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

extension Locale {
    static let tr = Locale(identifier: "tr_TR")
}
