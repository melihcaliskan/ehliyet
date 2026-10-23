import SwiftUI

// MARK: - Harç ve ücretler

struct FeesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("licenseClass") private var licenseClass = "B"
    @State private var includeCourse = true
    @State private var classes = ["A1", "A2", "A", "B", "BE", "C", "D"]
    @State private var table: FeeTable?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Harç ve Ücretler").font(.system(size: 34, weight: .bold)).padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tahmini toplam maliyet · \(licenseClass) sınıfı")
                        .font(.system(size: 13, weight: .semibold)).opacity(0.9)
                    Text(table?.totalKurus.lira ?? "—")
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .redacted(reason: table == nil ? .placeholder : [])
                    Text("\(validFromText) tarifesi · sınav tekrarları hariç")
                        .font(.system(size: 13)).opacity(0.9)
                    if table?.isEstimate == true {
                        Label("\(licenseClass) sınıfı harcı tahmini, resmi tarifeyle doğrulanmadı", systemImage: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.top, 4)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 18)
                .background(Palette.tint.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                Card {
                    Toggle("Sürücü kursu ücretini dahil et", isOn: $includeCourse.animation())
                        .padding(.horizontal, 18).frame(minHeight: 50)
                }

                if let error {
                    ContentUnavailableView {
                        Label("Ücretler yüklenemedi", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Tekrar Dene") { Task { await load() } }
                    }
                }

                ForEach(table?.sections ?? []) { section in
                    if !section.items.isEmpty { feeSection(section) }
                }

                if let table {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(table.note)
                        if !table.sources.isEmpty { Text("Kaynak: " + table.sources.joined(separator: ", ")) }
                    }
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await load() }
        .task(id: "\(licenseClass)|\(includeCourse)") { await load() }
        .task {
            let res: [String: [String]]? = try? await APIClient.shared.get("/v1/fees/classes")
            if let c = res?["classes"], !c.isEmpty { classes = c }
        }
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: {
                Menu {
                    Picker("Ehliyet sınıfı", selection: $licenseClass) {
                        ForEach(classes, id: \.self) { Text("\($0) Sınıfı").tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(licenseClass) Sınıfı")
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    .padding(.horizontal, 16).frame(height: 46)
                }
                .glass(Capsule(), interactive: true)
                .accessibilityLabel("Ehliyet sınıfı: \(licenseClass)")
            }
        }
    }

    private var validFromText: String {
        guard let s = table?.validFrom, let d = ISO8601DateFormatter.day.date(from: s) else { return "Güncel" }
        return d.formatted(.dateTime.month(.wide).year().locale(.tr))
    }

    private func load() async {
        do {
            let t: FeeTable = try await APIClient.shared.get("/v1/fees", query: ["class": licenseClass, "includeCourse": includeCourse ? "true" : "false"])
            withAnimation { table = t; error = nil }
        } catch {
            if table == nil { self.error = error.localizedDescription }
        }
    }

    private func feeSection(_ section: FeeTable.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: section.title, trailing: section.subtotalKurus.lira)
            Card(padding: .init(top: 2, leading: 18, bottom: 2, trailing: 18)) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { i, f in
                    HStack {
                        Text(f.title)
                        if f.isEstimate {
                            Text("tahmini").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Palette.orange.opacity(0.12), in: Capsule())
                        }
                        Spacer()
                        Text(f.amountKurus.lira).monospacedDigit()
                    }
                    .font(.system(size: 16))
                    .frame(minHeight: 46)
                    if i < section.items.count - 1 { Divider() }
                }
            }
        }
    }
}

extension ISO8601DateFormatter {
    /// "2026-11-12"
    static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}

// MARK: - Sınav takvimi

