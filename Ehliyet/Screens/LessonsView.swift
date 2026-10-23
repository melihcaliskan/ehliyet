import AVKit
import SwiftUI

struct LessonsView: View {
    @Environment(AppState.self) private var state
    @Environment(ContentStore.self) private var content
    @State private var kind: Lesson.Kind = .theory
    @State private var playing: Lesson?

    private var lessons: [Lesson] { content.lessons.filter { $0.kind == kind } }
    private var unlocked: Bool { state.isPremium || state.hasVideos }
    private var free: [Lesson] { lessons.filter { !$0.locked } }
    private var locked: [Lesson] { lessons.filter(\.locked) }
    /// Kaldığı ders yoksa ilk izlenmemiş ders
    private var resume: Lesson? {
        content.lessons.first { $0.id == content.resumeLessonId } ?? content.lessons.first { !$0.locked && !$0.completed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Dersler").font(.system(size: 34, weight: .bold))
                    Spacer()
                    if !unlocked {
                        Button { state.showPaywall = true } label: {
                            Label("Premium'a Geç", systemImage: "star.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        .glass(Capsule(), tint: Palette.tint, interactive: true)
                    }
                }
                .padding(.horizontal, 4).padding(.top, 8)

                if let resume { resumeCard(resume) }
                if content.lessons.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }

                Picker("Bölüm", selection: $kind.animation(.snappy)) {
                    Text("Teorik Dersler").tag(Lesson.Kind.theory)
                    Text("Direksiyon").tag(Lesson.Kind.driving)
                }
                .pickerStyle(.segmented)

                if let featured = locked.first {
                    LockedHero(lesson: featured) { state.showPaywall = true }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: unlocked ? "Tüm dersler" : "Ücretsiz",
                                  trailing: "\(lessons.filter(\.completed).count) / \(lessons.count) tamamlandı")
                    Card {
                        ForEach(Array(free.enumerated()), id: \.element.id) { i, l in
                            LessonRow(lesson: l, index: i + 1, watched: l.completed, current: l.id == resume?.id, locked: false) {
                                playing = l
                            }
                            if i < free.count - 1 { RowDivider(leading: 62) }
                        }
                    }
                }

                if !locked.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Premium", trailing: "Kilidi Aç") { state.showPaywall = true }
                        Card {
                            ForEach(Array(locked.enumerated()), id: \.element.id) { i, l in
                                LessonRow(lesson: l, index: free.count + i + 1, watched: false, current: false, locked: true) {
                                    state.showPaywall = true
                                }
                                if i < locked.count - 1 { RowDivider(leading: 62) }
                            }
                        }
                    }
                }
                TabBarSpacer()
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await content.loadLessons() }
        .fullScreenCover(item: $playing) { lesson in
            LessonPlayerView(lesson: lesson)
        }
    }

    private func resumeCard(_ resume: Lesson) -> some View {
        let total = Double(resume.minutes * 60)
        return Button { playing = resume } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(red: 0.11, green: 0.2, blue: 0.36), Color(red: 0.0, green: 0.3, blue: 0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.white.opacity(0.08))
                    .offset(x: 170, y: -20)
                VStack(alignment: .leading, spacing: 6) {
                    Text(resume.positionSec > 0 ? "Kaldığın yer · \(TimeInterval(resume.positionSec).clock)" : "Sıradaki ders")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 28)
                        .glass(Capsule())
                    Spacer()
                    Text("\(resume.chapter) · \(resume.minutes) dk")
                        .font(.system(size: 13)).opacity(0.85)
                    Text(resume.title).font(.system(size: 20, weight: .bold))
                    ProgressBar(value: min(1, Double(resume.positionSec) / total), tint: .white).padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(16)
                Image(systemName: "play.fill")
                    .font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .glass(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -10)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Devam et: \(resume.title)")
    }
}

