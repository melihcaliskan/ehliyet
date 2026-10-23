import SwiftUI
import UIKit

@main
struct EhliyetApp: App {
    @State private var state = AppState()
    @State private var auth: AuthStore
    @State private var purchases: PurchaseStore
    @State private var content = ContentStore()

    init() {
        let auth = AuthStore()
        _auth = State(initialValue: auth)
        _purchases = State(initialValue: PurchaseStore(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(auth)
                .environment(purchases)
                .environment(content)
                .task {
                    purchases.start()
                    await auth.restore()
                    await purchases.loadProducts()
                }
                .tint(Palette.tint)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth
    @Environment(ContentStore.self) private var content
    @AppStorage("onboarded") private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var state = state
        @Bindable var auth = auth
        ZStack(alignment: .bottom) {
            Group {
                switch state.selectedTab {
                case .home:
                    NavigationStack(path: $state.homePath) {
                        HomeView().withRoutes()
                    }
                case .questions:
                    NavigationStack(path: $state.questionsPath) {
                        QuestionsHubView().withRoutes()
                    }
                case .lessons:
                    NavigationStack(path: $state.lessonsPath) {
                        LessonsView().withRoutes()
                    }
                case .routes:
                    NavigationStack {
                        RoutesMapView()
                    }
                }
            }

            if !isTabBarHidden {
                GlassTabBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: isTabBarHidden)
        .sheet(isPresented: $state.showPaywall) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $state.showSearch) {
            SearchView()
        }
        .fullScreenCover(isPresented: .constant(!onboarded)) {
            OnboardingView()
        }
        // Onboarding açıkken giriş sayfasını onboarding kendisi gösterir
        .sheet(isPresented: onboarded ? $auth.showLogin : .constant(false)) {
            LoginView(reason: state.showPaywall ? "Satın alımın hesabına bağlansın diye önce giriş yap." : nil)
        }
        // Haklar sunucudan gelir
        .onChange(of: auth.entitlements, initial: true) { _, ent in
            state.isPremium = ent.isPremium
            state.hasVideos = ent.scopes.contains("videos")
        }
        // Giriş/çıkış ya da satın alma sonrası kilitli içerik ve ilerleme yeniden yüklenir
        // Widget'tan gelen bağlantılar: ehliyet://daily, ehliyet://checklist
        .onOpenURL { url in
            Analytics.track("deep_link", ["host": url.host() ?? ""])
            state.selectedTab = .home
            state.homePath = NavigationPath()
            switch url.host() {
            case "daily": state.homePath.append(Route.exam(.init(kind: .daily, title: "Günün 10 Sorusu")))
            case "checklist": state.homePath.append(Route.checklist)
            default: break
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Analytics.shared.didBecomeActive()
            case .background: Analytics.shared.didEnterBackground()
            default: break
            }
        }
        .onChange(of: state.selectedTab) { _, tab in Analytics.track("tab_select", ["tab": tab.title]) }
        .onChange(of: state.showPaywall) { _, shown in if shown { Analytics.track("paywall_view") } }
        .task(id: "\(auth.user?.id.uuidString ?? "-")|\(auth.entitlements.scopes.sorted())") {
            await content.refresh(signedIn: auth.isSignedIn)
        }
    }

    /// Sınav ekranı gibi odak gerektiren yerlerde sekme çubuğu gizlenir
    private var isTabBarHidden: Bool {
        switch state.selectedTab {
        case .home: !state.homePath.isEmpty
        case .questions: !state.questionsPath.isEmpty
        case .lessons: !state.lessonsPath.isEmpty
        case .routes: false
        }
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .exam(let req): ExamView(request: req)
                case .examResult(let r): ExamResultView(result: r)
                case .examHistory: ExamHistoryView()
                case .examReview(let id): ExamReviewView(examId: id)
                case .checklist: ChecklistView()
                case .topicTests: TopicTestsView()
                case .wrongAnswers: WrongAnswersView()
                case .fees: FeesView()
                case .calendar: CalendarView()
                case .rules: RulesView()
                case .notifications: NotificationsView()
                case .profile: ProfileView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// Gizli navigation bar ile kenardan kaydırarak geri dönmeyi açık tut
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - Yüzen cam sekme çubuğu

struct GlassTabBar: View {
    @Environment(AppState.self) private var state
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    let selected = state.selectedTab == tab
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { state.selectedTab = tab }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: selected ? tab.icon + ".fill" : tab.icon)
                                .font(.system(size: 20, weight: .medium))
                                .frame(height: 26)
                            Text(tab.title)
                                .font(.system(size: 10, weight: selected ? .semibold : .medium))
                        }
                        .foregroundStyle(selected ? Palette.tint : Color.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selected {
                                Capsule().fill(Color.primary.opacity(0.08))
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .frame(height: 62)
            .glass(Capsule())

            Button { state.showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 62, height: 62)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glass(Circle(), interactive: true)
            .accessibilityLabel("Ara")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
