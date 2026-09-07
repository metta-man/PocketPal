import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootTabView: View {
    @AppStorage("receipts.selectedLedger") private var ledger = ReceiptLedger.personal
    @SceneStorage("PocketPal.personal.tab") private var personalTab = "home"
    @SceneStorage("PocketPal.business.tab") private var businessTab = "home"
    @State private var workspace = ReceiptWorkspaceSession()
    private var tab: Binding<String> {
        Binding(get: { ledger == .personal ? personalTab : businessTab },
                set: { guard !workspace.isLocked else { return }; if ledger == .personal { personalTab = $0 } else { businessTab = $0 } })
    }
    private func openRecords(_ filter: ReceiptListScope) {
        workspace.filters[ledger] = filter
        workspace.searches[ledger] = ""
        tab.wrappedValue = "receipts"
    }
    var body: some View {
        VStack(spacing: 0) {
            WorkspaceSwitcher(ledger: $ledger, locked: workspace.isLocked)
            TabView(selection: tab) {
                if ledger == .personal {
                    PersonalHomeView(openRecords: openRecords)
                        .tabItem { Label("生活", systemImage: "sun.max") }.tag("home")
                } else {
                    BusinessHomeView(openReceipts: openRecords)
                        .tabItem { Label("工作台", systemImage: "briefcase") }.tag("home")
                }
                InboxView(selectedLedger: ledger)
                    .tabItem { Label(ledger == .personal ? "明細" : "收據", systemImage: ledger == .personal ? "list.bullet" : "tray.full") }.tag("receipts")
                if ledger == .business {
                    TaxReportView().tabItem { Label("匯出", systemImage: "square.and.arrow.up") }.tag("tax")
                }
                SettingsView().tabItem { Label("設定", systemImage: "gearshape") }.tag("settings")
            }
            .id(ledger)
        }
        .modifier(WorkspaceFilterPersistence(workspace: workspace))
        .environment(\.receiptWorkspace, workspace)
        .tint(ledger.accent)
        .background(ledger.background)
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
