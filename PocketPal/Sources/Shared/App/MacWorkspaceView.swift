#if os(macOS)
import SwiftData
import SwiftUI

private enum MacWorkspaceSection: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case money = "Money"
    case work = "Work"
    case books = "Books"
    case operations = "Operations"

    var id: String { rawValue }

    static var enabledCases: [MacWorkspaceSection] {
        InfrastructureFeatureFlags.accountingWorkspaceEnabled ? allCases : [.workspace]
    }
}

enum MacWorkspaceDestination: String, CaseIterable, Identifiable {
    case overview
    case settings
    case receipts
    case archive
    case insights
    case banking
    case sales
    case bills
    case projects
    case books
    case tax
    case automation
    case operations

    static let defaultDestination: MacWorkspaceDestination = .overview

    static var enabledDestinations: [MacWorkspaceDestination] {
        if InfrastructureFeatureFlags.accountingWorkspaceEnabled {
            return allCases
        }

        return [.overview, .receipts, .archive, .insights, .tax, .settings]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "設定"
        case .overview:
            return "總覽"
        case .receipts:
            return "收據"
        case .archive:
            return "已確認"
        case .insights:
            return "分析"
        case .banking:
            return "Banking"
        case .sales:
            return "Sales"
        case .bills:
            return "Bills"
        case .projects:
            return "Projects, Time & Mileage"
        case .books:
            return "Accounts & Journals"
        case .tax:
            return "稅務匯出"
        case .automation:
            return "Rules"
        case .operations:
            return "Payroll & Inventory"
        }
    }

    var systemImage: String {
        switch self {
        case .settings: return "gearshape"
        case .overview:
            return "rectangle.grid.2x2"
        case .receipts:
            return "tray.full"
        case .archive:
            return "archivebox"
        case .insights:
            return "chart.xyaxis.line"
        case .banking:
            return "creditcard"
        case .sales:
            return "doc.text"
        case .bills:
            return "tray.and.arrow.down"
        case .projects:
            return "clock.badge.checkmark"
        case .books:
            return "books.vertical"
        case .tax:
            return "checklist"
        case .automation:
            return "wand.and.stars"
        case .operations:
            return "shippingbox"
        }
    }

    fileprivate var section: MacWorkspaceSection {
        switch self {
        case .overview, .receipts, .archive, .insights, .tax, .settings:
            return .workspace
        case .banking, .sales, .bills:
            return .money
        case .projects:
            return .work
        case .books:
            return .books
        case .automation, .operations:
            return .operations
        }
    }

    fileprivate var accountingModule: AccountingModule? {
        switch self {
        case .banking:
            return .banking
        case .sales:
            return .sales
        case .bills:
            return .bills
        case .projects:
            return .projects
        case .books:
            return .books
        case .automation:
            return .automation
        case .operations:
            return .operations
        case .overview, .receipts, .archive, .insights, .tax, .settings:
            return nil
        }
    }

    fileprivate static func destinations(in section: MacWorkspaceSection) -> [MacWorkspaceDestination] {
        enabledDestinations.filter { $0.section == section }
    }
}

struct MacWorkspaceView: View {
    @State private var workspace = ReceiptWorkspaceSession()
    let experimentsContainer: ModelContainer?
    let experimentsLoadError: Error?
    private let selectedDestinationOverride: MacWorkspaceDestination?

    @SceneStorage("PocketPal.space") private var ledgerRaw = ""
    @AppStorage("receipts.selectedLedger") private var lastLedger = ReceiptLedger.personal
    @SceneStorage("PocketPal.personal.destination") private var personalDestination = "overview"
    @SceneStorage("PocketPal.business.destination") private var businessDestination = "overview"
    private var ledger: Binding<ReceiptLedger> {
        Binding(get: { ReceiptLedger(rawValue: ledgerRaw) ?? lastLedger }, set: {
            ledgerRaw = $0.rawValue
            lastLedger = $0
        })
    }
    @SceneStorage("PocketPal.MacWorkspace.selectedDestination")
    private var selectedDestinationRaw = MacWorkspaceDestination.defaultDestination.rawValue

