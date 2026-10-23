import SwiftUI
import Observation

enum AppTab: Hashable, CaseIterable {
    case home, questions, lessons, routes

    var title: String {
        switch self {
        case .home: "Ana Sayfa"
        case .questions: "Sorular"
        case .lessons: "Dersler"
        case .routes: "Güzergah"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .questions: "checklist"
        case .lessons: "play.rectangle"
        case .routes: "map"
        }
    }
}

enum Route: Hashable {
    case exam(ExamRequest)
    case examResult(ExamSummary)
    case examHistory
    case examReview(String)
    case checklist
    case topicTests
    case wrongAnswers
    case fees
    case calendar
    case rules
    case notifications
    case profile
}


@Observable
final class AppState {
    var selectedTab: AppTab = .home
    var homePath = NavigationPath()
    var questionsPath = NavigationPath()
    var lessonsPath = NavigationPath()

    var isPremium = false
    var hasVideos = false
    var showPaywall = false
    var showSearch = false


    var userInitials = "AB"

    func push(_ route: Route) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .questions: questionsPath.append(route)
        case .lessons: lessonsPath.append(route)
        case .routes: homePath.append(route)
        }
    }

}
