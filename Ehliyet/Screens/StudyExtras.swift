import SwiftUI

// MARK: - Hazırlık skoru

struct ReadinessCard: View {
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(ContentStore.self) private var content

    var body: some View {
        if let r = content.readiness {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color(.systemFill), lineWidth: 8)
                        Circle().trim(from: 0, to: Double(r.score) / 100)
                            .stroke(color(r), style: .init(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("%\(r.score)").font(.system(size: 20, weight: .bold).monospacedDigit())
                    }
                    .frame(width: 72, height: 72)
                    .accessibilityElement()
                    .accessibilityLabel("Hazırlık skoru yüzde \(r.score)")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sınava hazırlık").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Text(title(r)).font(.system(size: 19, weight: .bold))
                        Text(r.advice).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    metric("Deneme ort.", r.examAverage.map { "\($0)" } ?? "–")
                    metric("Konu kapsamı", "%\(r.coverage)")
                    metric("Sayılan deneme", "\(r.examsCounted)/3")
                }
                Button { state.push(.exam(.init(kind: .real, title: "Gerçek Sınav"))) } label: {
                    Label("Gerçek Sınav Modu", systemImage: "eye.slash")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Cevaplar sınav bitene kadar gösterilmez")
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func title(_ r: Readiness) -> String {
        switch r.level {
        case "high": "Sınava hazırsın"
        case "medium": "Yaklaştın"
        default: r.examsCounted == 0 ? "Henüz ölçülmedi" : "Biraz daha çalış"
        }
    }

    private func color(_ r: Readiness) -> Color {
        switch r.level { case "high": Palette.green; case "medium": Palette.tint; default: Palette.orange }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 16, weight: .bold).monospacedDigit())
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Günün 10 sorusu

struct DailyCard: View {
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(ContentStore.self) private var content

    var body: some View {
        let d = content.daily
        Button {
            if auth.isSignedIn { state.push(.exam(.init(kind: .daily, title: "Günün 10 Sorusu"))) } else { auth.showLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.58, blue: 0.0), Palette.orange], startPoint: .top, endPoint: .bottom))
                    Image(systemName: d?.completed == true ? "checkmark" : "flame.fill")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Günün 10 Sorusu").font(.system(size: 17, weight: .semibold))
                    Text(subtitle(d)).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if let d, d.streak > 0 {
                    VStack(spacing: 0) {
                        Text("\(d.streak)").font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(Palette.orange)
                        Text("gün").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(d.streak) günlük seri")
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func subtitle(_ d: DailyStatus?) -> String {
        guard let d else { return "Her gün 10 soru, 3 dakika" }
        if d.completed { return "Bugün tamam: \(d.correct ?? 0)/10 doğru. Yarın görüşürüz!" }
        if d.started { return "Yarım kaldı, devam et" }
        return d.streak > 0 ? "Serini koru · en iyi \(d.best) gün" : "Yanlışlarını tekrar ettiren 10 soru"
    }
}

struct StreakBadge: View {
    @Environment(ContentStore.self) private var content

    var body: some View {
        if let d = content.daily {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill").font(.system(size: 28)).foregroundStyle(Palette.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(d.streak) günlük seri").font(.system(size: 18, weight: .bold))
                    Text(d.streak >= d.best ? "En iyi serin bu!" : "En iyi serin \(d.best) gün").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Palette.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

// MARK: - Direksiyon kontrol listesi

struct ChecklistView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var checklist: Checklist?
    @AppStorage("checklistDone") private var doneRaw = ""

    private var done: Set<String> { Set(doneRaw.split(separator: ",").map(String.init)) }
    private var checkable: [Checklist.Item] { (checklist?.sections ?? []).filter { $0.warning != true }.flatMap(\.items) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Direksiyon Kontrol Listesi").font(.system(size: 30, weight: .bold))
                    Text("Sınav günü adım adım işaretle.").font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                if let checklist {
                    let count = checkable.filter { done.contains($0.id) }.count
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(count) / \(checkable.count) hazır").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            if count > 0 { Button("Sıfırla") { withAnimation { doneRaw = "" } }.font(.system(size: 15, weight: .semibold)) }
                        }
                        ProgressBar(value: checkable.isEmpty ? 0 : Double(count) / Double(checkable.count), tint: Palette.green)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    ForEach(checklist.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(section.title, systemImage: section.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(section.warning == true ? Palette.red : .primary)
                                .padding(.horizontal, 16)
                            Card {
                                ForEach(Array(section.items.enumerated()), id: \.element.id) { i, item in
                                    row(item, warning: section.warning == true)
                                    if i < section.items.count - 1 { RowDivider(leading: 56) }
                                }
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
        .task { checklist = try? await APIClient.shared.get("/v1/checklist") }
        .onAppear { Analytics.track("screen_view", ["screen": "checklist"]) }
    }

    @ViewBuilder
    private func row(_ item: Checklist.Item, warning: Bool) -> some View {
        let isDone = done.contains(item.id)
        Button {
            guard !warning else { return }
            var s = done
            if isDone { s.remove(item.id) } else { s.insert(item.id) }
            withAnimation(.snappy) { doneRaw = s.sorted().joined(separator: ",") }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: warning ? "xmark.octagon.fill" : isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(warning ? Palette.red : isDone ? Palette.green : Color(.tertiaryLabel))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 16, weight: .medium))
                        .strikethrough(isDone && !warning, color: .secondary)
                        .foregroundStyle(isDone && !warning ? .secondary : .primary)
                    if !item.detail.isEmpty {
                        Text(item.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}
