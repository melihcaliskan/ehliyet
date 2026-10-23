import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(ContentStore.self) private var content

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                examCard
                    .padding(.top, 70)
                DailyCard()
                nextAppointment
                ReadinessCard()
                studySection
                toolsSection
                progressSection
                TabBarSpacer()
            }
            .padding(.horizontal, 16)
        }
        .background(alignment: .top) {
            RoadHero()
                .frame(height: 320)
                .ignoresSafeArea(edges: .top)
        }
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
        .refreshable { await content.refresh(signedIn: auth.isSignedIn) }
        .onAppear {
            Analytics.track("screen_view", ["screen": "home"])
            if auth.isSignedIn { Task { await content.loadNextAppointment(); await content.loadStudyStatus() } }
        }
    }

    private var initials: String {
        let source = auth.user?.name ?? auth.user?.email ?? ""
        let parts = source.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "" : String(parts).uppercased(with: .tr)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.11, green: 0.23, blue: 0.37))
                Text("Ehliyet")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            HStack(spacing: 10) {
                GlassIconButton(systemName: "bell", label: "Bildirimler", size: 44, foreground: Palette.ink) {
                    state.push(.notifications)
                }
                Button { state.push(.profile) } label: {
                    Group {
                        if initials.isEmpty { Image(systemName: "person.fill") } else { Text(initials) }
                    }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glass(Circle(), interactive: true)
                .accessibilityLabel("Profil")
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private var examCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                IconTile(systemName: "stopwatch", color: Palette.tint, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("E-Sınav Provası").font(.system(size: 17, weight: .semibold))
                    Text("50 soru · 45 dk · Geçme notu 70")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if !state.isPremium, let remaining = content.remainingFreeExams {
                    Text("\(remaining) hak")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
            PrimaryButton(title: "Denemeye Başla") { state.push(.exam(.init(kind: .mock))) }
        }
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var nextAppointment: some View {
        if let next = content.nextAppointment {
            Button { state.push(.calendar) } label: {
                HStack(spacing: 14) {
                    VStack(spacing: 0) {
                        Text(next.startsAt.formatted(.dateTime.month(.abbreviated).locale(.tr)).uppercased(with: .tr))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.red)
                        Text(next.startsAt.formatted(.dateTime.day()))
                            .font(.system(size: 22, weight: .bold))
                    }
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(.system(size: 16, weight: .semibold))
                        Text(daysLeft(next.startsAt)).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func daysLeft(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        return days > 0 ? "\(days) gün kaldı" : "Bugün"
    }

    private var studySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Çalış")
            Card {
                NavRow(icon: "checklist", color: Palette.tint, title: "Çıkmış Sorular") { state.selectedTab = .questions }
                RowDivider()
                NavRow(icon: "list.bullet", color: Palette.indigo, title: "Konu Testleri") { state.push(.topicTests) }
                RowDivider()
                NavRow(icon: "play.fill", color: Palette.red, title: "Kurs Videoları") { state.selectedTab = .lessons }
                RowDivider()
                NavRow(icon: "point.topleft.down.to.point.bottomright.curvepath", color: Palette.green, title: "Sürüş Güzergahları") { state.selectedTab = .routes }
                RowDivider()
                NavRow(icon: "xmark", color: Palette.orange, title: "Yanlışlarım", value: "\(content.wrongCount)") { state.push(.wrongAnswers) }
                RowDivider()
                NavRow(icon: "clock.arrow.circlepath", color: Color(.systemTeal), title: "Sınav Geçmişi") { state.push(.examHistory) }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Başvuru")
            Card {
                NavRow(icon: "calendar", color: Palette.red, title: "Sınav Takvimi") { state.push(.calendar) }
                RowDivider()
                NavRow(icon: "list.number", color: Palette.indigo, title: "Sınav Kuralları") { state.push(.rules) }
                RowDivider()
                NavRow(icon: "checklist.checked", color: Palette.green, title: "Direksiyon Kontrol Listesi") { state.push(.checklist) }
                RowDivider()
                NavRow(icon: "turkishlirasign", color: Color(.systemGray), title: "Harç ve Ücretler") { state.push(.fees) }
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "İlerleme")
            Card(padding: .init(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                let shown = content.topics.prefix(auth.isSignedIn ? 4 : 2)
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, topic in
                    let progress = content.progress?.progress(for: topic.id) ?? 0
                    VStack(spacing: 6) {
                        HStack {
                            Text(topic.name)
                            Spacer()
                            Text("%\(progress.percent)").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 15))
                        ProgressBar(value: progress, tint: topic.tint)
                    }
                    .padding(.vertical, 10)
                    if i < shown.count - 1 { Divider() }
                }
                if content.topics.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 60) }
            }
        }
    }
}

struct NavRow: View {
    let icon: String
    let color: Color
    let title: String
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(systemName: icon, color: color)
                Text(title).font(.system(size: 17))
                Spacer()
                if let value { Text(value).font(.system(size: 17)).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Ana sayfa üst bölümündeki yol illüstrasyonu
struct RoadHero: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let sx = w / 390, sy = h / 300
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x * sx, y: y * sy) }

            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.74, green: 0.86, blue: 0.97), Color(red: 0.85, green: 0.92, blue: 0.98)]),
                                           startPoint: .zero, endPoint: p(0, 300)))
            ctx.fill(Path(ellipseIn: CGRect(x: 286 * sx, y: 36 * sy, width: 68 * sx, height: 68 * sx)),
                     with: .color(Color(red: 1, green: 0.91, blue: 0.64)))

            var hill1 = Path()
            hill1.move(to: p(0, 190)); hill1.addQuadCurve(to: p(190, 175), control: p(90, 140))
            hill1.addQuadCurve(to: p(390, 160), control: p(290, 210))
            hill1.addLine(to: p(390, 300)); hill1.addLine(to: p(0, 300)); hill1.closeSubpath()
            ctx.fill(hill1, with: .color(Color(red: 0.66, green: 0.83, blue: 0.60)))

            var hill2 = Path()
            hill2.move(to: p(0, 220)); hill2.addQuadCurve(to: p(230, 215), control: p(120, 190))
            hill2.addQuadCurve(to: p(390, 205), control: p(340, 240))
            hill2.addLine(to: p(390, 300)); hill2.addLine(to: p(0, 300)); hill2.closeSubpath()
            ctx.fill(hill2, with: .color(Color(red: 0.53, green: 0.75, blue: 0.47)))

            var road = Path()
            road.move(to: p(150, 300)); road.addLine(to: p(188, 168)); road.addLine(to: p(202, 168)); road.addLine(to: p(260, 300)); road.closeSubpath()
            ctx.fill(road, with: .color(Color(red: 0.35, green: 0.37, blue: 0.41)))

            var dash = Path()
            for (y1, y2, x) in [(176.0, 188.0, 195.0), (202, 220, 197.5), (238, 262, 200.5), (282, 300, 204)] {
                dash.move(to: p(x, y1)); dash.addLine(to: p(x + 1, y2))
            }
            ctx.stroke(dash, with: .color(Palette.gold), lineWidth: 3)

            var pole = Path(); pole.move(to: p(88, 150)); pole.addLine(to: p(88, 205))
            ctx.stroke(pole, with: .color(Color(red: 0.29, green: 0.31, blue: 0.35)), lineWidth: 3)
            let sign = CGRect(x: 74 * sx, y: 128 * sy, width: 28 * sx, height: 28 * sx)
            ctx.fill(Path(ellipseIn: sign), with: .color(Color(red: 0.11, green: 0.31, blue: 0.66)))
            ctx.stroke(Path(ellipseIn: sign), with: .color(.white), lineWidth: 3)
            var arrow = Path()
            arrow.move(to: CGPoint(x: sign.midX - 6, y: sign.midY)); arrow.addLine(to: CGPoint(x: sign.midX + 6, y: sign.midY))
            arrow.move(to: CGPoint(x: sign.midX + 1, y: sign.midY - 5)); arrow.addLine(to: CGPoint(x: sign.midX + 6, y: sign.midY)); arrow.addLine(to: CGPoint(x: sign.midX + 1, y: sign.midY + 5))
            ctx.stroke(arrow, with: .color(.white), style: .init(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Color(.systemGroupedBackground)], startPoint: .top, endPoint: .bottom)
                .frame(height: 60)
        }
        .accessibilityHidden(true)
    }
}
