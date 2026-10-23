import SwiftUI

// MARK: - Premium satın alma

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(PurchaseStore.self) private var store

    enum Plan: String, CaseIterable, Identifiable {
        case monthly, untilExam, videos
        var id: String { rawValue }
        var productID: String {
            switch self {
            case .monthly: ProductID.monthly
            case .untilExam: ProductID.sixMonths
            case .videos: ProductID.videos
            }
        }
        var title: String {
            switch self {
            case .monthly: "Aylık"
            case .untilExam: "Sınava Kadar · 6 Ay"
            case .videos: "Sadece Videolar"
            }
        }
        var subtitle: String {
            switch self {
            case .monthly: "Her ay yenilenir"
            case .untilExam: "Tek seferlik ödeme, yenilenmez"
            case .videos: "Tek seferlik ders paketi"
            }
        }
    }

    @State private var plan: Plan = .untilExam

    private func price(_ p: Plan) -> String {
        guard let product = store.product(p.productID) else { return "—" }
        return p == .monthly ? "\(product.displayPrice)/ay" : product.displayPrice
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.0, green: 0.3, blue: 0.7), Color(red: 0.03, green: 0.12, blue: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle().fill(Color(red: 0.3, green: 0.6, blue: 1).opacity(0.5)).frame(width: 300).blur(radius: 80).offset(x: 120, y: -300)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 34)).foregroundStyle(Palette.gold)
                            .frame(width: 80, height: 80)
                            .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        Text("Ehliyet Premium").font(.system(size: 30, weight: .bold))
                        Text("Sınava kadar her şeye sınırsız eriş.").font(.system(size: 17)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 40)

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                        perk("infinity", "Sınırsız deneme")
                        perk("play.rectangle.fill", "Tüm videolar")
                        perk("map.fill", "Tüm güzergahlar")
                        perk("nosign", "Reklamsız")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Plan seç").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                        ForEach(Plan.allCases) { p in planRow(p) }
                    }
                    Color.clear.frame(height: 150)
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .top) {
            GlassTopBar {
                GlassIconButton(systemName: "xmark", label: "Kapat", foreground: .white) { dismiss() }
            } trailing: {
                Button("Geri Yükle") { Task { await store.restore(); if state.isPremium { dismiss() } } }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 46)
                    .glass(Capsule(), interactive: true)
            }
            .padding(.top, 12)
        }
        .overlay(alignment: .bottom) { footer }
        .preferredColorScheme(.dark)
        .task { await store.loadProducts() }
    }

    private func perk(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 22)
            Text(text).font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).frame(height: 52)
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func planRow(_ p: Plan) -> some View {
        let selected = plan == p
        return Button { withAnimation(.spring(duration: 0.3)) { plan = p } } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? Palette.gold : .white.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.system(size: 17, weight: .semibold))
                    Text(p.subtitle).font(.system(size: 13)).opacity(0.75)
                }
                Spacer()
                Text(price(p)).font(.system(size: 16, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).frame(minHeight: 72)
            .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(selected ? Palette.gold : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if p == .untilExam {
                    Text("EN POPÜLER")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Palette.gold, in: Capsule())
                        .offset(x: -16, y: -10)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = store.lastError ?? store.loadError {
                Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.gold)
                    .multilineTextAlignment(.center)
            }
            Button {
                guard let product = store.product(plan.productID) else { return }
                Task { if await store.purchase(product) { dismiss() } }
            } label: {
                ZStack {
                    if store.isPurchasing { ProgressView().tint(.black) }
                    else { Text(auth.isSignedIn ? "Devam Et" : "Giriş Yap ve Devam Et") }
                }
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(store.isPurchasing || store.product(plan.productID) == nil)

            Text(plan == .monthly
                 ? "Aylık plan, iptal edilmedikçe her ay otomatik yenilenir. Ayarlar > Apple Hesabı > Abonelikler'den istediğin zaman iptal edebilirsin."
                 : "Tek seferlik ödeme. Otomatik yenileme yoktur.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Kullanım Koşulları", destination: URL(string: "https://ehliyet-api.melihcaliskan.com/legal/terms")!)
                Link("Gizlilik", destination: URL(string: "https://ehliyet-api.melihcaliskan.com/legal/privacy")!)
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 12)
    }
}

// MARK: - Arama

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var results: SearchResults?
    @State private var searching = false
    @FocusState private var focused: Bool

    struct SearchResults: Decodable {
        struct L: Decodable, Identifiable { let id: String; let kind: String; let title: String; let chapter: String; let isPremium: Bool }
        struct Q: Decodable, Identifiable { let id: String; let topicId: String; let topic: String; let text: String }
        let lessons: [L]
        let questions: [Q]
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if trimmed.count < 2 {
                    SectionHeader(title: "Popüler aramalar")
                    FlowChips(items: ["Kavşak", "İlk yardım", "Park", "Hız sınırı", "Sollama"]) { query = $0 }
                } else if let results {
                    if !results.lessons.isEmpty {
                        SectionHeader(title: "Dersler")
                        Card {
                            ForEach(Array(results.lessons.enumerated()), id: \.element.id) { i, l in
                                let locked = l.isPremium && !(state.isPremium || state.hasVideos)
                                NavRow(icon: locked ? "lock.fill" : "play.fill", color: locked ? Color(.systemGray) : Palette.red, title: l.title) {
                                    dismiss()
                                    if locked { state.showPaywall = true } else { state.selectedTab = .lessons }
                                }
                                if i < results.lessons.count - 1 { RowDivider() }
                            }
                        }
                    }
                    if !results.questions.isEmpty {
                        SectionHeader(title: "Sorular")
                        Card {
                            ForEach(Array(results.questions.enumerated()), id: \.element.id) { i, q in
                                Button {
                                    dismiss()
                                    state.selectedTab = .questions
                                    state.questionsPath.append(Route.exam(.init(kind: .topic, topicId: q.topicId, title: q.topic)))
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(q.topic).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tint)
                                        Text(q.text).font(.system(size: 16)).lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 18).padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if i < results.questions.count - 1 { RowDivider(leading: 18) }
                            }
                        }
                    }
                    if results.lessons.isEmpty && results.questions.isEmpty {
                        ContentUnavailableView.search(text: trimmed).padding(.top, 60)
                    }
                } else if searching {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Soru, ders veya konu ara", text: $query)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("Temizle")
                    }
                }
                .padding(.horizontal, 16).frame(height: 48)
                .glass(Capsule())
                GlassIconButton(systemName: "xmark", label: "Kapat", size: 48) { dismiss() }
            }
            .padding(.horizontal, 16)
        }
        .onAppear { focused = true }
        // Yazmayı bitirince ara (300 ms bekleme)
        .task(id: trimmed) {
            guard trimmed.count >= 2 else { results = nil; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            if let r: SearchResults = try? await APIClient.shared.get("/v1/search", query: ["q": trimmed]), !Task.isCancelled {
                results = r
            }
        }
    }
}

struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) { onTap(item) }
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }
}