    init(
        experimentsContainer: ModelContainer? = nil,
        experimentsLoadError: Error? = nil,
        selectedDestinationOverride: MacWorkspaceDestination? = nil
    ) {
        self.experimentsContainer = experimentsContainer
        self.experimentsLoadError = experimentsLoadError
        self.selectedDestinationOverride = selectedDestinationOverride
    }

    var body: some View {
        MacWorkspaceContentView(
            experimentsContainer: experimentsContainer,
            experimentsLoadError: experimentsLoadError,
            selectedDestinationRaw: $selectedDestinationRaw,
            selectedDestinationOverride: selectedDestinationOverride,
            ledger: ledger,
            personalDestination: $personalDestination,
            businessDestination: $businessDestination,
            workspace: workspace
        )
        .modifier(WorkspaceFilterPersistence(workspace: workspace))
        .onAppear { if ledgerRaw.isEmpty { ledgerRaw = lastLedger.rawValue } }
    }
}

struct MacWorkspaceContentView: View {
    let experimentsContainer: ModelContainer?
    let experimentsLoadError: Error?
    private let selectedDestinationOverride: MacWorkspaceDestination?

    @Binding private var selectedDestinationRaw: String

    @Binding private var ledger: ReceiptLedger
    @Binding private var personalDestination: String
    @Binding private var businessDestination: String
    @State private var workspace = ReceiptWorkspaceSession()
    private var ledgerBinding: Binding<ReceiptLedger> {
        Binding(get: { ledger }, set: { next in
            guard !workspace.isLocked else { return }
            ledger = next
        })
    }
    private var destinations: [MacWorkspaceDestination] {
        ledger == .personal ? [.overview, .receipts, .insights, .settings] : MacWorkspaceDestination.enabledDestinations
    }
    private func destinationTitle(_ destination: MacWorkspaceDestination) -> String {
        if destination == .overview { return ledger == .personal ? "生活總覽" : "工作台" }
        if destination == .receipts && ledger == .personal { return "收支明細" }
        return destination.title
    }
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    init(
        experimentsContainer: ModelContainer? = nil,
        experimentsLoadError: Error? = nil,
        selectedDestinationRaw: Binding<String>,
        selectedDestinationOverride: MacWorkspaceDestination? = nil,
        ledger: Binding<ReceiptLedger> = .constant(.personal),
        personalDestination: Binding<String> = .constant("overview"),
        businessDestination: Binding<String> = .constant("overview"),
        workspace: ReceiptWorkspaceSession = ReceiptWorkspaceSession()
    ) {
        self._workspace = State(initialValue: workspace)
        self._ledger = ledger
        self._personalDestination = personalDestination
        self._businessDestination = businessDestination
        self.experimentsContainer = experimentsContainer
        self.experimentsLoadError = experimentsLoadError
        self._selectedDestinationRaw = selectedDestinationRaw
        self.selectedDestinationOverride = selectedDestinationOverride
    }

    private var selectedDestination: MacWorkspaceDestination {
        if let selectedDestinationOverride, MacWorkspaceDestination.enabledDestinations.contains(selectedDestinationOverride) {
            return selectedDestinationOverride
        }
        let raw = ledger == .personal ? personalDestination : businessDestination
        let value = MacWorkspaceDestination(rawValue: raw) ?? .overview
        return destinations.contains(value) ? value : .overview
    }
    private var selection: Binding<MacWorkspaceDestination?> {
        Binding(get: { selectedDestination }, set: { value in
            guard !workspace.isLocked else { return }
            selectDestination(value ?? .overview)
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                WorkspaceSwitcher(ledger: ledgerBinding, locked: workspace.isLocked)
                List(selection: selection) {
                    ForEach(destinations) { destination in
                        Label(destinationTitle(destination), systemImage: destination.systemImage).tag(destination)
                    }
                }.listStyle(.sidebar)
            }
            .navigationTitle("\(ledger.title)空間")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            detailView(for: selectedDestination)
                .id("\(ledger.rawValue).\(selectedDestination.rawValue)")
        }
        .environment(\.receiptWorkspace, workspace)
        .tint(ledger.accent)
    }

