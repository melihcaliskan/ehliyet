import SwiftUI

// MARK: - Sorular sekmesi

struct QuestionsHubView: View {
    @Environment(AppState.self) private var state
    @Environment(ContentStore.self) private var content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sorular")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Deneme Sınavı", systemImage: "stopwatch.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Gerçek e-sınav formatında 50 soru")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text(quotaText)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                    Button { state.push(.exam(.init(kind: .mock))) } label: {
                        Text("Başla")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.tint)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(20)
                .background(Palette.tint.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                DailyCard()
                ReadinessCard()

                SectionHeader(title: "Konular")
                Card {
                    if content.topics.isEmpty {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                    ForEach(Array(content.topics.enumerated()), id: \.element.id) { i, t in
                        NavRow(icon: t.icon, color: t.tint, title: t.name, value: "%\((content.progress?.progress(for: t.id) ?? 0).percent)") {
                            state.push(.exam(.init(kind: .topic, topicId: t.id, title: t.name)))
                        }
                        if i < content.topics.count - 1 { RowDivider() }
                    }
                }

                SectionHeader(title: "Tekrar")
                Card {
                    NavRow(icon: "xmark", color: Palette.orange, title: "Yanlışlarım", value: "\(content.wrongCount)") { state.push(.wrongAnswers) }
                    RowDivider()
                    NavRow(icon: "clock.arrow.circlepath", color: Palette.indigo, title: "Sınav Geçmişi") { state.push(.examHistory) }
                }
                TabBarSpacer()
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await content.loadProgress() }
    }

    private var quotaText: String {
        if state.isPremium { return "Sınırsız deneme" }
        guard let remaining = content.remainingFreeExams else { return "3 ücretsiz deneme hakkı" }
        return "\(remaining) / 3 ücretsiz hak kaldı"
    }
}

extension Double {
    /// 0.62 → 62
    var percent: Int { Int((self * 100).rounded()) }
}

// MARK: - Sınav (soru çözme)

struct ExamView: View {
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    let request: ExamRequest

