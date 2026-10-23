import SwiftUI

// MARK: - Model (GET /v1/rules)

struct ExamRules: Decodable {
    struct Right: Decodable, Identifiable {
        let id: String
        let title: String
        let value: String
        let total: Int
        let remaining: Int
        let detail: String
    }
    struct Step: Decodable {
        let title: String
        let detail: String
    }
    struct Section: Decodable, Identifiable {
        let id: String
        let title: String
        let steps: [Step]
    }
    struct Fact: Decodable {
        let icon: String
        let warning: Bool
        let text: String
    }

    let updatedAt: String
    let rights: [Right]
    let sections: [Section]
    let facts: [Fact]
    let note: String

    /// Sunucuya ulaşılamazsa gösterilen gömülü içerik
    static let fallback = ExamRules(
        updatedAt: "2026-10-23",
        rights: [
            .init(id: "e_sinav", title: "E-SINAV", value: "4", total: 4, remaining: 4, detail: "50 soru · 45 dk\nGeçme: 70 puan"),
            .init(id: "direksiyon", title: "DİREKSİYON", value: "4+4", total: 4, remaining: 3, detail: "40 dk · Geçme: 70 puan\nİkinci 4 hak nakille"),
        ],
        sections: [
            .init(id: "e_sinav", title: "E-Sınav adım adım", steps: [
                .init(title: "Erken git", detail: "Kimlik kartınla sınav saatinden önce sınav merkezinde ol."),
                .init(title: "Eşyalarını bırak", detail: "Telefon, akıllı saat ve çantanı salona sokma."),
                .init(title: "50 soruyu çöz", detail: "45 dakikan var. Cevaplarını bilgisayar ekranında işaretle."),
                .init(title: "Sonucunu öğren", detail: "100 üzerinden en az 70 puan alırsan direksiyon sınavına geçersin."),
            ]),
            .init(id: "direksiyon", title: "Direksiyon sınavı adım adım", steps: [
                .init(title: "Araç bilgisi soruları", detail: "Sınav, aracın donanımıyla ilgili sorularla başlar."),
                .init(title: "Hazırlan ve kalk", detail: "Koltuğu, aynaları ve kemeri ayarla. Aracı çalıştırıp güvenle hareket et."),
                .init(title: "Güzergahta sür", detail: "Onaylı güzergahta hız sınırına, işaretlere ve geçiş hakkına uy."),
                .init(title: "Manevralar", detail: "En az 25 m geri git, 30 km/s'de ani duruş yap, 90° geri dönüş yap."),
                .init(title: "Geri park", detail: "Dubaların arasına yola paralel olarak geri geri park et."),
                .init(title: "Değerlendirme", detail: "Sınav yaklaşık 40 dakika sürer. 100 üzerinden en az 70 puan gerekir."),
            ]),
        ],
        facts: [
            .init(icon: "retry", warning: false, text: "Geri parkta dubaların arasından tek hamlede geçemezsen aynı hamleyi **bir kez daha** deneyebilirsin."),
            .init(icon: "transfer", warning: false, text: "İlk 4 direksiyon hakkın biterse başka bir kursa nakil olarak **4 hak daha** kullanabilirsin."),
            .init(icon: "calendar", warning: false, text: "Direksiyondan kalıp **3 yıl içinde** yeniden kayıt olursan teorik eğitimi ve e-sınavı tekrar etmezsin."),
            .init(icon: "alert", warning: false, text: "Komisyon aracı güvenle kullanamayacağına karar verirse sınav **erken bitirilebilir**."),
            .init(icon: "ban", warning: true, text: "Başkasının yerine sınava giren ya da girmeye çalışan **5 yıl** boyunca sınavlara alınmaz."),
        ],
        note: "Kurallar MEB yönetmeliğine göre değişebilir."
    )
}

// MARK: - Sınav kuralları

struct RulesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var rules = ExamRules.fallback

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sınav Kuralları").font(.system(size: 34, weight: .bold))
                    Text("Sınav günü ne olacağını adım adım öğren.")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    ForEach(rules.rights) { rightCard($0) }
                }

                ForEach(rules.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.system(size: 20, weight: .bold)).padding(.horizontal, 16)
                        Card(padding: .init(top: 6, leading: 18, bottom: 6, trailing: 18)) {
                            ForEach(Array(section.steps.enumerated()), id: \.offset) { i, step in
                                stepRow(i + 1, step, color: color(for: section.id))
                                if i < section.steps.count - 1 { Divider() }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bilmen gereken kurallar").font(.system(size: 20, weight: .bold)).padding(.horizontal, 16)
                    Card(padding: .init(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                        ForEach(Array(rules.facts.enumerated()), id: \.offset) { i, fact in
                            factRow(fact)
                            if i < rules.facts.count - 1 { Divider() }
                        }
                    }
                    Text("\(rules.note) Son kontrol: \(updatedText)")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 110)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "chevron.left", label: "Geri") { dismiss() }
            } trailing: {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glass(Circle(), interactive: true)
                .accessibilityLabel("Kuralları paylaş")
            }
        }
        .overlay(alignment: .bottom) {
            PrimaryButton(title: "Deneme Sınavına Başla") {
                state.push(.exam(ExamRequest(kind: .mock)))
            }
            .shadow(color: Palette.tint.opacity(0.35), radius: 14, y: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .task {
            if let fresh: ExamRules = try? await APIClient.shared.send("GET", "/v1/rules", auth: false) {
                rules = fresh
            }
        }
    }

    private func color(for id: String) -> Color { id == "direksiyon" ? Palette.orange : Palette.tint }

    private var updatedText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: rules.updatedAt) else { return rules.updatedAt }
        return d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR")))
    }

    private var shareText: String {
        var lines = ["Ehliyet Sınav Kuralları"]
        for s in rules.sections {
            lines.append("\n\(s.title)")
            for (i, step) in s.steps.enumerated() { lines.append("\(i + 1). \(step.title): \(step.detail)") }
        }
        lines.append("\nBilmen gereken kurallar")
        lines += rules.facts.map { "• " + $0.text.replacingOccurrences(of: "**", with: "") }
        return lines.joined(separator: "\n")
    }

    private func rightCard(_ r: ExamRules.Right) -> some View {
        let c = color(for: r.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text(r.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(c)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(r.value).font(.system(size: 40, weight: .bold)).tracking(-1.2)
                Text("hak").font(.system(size: 15, weight: .semibold))
            }
            HStack(spacing: 4) {
                ForEach(0..<r.total, id: \.self) { i in
                    Capsule().fill(i >= r.total - r.remaining ? c : Color(.systemGray5)).frame(height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Kalan hak: \(r.remaining) / \(r.total)")
            Text(r.detail).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func stepRow(_ n: Int, _ step: ExamRules.Step, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.system(size: 16, weight: .semibold))
                Text(step.detail).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func factRow(_ fact: ExamRules.Fact) -> some View {
        let symbol = switch fact.icon {
        case "retry": "arrow.counterclockwise"
        case "transfer": "arrow.left.arrow.right"
        case "calendar": "calendar"
        case "ban": "nosign"
        default: "exclamationmark.circle"
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(fact.warning ? Palette.orange : Palette.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text((try? AttributedString(markdown: fact.text)) ?? AttributedString(fact.text))
                .font(.system(size: 15))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}