    @ViewBuilder
    private func detailView(for destination: MacWorkspaceDestination) -> some View {
        if let module = destination.accountingModule {
            if let experimentsContainer {
                AccountingModuleView(module: module)
                    .modelContainer(experimentsContainer)
            } else {
                AccountingWorkspaceUnavailableView(error: experimentsLoadError)
            }
        } else {
            switch destination {
            case .overview:
                if ledger == .personal {
                    PersonalHomeView(openRecords: openRecords)
                } else {
                    BusinessHomeView(openReceipts: openRecords)
                }
            case .receipts:
                InboxView(selectedLedger: ledger)
            case .archive:
                InboxView(selectedLedger: ledger)
                    .onAppear { workspace.filters[ledger] = .reviewed }
            case .insights:
                InsightView(ledger: ledger)
            case .settings:
                SettingsView()
            case .tax:
                TaxReportView()
            case .banking, .sales, .bills, .projects, .books, .automation, .operations:
                EmptyView()
            }
        }
    }

    private func selectDestination(_ destination: MacWorkspaceDestination) {
        selectedDestinationRaw = destination.rawValue
        if ledger == .personal { personalDestination = destination.rawValue }
        else { businessDestination = destination.rawValue }
    }
    private func openRecords(_ filter: ReceiptListScope) {
        workspace.filters[ledger] = filter
        workspace.searches[ledger] = ""
        selectDestination(.receipts)
    }
}

private struct AccountingWorkspaceUnavailableView: View {
    let error: Error?

    var body: some View {
        ContentUnavailableView {
            Label("Accounting workspace unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(error?.localizedDescription ?? "The experiment store is not available. The receipt ledger remains isolated and editable.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.receiptGroupedBackground)
    }
}

private struct MacWorkspaceOverviewView: View {
    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    let selectDestination: (MacWorkspaceDestination) -> Void

    private var pendingReceiptCount: Int {
        receipts.filter { $0.reviewStatus != .reviewed }.count
    }

    private var readyForTaxCount: Int {
        receipts.filter { $0.taxReadiness.isReadyForTaxExport }.count
    }

    private var needsTaxReviewCount: Int {
        receipts.filter { $0.expenseType.isTaxDeductible && !$0.taxReadiness.isReadyForTaxExport }.count
    }

    private var failedProcessingCount: Int {
        receipts.filter { $0.processingState == .failed }.count
    }

    private var capturedTotalHKD: Double {
        receipts.compactMap(\.amountInHKD).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Receipt ledger")
                        .font(.largeTitle.weight(.semibold))
                    Text("Turn messy receipts into reviewed, searchable, tax-ready records.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    WorkspaceMetricTile(value: "\(pendingReceiptCount)", label: "Receipts to review")
                    WorkspaceMetricTile(value: "\(readyForTaxCount)", label: "Tax-ready")
                    WorkspaceMetricTile(value: "\(needsTaxReviewCount)", label: "Tax gaps")
                    WorkspaceMetricTile(value: "\(failedProcessingCount)", label: "OCR failures")
                    WorkspaceMetricTile(value: Currency.amountString(capturedTotalHKD, currencyCode: Currency.hkd.rawValue), label: "Captured")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Focus Areas")
                        .font(.headline)
                    WorkspaceFocusRow(
                        title: "Review receipts",
                        detail: "\(pendingReceiptCount) receipts waiting for review or supporting evidence.",
                        systemImage: "tray.full"
                    ) {
                        selectDestination(.receipts)
                    }
                    WorkspaceFocusRow(
                        title: "Close tax gaps",
                        detail: "\(needsTaxReviewCount) deductible receipts still need complete date, amount, category, or attachment evidence.",
                        systemImage: "checklist"
                    ) {
                        selectDestination(.tax)
                    }
                    WorkspaceFocusRow(
                        title: "Inspect spending",
                        detail: "Use charts and category summaries only after the receipt ledger is clean.",
                        systemImage: "chart.xyaxis.line"
                    ) {
                        selectDestination(.insights)
                    }
                    WorkspaceFocusRow(
                        title: "Archive reviewed records",
                        detail: "Keep historical receipts searchable without mixing them into the active inbox.",
                        systemImage: "archivebox"
                    ) {
                        selectDestination(.archive)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color.receiptGroupedBackground)
        .navigationTitle("Overview")
    }
}

private struct WorkspaceMetricTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(12)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkspaceFocusRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
#endif
