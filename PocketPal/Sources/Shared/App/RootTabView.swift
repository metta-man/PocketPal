import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.full")
                }

            ArchiveView()
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
