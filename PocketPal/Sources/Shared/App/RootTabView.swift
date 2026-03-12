import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootTabView: View {
    var body: some View {
        ZStack {
            Color.receiptGroupedBackground
                .ignoresSafeArea()

            TabView {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "house")
                    }

                InboxView()
                    .tabItem {
                        Label("Inbox", systemImage: "tray.full")
                    }

                InsightView()
                    .tabItem {
                        Label("Insights", systemImage: "chart.bar.xaxis")
                    }

                ArchiveView()
                    .tabItem {
                        Label("Archive", systemImage: "archivebox")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
        }
        #if os(iOS)
        .onAppear(perform: forceFullScreenWindowSize)
        #endif
    }

    #if os(iOS)
    private func forceFullScreenWindowSize() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let sizeRestrictions = windowScene.sizeRestrictions else {
            return
        }

        let screenSize = UIScreen.main.bounds.size
        sizeRestrictions.minimumSize = screenSize
        sizeRestrictions.maximumSize = screenSize
    }
    #endif
}

#Preview {
    RootTabView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
