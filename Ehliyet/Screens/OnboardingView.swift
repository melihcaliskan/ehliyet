import SwiftUI
import StoreKit

/// İlk açılış: en fazla 3 dokunuş. Ehliyet sınıfı ve sınav zamanını sorar,
/// sınav zamanına göre uygun Premium planını önerir. Her adımda atlanabilir.
struct OnboardingView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(PurchaseStore.self) private var store
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("licenseClass") private var licenseClass = "B"
    @AppStorage("examTiming") private var timing = ""

    @State private var step = 0

    enum Timing: String, CaseIterable {
        case month = "1 ay içinde", soon = "1–3 ay", later = "3 aydan sonra", unknown = "Belli değil"
        /// Yakın sınavda tek seferlik 6 aylık paket aylık abonelikten daha mantıklı
        var recommended: String { self == .later || self == .unknown ? ProductID.monthly : ProductID.sixMonths }
    }

    var body: some View {
        @Bindable var auth = auth
        ZStack {
            LinearGradient(colors: [Color(red: 0.0, green: 0.3, blue: 0.7), Color(red: 0.03, green: 0.12, blue: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle().fill(Color(red: 0.3, green: 0.6, blue: 1).opacity(0.45)).frame(width: 320).blur(radius: 90).offset(x: 130, y: -320)

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Capsule().fill(.white.opacity(i <= step ? 1 : 0.3)).frame(width: i == step ? 22 : 8, height: 8)
                        }
                    }
                    .animation(.spring(duration: 0.35), value: step)
                    .accessibilityLabel("Adım \(step + 1) / 3")
                    Spacer()
                    Button(step == 2 ? "Şimdilik geç" : "Atla") { finish() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                        .glass(Capsule(), interactive: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: questions
                    default: offer
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $auth.showLogin) {
            LoginView(reason: "Satın alımın hesabına bağlansın diye önce giriş yap.")
                .preferredColorScheme(nil)
        }
        .task { await store.loadProducts() }
    }

    private func next() { withAnimation(.snappy) { step += 1 } }
    private func finish() {
        Analytics.track("onboarding_finish", ["step": step, "class": licenseClass, "timing": timing])
        onboarded = true
    }

    // MARK: 1 · Karşılama

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "car.fill")
                .font(.system(size: 44)).foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(spacing: 8) {
                Text("Ehliyetini ilk seferde al").font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
                Text("E-sınav ve direksiyon için ihtiyacın olan her şey tek yerde.")
                    .font(.system(size: 17)).opacity(0.85).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                benefit("checklist", "Gerçek formatta deneme sınavları")
                benefit("play.rectangle.fill", "Ders ve direksiyon videoları")
                benefit("map.fill", "İline göre sınav güzergahları")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
            Spacer()
            whiteButton("Başla", action: next)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 28)
            Text(text).font(.system(size: 17, weight: .medium))
        }
    }

    // MARK: 2 · İki soru

    private var questions: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("Hangi ehliyeti alıyorsun?").font(.system(size: 22, weight: .bold))
                HStack(spacing: 8) {
                    ForEach(["A2", "B", "C", "D"], id: \.self) { c in
                        chip(c, selected: licenseClass == c) { licenseClass = c }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("E-sınavın ne zaman?").font(.system(size: 22, weight: .bold))
                LazyVGrid(columns: [.init(.flexible(), spacing: 8), .init(.flexible())], spacing: 8) {
                    ForEach(Timing.allCases, id: \.self) { t in
                        chip(t.rawValue, selected: timing == t.rawValue) { timing = t.rawValue }
                    }
                }
            }
            Spacer()
            whiteButton("Devam", action: next)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Palette.ink : .white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background { if selected { Capsule().fill(.white) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), interactive: true)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 3 · Premium teklifi

    private var recommendedID: String { (Timing(rawValue: timing) ?? .unknown).recommended }
    private var recommended: Product? { store.product(recommendedID) }

    private var offer: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "star.fill")
                .font(.system(size: 34)).foregroundStyle(Palette.gold)
                .frame(width: 80, height: 80)
                .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(spacing: 8) {
                Text("Sınava Premium ile hazırlan").font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center)
                Text(offerSubtitle).font(.system(size: 16)).opacity(0.85).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                PerkRow(text: "Sınırsız deneme sınavı")
                PerkRow(text: "Yanlışlarına özel tekrar testleri")
                PerkRow(text: "Tüm videolar ve güzergahlar")
            }
            .tint(Palette.gold)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if let p = recommended {
                VStack(spacing: 2) {
                    Text(p.displayName).font(.system(size: 17, weight: .semibold))
                    Text(recommendedID == ProductID.monthly ? "\(p.displayPrice) / ay · istediğin zaman iptal et" : "\(p.displayPrice) · tek seferlik, yenilenmez")
                        .font(.system(size: 14)).opacity(0.8)
                }
            }
            if let error = store.lastError {
                Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.gold).multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                whiteButton(store.isPurchasing ? "Bekleyin…" : (auth.isSignedIn ? "Premium'u Başlat" : "Giriş Yap ve Başlat")) {
                    guard let p = recommended else { return }
                    Task { if await store.purchase(p) { finish() } }
                }
                .disabled(recommended == nil || store.isPurchasing)
                Button("Ücretsiz devam et") { finish() }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    .frame(minHeight: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var offerSubtitle: String {
        switch Timing(rawValue: timing) {
        case .month, .soon: "Sınavın yakın. Tek seferlik paketle sınava kadar her şey açık."
        default: "3 ücretsiz deneme hakkın var. Daha fazlası için Premium'a geç."
        }
    }

    private func whiteButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