    enum Phase { case loading, signInRequired, failed(String), ready(Exam) }
    @State private var phase: Phase = .loading
    @State private var index = 0
    @State private var choices: [String: Int] = [:]
    @State private var elapsed: TimeInterval = 0
    @State private var confirmExit = false
    @State private var confirmFinish = false
    @State private var showMap = false
    @State private var finishing = false
    @State private var reporting: Question?
    @State private var reportText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isReal: Bool { request.kind.hidesFeedback }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Sorular hazırlanıyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signInRequired:
                ContentUnavailableView {
                    Label("Giriş yapman gerekiyor", systemImage: "person.crop.circle")
                } description: {
                    Text("Sınav sonuçların ve yanlışların hesabına kaydedilir.")
                } actions: {
                    Button("Giriş Yap") { auth.showLogin = true }.buttonStyle(.borderedProminent)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Sınav başlatılamadı", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Tekrar Dene") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            case .ready(let exam):
                examBody(exam)
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) { topBar }
        .task(id: auth.isSignedIn) { await load() }
        .onReceive(timer) { _ in if case .ready = phase { elapsed += 1 } }
        .confirmationDialog("Sınavdan çıkılsın mı?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Çık", role: .destructive) { dismiss() }
        } message: {
            Text("Cevapladığın sorular kaydedildi.")
        }
        .alert("Soruda hata mı var?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            TextField("Kısaca açıkla", text: $reportText)
            Button("Gönder") { sendReport() }
            Button("Vazgeç", role: .cancel) { reportText = "" }
        } message: {
            Text("Bildirimin incelenip soru düzeltilecek.")
        }
    }

    private func load() async {
        guard auth.isSignedIn else { phase = .signInRequired; return }
        if case .ready = phase { return }
        phase = .loading
        do {
            let exam = try await content.startExam(request)
            index = 0; elapsed = 0
            choices = Dictionary((exam.answered ?? []).map { ($0.questionId, $0.choice) }, uniquingKeysWith: { $1 })
            // Günlük sorulara kaldığı yerden devam
            if let firstOpen = exam.questions.firstIndex(where: { choices[$0.id] == nil }) { index = firstOpen }
            if exam.finished == true {
                state.push(.examResult(try await content.finish(exam: exam, durationSec: 0)))
                return
            }
            phase = .ready(exam)
            Analytics.track("exam_start", ["kind": request.kind.rawValue, "questions": exam.questions.count])
        } catch let err as APIError where err.error == "free_limit_reached" || err.error == "premium_required" {
            Analytics.track("paywall_hit", ["reason": err.error])
            dismiss()
            state.showPaywall = true
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Soru gövdesi

    private func examBody(_ exam: Exam) -> some View {
        let q = exam.questions[index]
        let selected = choices[q.id]
        let isLast = index == exam.questions.count - 1
        let showFeedback = !isReal && selected != nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(q.topic.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.tint)
                    Spacer()
                    if isReal {
                        Label("Gerçek sınav modu", systemImage: "eye.slash")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                if let image = q.image {
                    TrafficSignView(sign: image, size: 150)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                Text(q.text)
                    .font(.system(size: 22, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    ForEach(q.options.indices, id: \.self) { i in
                        OptionRow(letter: String(UnicodeScalar(65 + i)!), text: q.options[i], state: optionState(i, q, selected: selected)) {
                            select(i, for: q, in: exam)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Cevap seçenekleri")

                if showFeedback, let explanation = q.explanation {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(selected == q.answer ? "Doğru!" : "Doğru cevap: \(q.answer.map { q.options[$0] } ?? "")",
                              systemImage: selected == q.answer ? "checkmark.circle.fill" : "lightbulb.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.green)
                        Text(explanation).font(.system(size: 15))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Palette.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 76)
            .animation(.snappy, value: index)
        }
        .overlay(alignment: .bottom) { bottomBar(exam, isLast: isLast, canAdvance: isReal || selected != nil) }
        .sheet(isPresented: $showMap) { questionMap(exam).presentationDetents([.medium]) }
        .confirmationDialog(unansweredText(exam), isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Sınavı Bitir", role: .destructive) { Task { await finish(exam) } }
        }
        .onChange(of: elapsed) { _, t in
            // Süre dolunca sınav kendiliğinden biter
            if let limit = exam.timeLimitSec, Int(t) >= limit, !finishing { Task { await finish(exam) } }
        }
    }

    private func select(_ i: Int, for q: Question, in exam: Exam) {
        if !isReal && choices[q.id] != nil { return } // alıştırmada cevap kilitlenir
        withAnimation(.spring(duration: 0.3)) { choices[q.id] = i }
        if !isReal, let answer = q.answer {
            UIImpactFeedbackGenerator(style: i == answer ? .light : .rigid).impactOccurred()
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        Task { await content.answer(exam: exam, question: q, choice: i) }
    }

    private func bottomBar(_ exam: Exam, isLast: Bool, canAdvance: Bool) -> some View {
        HStack(spacing: 10) {
            if isReal {
                Button { withAnimation(.snappy) { index -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .opacity(index == 0 ? 0.4 : 1)
                .accessibilityLabel("Önceki soru")
            }
            PrimaryButton(title: finishing ? "Hesaplanıyor…" : (isLast ? "Sınavı Bitir" : "Sonraki Soru"), systemImage: isLast ? "flag.checkered" : nil) {
                if isLast {
                    if isReal && choices.count < exam.questions.count { confirmFinish = true }
                    else { Task { await finish(exam) } }
                } else {
                    withAnimation(.snappy) { index += 1 }
                }
            }
            .disabled(!canAdvance || finishing)
            .opacity(canAdvance ? 1 : 0.5)
        }
        .padding(10)
        .glass(Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Gerçek sınavdaki gibi soru haritası: hangi sorular boş
    private func questionMap(_ exam: Exam) -> some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(exam.questions.indices, id: \.self) { i in
                        let answered = choices[exam.questions[i].id] != nil
                        Button { index = i; showMap = false } label: {
                            Text("\(i + 1)")
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(answered ? .white : .primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(answered ? Palette.tint : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    if i == index { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.orange, lineWidth: 2) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Soru \(i + 1), \(answered ? "cevaplandı" : "boş")")
                    }
                }
                .padding(20)
            }
            .navigationTitle("\(choices.count) / \(exam.questions.count) cevaplandı")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func unansweredText(_ exam: Exam) -> String {
        let n = exam.questions.count - choices.count
        return n > 0 ? "\(n) soru boş. Boş sorular yanlış sayılır." : "Sınavı bitirmek istiyor musun?"
    }

    private func finish(_ exam: Exam) async {
        guard !finishing else { return }
        finishing = true
        defer { finishing = false }
        do {
            let summary = try await content.finish(exam: exam, durationSec: Int(elapsed))
            Analytics.track("exam_finish", ["kind": exam.kind.rawValue, "score": summary.score, "duration": Int(elapsed)])
            if exam.kind == .daily { await DailyReminder.didCompleteToday() }
            state.push(.examResult(summary))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func sendReport() {
        guard let q = reporting, reportText.trimmingCharacters(in: .whitespaces).count >= 3 else { return }
        let message = reportText
        reportText = ""
        Task { try? await APIClient.shared.send("POST", "/v1/study/questions/\(q.id)/report", body: ["message": message]) }
        Analytics.track("question_report", ["question": q.id])
    }

    private var topBar: some View {
        GlassTopBar {
            GlassIconButton(systemName: "xmark", label: "Kapat") {
                if case .ready = phase { confirmExit = true } else { dismiss() }
            }
        } trailing: {
            if case .ready(let exam) = phase {
                HStack(spacing: 8) {
                    Button { if isReal { showMap = true } } label: {
                        Text(request.title ?? "\(index + 1) / \(exam.questions.count)")
                            .font(.system(size: 15, weight: .semibold).monospacedDigit()).lineLimit(1)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14).frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .glass(Capsule(), interactive: isReal)
                    .accessibilityHint(isReal ? "Soru haritasını açar" : "")
                    Label(timeText(exam), systemImage: "timer")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 12).frame(height: 46)
                        .glass(Capsule())
                    Menu {
                        Button("Soruda hata bildir", systemImage: "exclamationmark.bubble") { reporting = exam.questions[index] }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                            .frame(width: 46, height: 46).contentShape(Circle())
                    }
                    .glass(Circle(), interactive: true)
                    .accessibilityLabel("Diğer")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if case .ready(let exam) = phase {
                ProgressBar(value: Double(index + 1) / Double(exam.questions.count))
                    .padding(.horizontal, 16)
                    .offset(y: 14)
            }
        }
    }

    private func timeText(_ exam: Exam) -> String {
        guard let limit = exam.timeLimitSec else { return elapsed.clock }
        return max(0, TimeInterval(limit) - elapsed).clock
    }

    private func optionState(_ i: Int, _ q: Question, selected: Int?) -> OptionRow.State {
        guard let selected else { return .idle }
        if isReal { return i == selected ? .selected : .idle }
        if i == q.answer { return .correct }
        if i == selected { return .wrong }
        return .dimmed
    }
}

struct OptionRow: View {
    enum State { case idle, selected, correct, wrong, dimmed }
    let letter: String
    let text: String
    let state: State
    let action: () -> Void

    private var color: Color {
        switch state {
        case .correct: Palette.green
        case .wrong: Palette.red
        case .selected: Palette.tint
        default: .primary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(state == .correct || state == .wrong || state == .selected ? color : Color(.tertiarySystemFill))
                    if state == .correct {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    } else if state == .wrong {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text(letter).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(state == .selected ? .white : .primary)
                    }
                }
                .frame(width: 32, height: 32)
                Text(text).font(.system(size: 17)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14).frame(minHeight: 60)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(state == .correct || state == .wrong || state == .selected ? color : .clear, lineWidth: 2)
            }
            .opacity(state == .dimmed ? 0.55 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityValue(state == .correct ? "Doğru" : state == .wrong ? "Yanlış" : state == .selected ? "Seçili" : "")
    }
}

// MARK: - Sınav sonucu / Ücretsiz hak bitti

struct ExamResultView: View {
    @Environment(AppState.self) private var state
    @Environment(ContentStore.self) private var content
    let result: ExamSummary

    private var limitReached: Bool { (result.kind == .mock || result.kind == .real) && !state.isPremium && content.remainingFreeExams == 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    ScoreRing(score: result.score, passed: result.passed)
                        .frame(width: 150, height: 150)
                    Text(result.passed ? "Tebrikler, geçtin!" : "Biraz daha çalışmalısın")
                        .font(.system(size: 22, weight: .bold))
                    HStack(spacing: 0) {
                        stat("\(result.correct)", "Doğru", Palette.green)
                        Divider().frame(height: 36)
                        stat("\(result.wrong)", "Yanlış", Palette.red)
                        Divider().frame(height: 36)
                        stat(TimeInterval(result.durationSec).clock, "Süre", .primary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                if result.kind == .daily {
                    StreakBadge()
                }
                SecondaryButton(title: "Cevapları İncele") { state.push(.examReview(result.id)) }
                if limitReached {
                    limitCard
                } else if result.wrong > 0 {
                    PrimaryButton(title: "Yanlışlarımı Gör") { state.push(.wrongAnswers) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "xmark", label: "Kapat") { popToRoot() }
            } trailing: {
                ShareLink(item: "Ehliyet deneme sınavından \(result.score) puan aldım!") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                }
                .glass(Circle(), interactive: true)
            }
        }
    }

    private var title: String {
        switch result.kind {
        case .mock: "Deneme Sınavı · Sonuç"
        case .real: "Gerçek Sınav Provası · Sonuç"
        case .daily: "Günün 10 Sorusu · Sonuç"
        case .topic: "\(content.topics.first { $0.id == result.topicId }?.name ?? "Konu Testi") · Sonuç"
        case .wrongs: "Yanlışlar Testi · Sonuç"
        }
    }

    private var limitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(systemName: "lock.fill", color: Palette.tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ücretsiz deneme hakkın bitti").font(.system(size: 17, weight: .semibold))
                    Text("3 ücretsiz deneme sınavının hepsini çözdün.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Text("Sınırsız deneme ve tüm çıkmış sorular için Premium'a geç.")
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 10) {
                PerkRow(text: "Sınırsız deneme sınavı")
                PerkRow(text: "Yanlışlarına özel tekrar testleri")
                PerkRow(text: "Tüm ders ve direksiyon videoları")
            }
            PrimaryButton(title: "Premium'u İncele", systemImage: "star.fill") { state.showPaywall = true }
            Button("Ücretsiz konu testleriyle devam et") { state.push(.topicTests) }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func popToRoot() {
        switch state.selectedTab {
        case .questions: state.questionsPath = NavigationPath()
        case .lessons: state.lessonsPath = NavigationPath()
        default: state.homePath = NavigationPath()
        }
    }
}

struct ScoreRing: View {
    let score: Int
    let passed: Bool
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(Color(.systemFill), lineWidth: lineWidth)
            Circle().trim(from: 0, to: Double(score) / 100)
                .stroke(passed ? Palette.green : Palette.red, style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: lineWidth * 3.6, weight: .bold))
                if lineWidth >= 10 { Text("/ 100 puan").font(.system(size: 13)).foregroundStyle(.secondary) }
            }
        }
    }
}

struct PerkRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.tint)
            Text(text).font(.system(size: 15))
        }
    }
}

// MARK: - Konu testleri

struct TopicTestsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(ContentStore.self) private var content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Konu Testleri").font(.system(size: 34, weight: .bold)).padding(.horizontal, 4)
                Text("Konu testleri ücretsizdir ve deneme hakkından düşmez.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).padding(.horizontal, 4)
                LazyVGrid(columns: [.init(.flexible(), spacing: 12), .init(.flexible())], spacing: 12) {
                    ForEach(content.topics) { t in
                        let progress = content.progress?.progress(for: t.id) ?? 0
                        Button { state.push(.exam(.init(kind: .topic, topicId: t.id, title: t.name))) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                IconTile(systemName: t.icon, color: t.tint, size: 40)
                                Spacer(minLength: 8)
                                Text(t.name).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.leading)
                                Text("\(t.questionCount) soru · %\(progress.percent)").font(.system(size: 13)).foregroundStyle(.secondary)
                                ProgressBar(value: progress, tint: t.tint)
                            }
                            .foregroundStyle(.primary)
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: { EmptyView() }
        }
    }
}

// MARK: - Yanlışlarım

struct WrongAnswersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth

    @State private var wrongs: [Question]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Yanlışlarım").font(.system(size: 34, weight: .bold)).padding(.horizontal, 4)
                if !auth.isSignedIn {
                    ContentUnavailableView {
                        Label("Giriş yap", systemImage: "person.crop.circle")
                    } description: {
                        Text("Yanlış yaptığın sorular hesabında toplanır.")
                    } actions: {
                        Button("Giriş Yap") { auth.showLogin = true }.buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                } else if let wrongs {
                    if wrongs.isEmpty {
                        ContentUnavailableView("Yanlışın yok", systemImage: "checkmark.seal.fill",
                                               description: Text("Yanlış yaptığın sorular burada toplanır; doğru cevaplayınca listeden düşer."))
                            .padding(.top, 60)
                    } else {
                        Button { state.push(.exam(.init(kind: .wrongs, title: "Yanlışlarım"))) } label: {
                            Label(state.isPremium ? "Hepsini tekrar çöz" : "Tekrar testi · Premium", systemImage: state.isPremium ? "arrow.clockwise" : "lock.fill")
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Palette.tint, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())

                        Card {
                            ForEach(Array(wrongs.enumerated()), id: \.element.id) { i, q in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(q.topic).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.orange)
                                    Text(q.text).font(.system(size: 16))
                                    Text("Doğru: \(q.answer.map { q.options[$0] } ?? "")").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.green)
                                    Text(q.explanation ?? "").font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                if i < wrongs.count - 1 { RowDivider(leading: 18) }
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: { EmptyView() }
        }
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn else { return }
            let res: [String: [Question]]? = try? await APIClient.shared.get("/v1/study/wrong-answers")
            wrongs = res?["questions"] ?? []
        }
    }
}

// MARK: - Sınav geçmişi (tasarımda yoktu, eklendi)

struct ExamHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(ContentStore.self) private var content

    @State private var exams: [ExamSummary]?

    private var mocks: [ExamSummary] { (exams ?? []).filter { $0.kind == .mock || $0.kind == .real } }
    private var average: Int? { mocks.isEmpty ? nil : mocks.map(\.score).reduce(0, +) / mocks.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sınav Geçmişi").font(.system(size: 34, weight: .bold)).padding(.horizontal, 4)

                if let exams {
                    if exams.isEmpty {
                        ContentUnavailableView("Henüz sınav yok", systemImage: "doc.text.magnifyingglass",
                                               description: Text("Çözdüğün deneme ve konu testleri burada listelenir."))
                            .padding(.top, 60)
                    } else {
                        summaryCard
                        Card {
                            ForEach(Array(exams.enumerated()), id: \.element.id) { i, e in
                                Button { state.push(.examResult(e)) } label: { row(e) }
                                    .buttonStyle(.plain)
                                if i < exams.count - 1 { RowDivider(leading: 72) }
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: { EmptyView() }
        }
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn else { exams = []; return }
            let res: [String: [ExamSummary]]? = try? await APIClient.shared.get("/v1/study/exams")
            exams = res?["exams"] ?? []
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            metric("\(mocks.count)", "Deneme")
            Divider().frame(height: 40)
            metric(average.map(String.init) ?? "–", "Ortalama")
            Divider().frame(height: 40)
            metric("\(mocks.filter(\.passed).count)", "Geçti")
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold).monospacedDigit())
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ e: ExamSummary) -> some View {
        HStack(spacing: 14) {
            ScoreRing(score: e.score, passed: e.passed, lineWidth: 4)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindTitle(e)).font(.system(size: 16, weight: .semibold))
                Text("\((e.finishedAt ?? e.startedAt).formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(.tr))) · \(e.correct)/\(e.total) doğru")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18).frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private func kindTitle(_ e: ExamSummary) -> String {
        switch e.kind {
        case .mock: "Deneme Sınavı"
        case .real: "Gerçek Sınav Provası"
        case .daily: "Günün 10 Sorusu"
        case .topic: content.topics.first { $0.id == e.topicId }?.name ?? "Konu Testi"
        case .wrongs: "Yanlışlar Testi"
        }
    }
}

// MARK: - Cevap dökümü

struct ExamReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let examId: String
    @State private var review: ExamReview?
    @State private var onlyWrong = false

    private var items: [ExamReview.Item] { (review?.items ?? []).filter { !onlyWrong || !$0.correct } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cevaplar").font(.system(size: 34, weight: .bold)).padding(.horizontal, 4)
                if let review {
                    Picker("Göster", selection: $onlyWrong) {
                        Text("Tümü (\(review.items.count))").tag(false)
                        Text("Yanlış ve boş (\(review.items.filter { !$0.correct }.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    ForEach(Array(items.enumerated()), id: \.element.id) { _, item in reviewCard(item, number: (review.items.firstIndex { $0.id == item.id } ?? 0) + 1) }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: { EmptyView() }
        }
        .task { review = try? await APIClient.shared.get("/v1/study/exams/\(examId)/review") }
    }

    private func reviewCard(_ item: ExamReview.Item, number: Int) -> some View {
        let q = item.question
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(number). soru · \(q.topic)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Label(item.choice == nil ? "Boş" : item.correct ? "Doğru" : "Yanlış",
                      systemImage: item.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.correct ? Palette.green : Palette.red)
            }
            if let image = q.image { TrafficSignView(sign: image, size: 90).frame(maxWidth: .infinity) }
            Text(q.text).font(.system(size: 17, weight: .semibold))
            ForEach(q.options.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Image(systemName: i == q.answer ? "checkmark.circle.fill" : i == item.choice ? "xmark.circle.fill" : "circle")
                        .foregroundStyle(i == q.answer ? Palette.green : i == item.choice ? Palette.red : Color.secondary)
                    Text(q.options[i]).font(.system(size: 15))
                        .foregroundStyle(i == q.answer || i == item.choice ? .primary : .secondary)
                }
            }
            if let e = q.explanation {
                Text(e).font(.system(size: 14)).foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