struct LessonRow: View {
    let lesson: Lesson
    let index: Int
    let watched: Bool
    let current: Bool
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(locked ? Color(.systemFill) : watched ? Palette.green : Palette.tint)
                    Image(systemName: locked ? "lock.fill" : watched ? "checkmark" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(locked ? Color.secondary : .white)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(index). \(lesson.title)").font(.system(size: 16))
                        .foregroundStyle(locked ? .secondary : .primary)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(current ? Palette.tint : .secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18).frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if locked { return "\(lesson.minutes) dk · Premium" }
        if current { return "\(lesson.minutes) dk · Devam ediyor" }
        if watched { return "\(lesson.minutes) dk · İzlendi" }
        return "\(lesson.minutes) dk"
    }
}

/// Kilitli premium ders vitrini
struct LockedHero: View {
    let lesson: Lesson
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Canvas { ctx, size in
                    let w = size.width
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.17, green: 0.23, blue: 0.32)))
                    ctx.fill(Path(CGRect(x: 0, y: 96, width: w, height: 80)), with: .color(Color(red: 0.23, green: 0.25, blue: 0.31)))
                    var lane = Path(); lane.move(to: .init(x: 0, y: 100)); lane.addLine(to: .init(x: w, y: 100))
                    ctx.stroke(lane, with: .color(.white), style: .init(lineWidth: 3, dash: [16, 12]))
                    for x in [w * 0.17, w * 0.61] {
                        ctx.fill(Path(roundedRect: CGRect(x: x, y: 112, width: 70, height: 34), cornerRadius: 8), with: .color(Color(red: 0.56, green: 0.6, blue: 0.69)))
                    }
                    ctx.fill(Path(roundedRect: CGRect(x: w * 0.39, y: 58, width: 70, height: 34), cornerRadius: 8), with: .color(Palette.gold))
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.45)))
                }
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .glass(Circle())
                    .offset(y: -12)
            }
            .overlay(alignment: .topLeading) {
                Label("Premium", systemImage: "star.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 30)
                    .glass(Capsule())
                    .padding(14)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(lesson.title).font(.system(size: 18, weight: .bold))
                    Text("\(lesson.chapter) · \(lesson.minutes) dk").font(.system(size: 13)).opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Premium ders: \(lesson.title). Kilidi açmak için dokun")
    }
}

/// Ders oynatıcı. Sunucudaki HLS adresini oynatır, ilerlemeyi 15 sn'de bir ve kapanışta kaydeder.
struct LessonPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentStore.self) private var content
    let lesson: Lesson

    @State private var player: AVPlayer?
    @State private var position: TimeInterval = 0
    @State private var lastSaved: TimeInterval = 0
    @State private var observer: Any?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                ContentUnavailableView("Video bulunamadı", systemImage: "play.slash", description: Text("Bu dersin videosu henüz yüklenmedi."))
                    .foregroundStyle(.white)
            }
            HStack {
                GlassIconButton(systemName: "xmark", label: "Kapat", foreground: .white) { close() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(lesson.title).font(.system(size: 15, weight: .semibold))
                    Text(lesson.chapter).font(.system(size: 12)).opacity(0.7)
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                Spacer()
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: setUp)
        .onDisappear { player?.pause() }
    }

    private func setUp() {
        guard player == nil, let url = lesson.videoUrl else { return }
        let p = AVPlayer(url: url)
        if lesson.positionSec > 0 && !lesson.completed {
            p.seek(to: CMTime(seconds: Double(lesson.positionSec), preferredTimescale: 1))
        }
        Analytics.track("lesson_play", ["lesson": lesson.id])
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { time in
            MainActor.assumeIsolated {
                position = time.seconds
                if position - lastSaved >= 15 { save() }
            }
        }
        player = p
        p.play()
    }

    private func save() {
        guard position > 0 else { return }
        lastSaved = position
        let pos = Int(position)
        Task { await content.saveLessonProgress(lesson, positionSec: pos) }
    }

    private func close() {
        save()
        if let observer { player?.removeTimeObserver(observer) }
        dismiss()
    }
}
