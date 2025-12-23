import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case insights = "Insights"
    case regimen = "Regimen"
    case settings = "Settings"
    case profile = "Profile"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "speedometer"
        case .insights: return "chart.xyaxis.line"
        case .regimen: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        case .profile: return "person.crop.circle"
        }
    }
}

struct RootView: View {
    @State private var selection: AppSection? = .dashboard
    @StateObject private var app = AppViewModel()

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section as AppSection?)
            }
            .navigationTitle("scalinity.bio")
        } detail: {
            Group {
                if let section = selection {
                    detailView(for: section)
                } else {
                    detailView(for: .dashboard)
                }
            }
            .frame(minWidth: 800, minHeight: 520)
        }
        .environmentObject(app)
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .insights:
            InsightsView()
        case .regimen:
            RegimenView()
        case .settings:
            SettingsView()
        case .profile:
            ProfileView()
        }
    }
}