struct CalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))!
    @State private var selectedDay: Date?
    @State private var sessions: [ExamSession] = []
    @State private var info: CalendarInfo?
    @State private var appointments: [Appointment] = []
    @State private var editing: AppointmentDraft?

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = .tr
        return c
    }
    private var monthKey: String { String(ISO8601DateFormatter.day.string(from: month).prefix(7)) }
    private var monthAppointments: [Appointment] { appointments.filter { cal.isDate($0.startsAt, equalTo: month, toGranularity: .month) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sınav Takvimi").font(.system(size: 34, weight: .bold)).padding(.horizontal, 4)
                monthCard
                legend

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Randevularım")
                    Card {
                        if !auth.isSignedIn {
                            Button("Randevularını kaydetmek için giriş yap") { auth.showLogin = true }
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                        } else if appointments.isEmpty {
                            Button { editing = .init(date: selectedDay ?? .now) } label: {
                                Label("İlk randevunu ekle", systemImage: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 56)
                            }
                        }
                        ForEach(Array(appointments.enumerated()), id: \.element.id) { i, a in
                            Button { editing = .init(a) } label: { appointmentRow(a) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Sil", systemImage: "trash", role: .destructive) { Task { await delete(a) } }
                                }
                            if i < appointments.count - 1 { RowDivider(leading: 34) }
                        }
                    }
                }

                let monthSessions = sessions
                if !monthSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Bu ayki duyurular")
                        Card {
                            ForEach(Array(monthSessions.enumerated()), id: \.element.id) { i, s in
                                HStack {
                                    Text(s.title).font(.system(size: 16))
                                    Spacer()
                                    Text(dayText(s.date)).font(.system(size: 15)).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 18).frame(minHeight: 46)
                                if i < monthSessions.count - 1 { RowDivider(leading: 18) }
                            }
                        }
                    }
                }

                if let info {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Sınavlar nasıl planlanır?")
                        Card(padding: .init(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                            infoRow("desktopcomputer", Palette.tint, "E-Sınav", info.eSinav)
                            Divider()
                            infoRow("steeringwheel", Palette.orange, "Direksiyon", info.direksiyon)
                        }
                        Text("Kaynak: \(info.source)").font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                }
                TabBarSpacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: {
                GlassIconButton(systemName: "plus", label: "Randevu ekle") {
                    if auth.isSignedIn { editing = .init(date: selectedDay ?? .now) } else { auth.showLogin = true }
                }
            }
        }
        .task(id: monthKey) {
            let res: SessionsResponse? = try? await APIClient.shared.get("/v1/calendar/sessions", query: ["month": monthKey])
            sessions = res?.sessions ?? []
            info = res?.info
        }
        .task(id: auth.isSignedIn) { await loadAppointments() }
        .sheet(item: $editing) { draft in
            AppointmentEditor(draft: draft) { await loadAppointments() }
                .presentationDetents([.medium, .large])
        }
    }

    private func loadAppointments() async {
        guard auth.isSignedIn else { appointments = []; return }
        let res: [String: [Appointment]]? = try? await APIClient.shared.get("/v1/calendar/appointments")
        appointments = res?["appointments"] ?? []
    }

    private func delete(_ a: Appointment) async {
        try? await APIClient.shared.send("DELETE", "/v1/calendar/appointments/\(a.id)")
        await loadAppointments()
    }

    private func appointmentRow(_ a: Appointment) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(a.color).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(.system(size: 16, weight: .semibold))
                Text([a.startsAt.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(.tr)),
                      a.startsAt.formatted(date: .omitted, time: .shortened),
                      a.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(daysLeft(a.startsAt)).font(.system(size: 13, weight: .semibold)).foregroundStyle(a.color)
        }
        .padding(.horizontal, 18).frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private func infoRow(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(Palette.tint, "E-Sınav")
            legendItem(Palette.orange, "Direksiyon")
            legendItem(Color(.systemGray3), "Duyuru")
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 10, height: 10); Text(label) }
    }

    private func daysLeft(_ d: Date) -> String {
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: d)).day ?? 0
        return n > 0 ? "\(n) gün" : n == 0 ? "Bugün" : "Geçti"
    }

    private func dayText(_ ymd: String) -> String {
        ISO8601DateFormatter.day.date(from: ymd)?.formatted(.dateTime.day().month(.wide).weekday(.abbreviated).locale(.tr)) ?? ymd
    }

    private var monthCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year().locale(.tr)))
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Önceki ay")
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Sonraki ay")
            }
            .font(.system(size: 17, weight: .semibold))

            let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(["PZT", "SAL", "ÇAR", "PER", "CUM", "CMT", "PAZ"], id: \.self) {
                    Text($0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func dayCell(_ day: Date) -> some View {
        let appt = monthAppointments.first { cal.isDate($0.startsAt, inSameDayAs: day) }
        let hasSession = sessions.contains { $0.date == ISO8601DateFormatter.day.string(from: day) }
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let isToday = cal.isDateInToday(day)
        return Button { selectedDay = day } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 17, weight: appt != nil || isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(appt != nil ? .white : isToday ? Palette.red : .primary)
                .frame(width: 40, height: 40)
                .background {
                    if let appt { Circle().fill(appt.color) }
                    else if isSelected { Circle().fill(Color(.tertiarySystemFill)) }
                    else if hasSession { Circle().strokeBorder(Color(.systemGray3), lineWidth: 1.5) }
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(day.formatted(.dateTime.day().month(.wide).locale(.tr)) + (appt.map { ", \($0.title)" } ?? "") + (hasSession ? ", sınav günü" : ""))
    }

    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func shift(_ v: Int) {
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: v, to: month)! }
    }
}

