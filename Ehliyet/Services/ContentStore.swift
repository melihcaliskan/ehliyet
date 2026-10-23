import Foundation
import Observation

/// Sunucudan gelen ve birden çok ekranın paylaştığı veriler.
@Observable
@MainActor
final class ContentStore {
    private(set) var topics: [Topic] = []
    private(set) var progress: StudyProgress?
    private(set) var lessons: [Lesson] = []
    private(set) var resumeLessonId: String?
    private(set) var nextAppointment: Appointment?
    private(set) var readiness: Readiness?
    private(set) var daily: DailyStatus?

    private let api = APIClient.shared

    var wrongCount: Int { progress?.wrongCount ?? 0 }
    /// nil = sınırsız (premium) ya da henüz bilinmiyor
    var remainingFreeExams: Int? { progress?.mockExams.remaining }

    func refresh(signedIn: Bool) async {
        async let t: Void = loadTopics()
        async let l: Void = loadLessons()
        async let p: Void = signedIn ? loadProgress() : clearProgress()
        async let a: Void = signedIn ? loadNextAppointment() : clearAppointment()
        async let s: Void = signedIn ? loadStudyStatus() : clearStudyStatus()
        _ = await (t, l, p, a, s)
    }

    func loadStudyStatus() async {
        async let r: Readiness? = try? api.get("/v1/study/readiness")
        async let d: DailyStatus? = try? api.get("/v1/study/daily")
        (readiness, daily) = await (r, d)
        if let daily { DailyReminder.update(streak: daily.streak, completedToday: daily.completed) }
        DailyReminder.updateReadiness(readiness?.score)
    }

    private func clearStudyStatus() async { readiness = nil; daily = nil }

    func loadNextAppointment() async {
        let res: [String: [Appointment]]? = try? await api.get("/v1/calendar/appointments")
        nextAppointment = res?["appointments"]?.first { $0.startsAt >= Calendar.current.startOfDay(for: .now) }
        DailyReminder.scheduleExamCountdown(nextAppointment)
    }

    private func clearAppointment() async { nextAppointment = nil }

    func loadTopics() async {
        if let res: [String: [Topic]] = try? await api.get("/v1/study/topics") { topics = res["topics"] ?? [] }
    }

    func loadProgress() async {
        progress = try? await api.get("/v1/study/progress")
    }

    func loadLessons() async {
        if let res: LessonList = try? await api.get("/v1/lessons") {
            lessons = res.lessons
            resumeLessonId = res.resumeLessonId
        }
    }

    private func clearProgress() async { progress = nil }

    func saveLessonProgress(_ lesson: Lesson, positionSec: Int) async {
        struct Body: Encodable { let positionSec: Int }
        struct Res: Decodable { let positionSec: Int; let completed: Bool }
        guard let res: Res = try? await api.send("PUT", "/v1/lessons/\(lesson.id)/progress", body: Body(positionSec: positionSec)) else { return }
        if let i = lessons.firstIndex(where: { $0.id == lesson.id }) {
            lessons[i].positionSec = res.positionSec
            lessons[i].completed = res.completed
        }
        if !res.completed { resumeLessonId = lesson.id }
    }

    // MARK: Sınav

    func startExam(_ req: ExamRequest) async throws -> Exam {
        struct Body: Encodable { let kind: ExamKind; let topicId: String? }
        return try await api.send("POST", "/v1/study/exams", body: Body(kind: req.kind, topicId: req.topicId))
    }

    func answer(exam: Exam, question: Question, choice: Int) async {
        struct Body: Encodable { let questionId: String; let choice: Int }
        try? await api.send("POST", "/v1/study/exams/\(exam.id)/answers", body: Body(questionId: question.id, choice: choice))
    }

    func finish(exam: Exam, durationSec: Int) async throws -> ExamSummary {
        let summary: ExamSummary = try await api.send("POST", "/v1/study/exams/\(exam.id)/finish", body: ["durationSec": durationSec])
        async let p: Void = loadProgress()
        async let s: Void = loadStudyStatus()
        _ = await (p, s)
        return summary
    }
}