// MARK: - Randevu ekle / düzenle (tasarımda yoktu, eklendi)

struct AppointmentDraft: Identifiable {
    var id: String?
    var kind = "e_sinav"
    var date: Date
    var location = ""

    init(date: Date) {
        let start = Calendar.current.startOfDay(for: date)
        self.date = Calendar.current.date(byAdding: .hour, value: 10, to: start) ?? date
    }
    init(_ a: Appointment) {
        id = a.id; kind = a.kind; date = a.startsAt; location = a.location ?? ""
    }
}

struct AppointmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: AppointmentDraft
    let onSaved: () async -> Void
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Sınav", selection: $draft.kind) {
                    Text("E-Sınav (Teorik)").tag("e_sinav")
                    Text("Direksiyon Sınavı").tag("direksiyon")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                DatePicker("Tarih ve saat", selection: $draft.date)
                    .environment(\.locale, .tr)
                TextField("Sınav merkezi / alanı (isteğe bağlı)", text: $draft.location)
                if let error { Text(error).foregroundStyle(Palette.red) }
                if draft.id != nil {
                    Button("Randevuyu Sil", role: .destructive) { Task { await delete() } }
                }
            }
            .navigationTitle(draft.id == nil ? "Randevu Ekle" : "Randevu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await save() } }.disabled(saving)
                }
            }
        }
    }

    private func save() async {
        struct Body: Encodable { let kind: String; let title: String; let startsAt: String; let location: String? }
        saving = true
        defer { saving = false }
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        let body = Body(kind: draft.kind,
                        title: draft.kind == "e_sinav" ? "E-Sınav (Teorik)" : "Direksiyon Sınavı",
                        startsAt: f.string(from: draft.date),
                        location: draft.location.isEmpty ? nil : draft.location)
        do {
            if let id = draft.id {
                try await APIClient.shared.send("PATCH", "/v1/calendar/appointments/\(id)", body: body)
            } else {
                try await APIClient.shared.send("POST", "/v1/calendar/appointments", body: body)
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let id = draft.id else { return }
        try? await APIClient.shared.send("DELETE", "/v1/calendar/appointments/\(id)")
        await onSaved()
        dismiss()
    }
}

// MARK: - Bildirimler

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @State private var items: [AppNotification]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bildirimler").font(.system(size: 34, weight: .bold)).padding(.horizontal, 4)
                if !auth.isSignedIn {
                    ContentUnavailableView {
                        Label("Giriş yap", systemImage: "bell")
                    } description: {
                        Text("Sınav hatırlatmaları ve sonuçların burada görünür.")
                    } actions: {
                        Button("Giriş Yap") { auth.showLogin = true }.buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                } else if let items {
                    if items.isEmpty {
                        ContentUnavailableView("Yeni bildirim yok", systemImage: "bell.slash").padding(.top, 60)
                    } else {
                        Card {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, n in
                                HStack(alignment: .top, spacing: 12) {
                                    IconTile(systemName: n.icon, color: Color(hex: n.color), size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(n.title).font(.system(size: 16, weight: .semibold))
                                            Spacer()
                                            Text(n.date.formatted(.relative(presentation: .named).locale(.tr)))
                                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                        }
                                        Text(n.body).font(.system(size: 15)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                if i < items.count - 1 { RowDivider(leading: 66) }
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: { EmptyView() }
        }
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn else { return }
            let res: [String: [AppNotification]]? = try? await APIClient.shared.get("/v1/notifications")
            items = res?["notifications"] ?? []
        }
    }
}

// MARK: - Profil

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(PurchaseStore.self) private var store
    @Environment(ContentStore.self) private var content
    @State private var confirmDelete = false
    @AppStorage("dailyReminder") private var dailyReminder = true
    @AppStorage("haptics") private var haptics = true

    var body: some View {
        @Bindable var state = state
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text(String((auth.user?.name ?? auth.user?.email ?? "?").prefix(1)).uppercased(with: .tr))
                        .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Palette.tint.gradient, in: Circle())
                    Text(auth.user?.name ?? auth.user?.email ?? "Misafir").font(.system(size: 22, weight: .bold))
                    Text(state.isPremium ? "Premium üye" : "Ücretsiz plan")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if !state.isPremium {
                    Button { state.showPaywall = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill").font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Ehliyet Premium").font(.system(size: 17, weight: .semibold))
                                Text("Sınırsız deneme, tüm videolar").font(.system(size: 13)).opacity(0.9)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Palette.tint.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }

                Card {
                    toggleRow("bell.badge.fill", Palette.red, "Günlük hatırlatıcı", $dailyReminder)
                        .onChange(of: dailyReminder) { _, on in
                            Task {
                                if on, await DailyReminder.requestPermission() { await content.loadStudyStatus(); await content.loadNextAppointment() }
                                else if !on { DailyReminder.cancelAll() }
                            }
                        }
                    RowDivider()
                    toggleRow("iphone.radiowaves.left.and.right", Palette.indigo, "Titreşim", $haptics)
                }
                Card {
                    NavRow(icon: "calendar", color: Palette.red, title: "Sınav Takvimi") { state.push(.calendar) }
                    RowDivider()
                    NavRow(icon: "arrow.clockwise", color: Palette.green, title: "Satın Alımları Geri Yükle") { Task { await store.restore() } }
                    RowDivider()
                    NavRow(icon: "questionmark.circle.fill", color: Color(.systemGray), title: "Yardım ve Destek") {}
                }
                Card {
                    if auth.isSignedIn {
                        Button("Çıkış Yap") { DailyReminder.cancelAll(); Task { await auth.logout() } }
                            .frame(maxWidth: .infinity, minHeight: 50)
                        RowDivider(leading: 0)
                        Button("Hesabı Sil", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity, minHeight: 50)
                    } else {
                        Button("Giriş Yap veya Kayıt Ol") { auth.showLogin = true }
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                #if DEBUG
                Card {
                    Toggle("Premium (geliştirici)", isOn: $state.isPremium)
                        .padding(.horizontal, 18).frame(minHeight: 50)
                }
                #endif
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
        .confirmationDialog("Hesabın silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Hesabı Kalıcı Olarak Sil", role: .destructive) { Task { try? await auth.deleteAccount() } }
        } message: {
            Text("Tüm ilerlemen silinir. Aktif aboneliğin varsa Ayarlar > Apple Hesabı > Abonelikler'den ayrıca iptal etmelisin.")
        }
    }

    private func toggleRow(_ icon: String, _ color: Color, _ title: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, color: color)
            Toggle(title, isOn: binding).font(.system(size: 17))
        }
        .padding(.horizontal, 18).frame(minHeight: 52)
    }
}
