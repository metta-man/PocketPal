import SwiftUI
import SwiftData
import Observation

// One session per window; no receipt data is duplicated or moved.
@Observable final class ReceiptWorkspaceSession {
    var captureRequested = false
    var locks: Set<UUID> = []
    var filters: [ReceiptLedger: ReceiptListScope] = [:]
    var searches: [ReceiptLedger: String] = [:]
    var insightFilters: [ReceiptLedger: [String: String]] = [:]
    var isLocked: Bool { !locks.isEmpty }
    func setLocked(_ locked: Bool, owner: UUID) {
        if locked { locks.insert(owner) } else { locks.remove(owner) }
    }
}
private struct WorkspaceFilterSnapshot: Codable {
    var filters: [String: String]
    var searches: [String: String]
    var insights: [String: [String: String]]
}
extension ReceiptWorkspaceSession {
    var savedFilters: String {
        let snapshot = WorkspaceFilterSnapshot(
            filters: Dictionary(uniqueKeysWithValues: filters.map { ($0.key.rawValue, $0.value.rawValue) }),
            searches: Dictionary(uniqueKeysWithValues: searches.map { ($0.key.rawValue, $0.value) }),
            insights: Dictionary(uniqueKeysWithValues: insightFilters.map { ($0.key.rawValue, $0.value) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(snapshot)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func restoreFilters(_ value: String) {
        guard let data = value.data(using: .utf8), let snapshot = try? JSONDecoder().decode(WorkspaceFilterSnapshot.self, from: data) else { return }
        for ledger in ReceiptLedger.allCases {
            filters[ledger] = snapshot.filters[ledger.rawValue].flatMap(ReceiptListScope.init(rawValue:))
            searches[ledger] = snapshot.searches[ledger.rawValue]
            insightFilters[ledger] = snapshot.insights[ledger.rawValue]
        }
    }
}
struct WorkspaceFilterPersistence: ViewModifier {
    let workspace: ReceiptWorkspaceSession
    @SceneStorage("PocketPal.workspace.filters") private var saved = ""
    @State private var restored = false
    func body(content: Content) -> some View {
        content.onAppear {
            guard !restored else { return }
            workspace.restoreFilters(saved)
            restored = true
        }.onChange(of: workspace.savedFilters) { _, value in
            if restored { saved = value }
        }
    }
}

private struct ReceiptWorkspaceKey: EnvironmentKey {
    static let defaultValue = ReceiptWorkspaceSession()
}
extension EnvironmentValues {
    var receiptWorkspace: ReceiptWorkspaceSession {
        get { self[ReceiptWorkspaceKey.self] }
        set { self[ReceiptWorkspaceKey.self] = newValue }
    }
}

extension ReceiptLedger {
    var symbol: String { self == .personal ? "sun.max.fill" : "briefcase.fill" }
    var accent: Color { self == .personal ? .personalAccent : .receiptAccentBlue }
    var background: Color { self == .personal ? .personalBackground : .receiptGroupedBackground }
}

struct WorkspaceSwitcher: View {
    @Binding var ledger: ReceiptLedger
    let locked: Bool
    private var identity: some View {
        Label("\(ledger.title)空間", systemImage: ledger.symbol).font(.headline)
    }
    private var switchMenu: some View {
        Menu {
            ForEach(ReceiptLedger.allCases) { item in
                Button { ledger = item } label: { Label("切換到\(item.title)空間", systemImage: item.symbol) }
            }
        } label: { Label("切換空間", systemImage: "arrow.left.arrow.right").font(.subheadline) }
        .disabled(locked)
        .accessibilityIdentifier("workspace.switch")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack { identity.fixedSize(); Spacer(minLength: 16); switchMenu.fixedSize() }
                VStack(alignment: .leading, spacing: 8) { identity; switchMenu }
            }
            if locked { Text("完成或取消目前操作後可切換").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(ledger.background)
        .tint(ledger.accent)
    }
}

struct WorkspaceCurrencyTotal: Identifiable {
    var id: String { currency }
    let currency: String
    let income: Double
    let expense: Double
}
enum WorkspaceSummary {
    static func monthlyTotals(_ receipts: [Receipt], ledger: ReceiptLedger, now: Date = .now, calendar: Calendar = .current) -> [WorkspaceCurrencyTotal] {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        let eligible = receipts.filter {
            ledger.includes($0) && $0.reviewStatus == .reviewed && $0.totalAmount != nil &&
            ($0.transactionDate.map { $0 >= month.start && $0 < month.end } == true || $0.finance.payments.contains { $0.date >= month.start && $0.date < month.end })
        }
        let grouped = Dictionary(grouping: eligible) { receipt in
            receipt.currencyCode ?? "未指定幣種"
        }
        var totals: [WorkspaceCurrencyTotal] = []
        totals.reserveCapacity(grouped.count)

        for (currency, receipts) in grouped {
            var income = 0.0
            var expense = 0.0
            for receipt in receipts {
                for entry in receipt.cashEntries(start: month.start, end: month.end.addingTimeInterval(-1)) {
                    income += NSDecimalNumber(decimal: entry.income).doubleValue
                    expense += NSDecimalNumber(decimal: entry.expense).doubleValue
                }
            }
            totals.append(WorkspaceCurrencyTotal(
                currency: currency,
                income: income,
                expense: expense
            ))
        }

        return totals.sorted { $0.currency < $1.currency }
    }
}

struct PersonalHomeView: View {
    @Environment(\.receiptWorkspace) private var workspace
    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)]) private var allReceipts: [Receipt]
    let openRecords: (ReceiptListScope) -> Void
    @State private var adding = false
    @State private var selected: Receipt?
    @State private var lockID = UUID()
    private var receipts: [Receipt] { allReceipts.filter { ReceiptLedger.personal.includes($0) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("我的生活", systemImage: "sun.max.fill").foregroundStyle(Color.personalAccent)
                        Text("每一筆，慢慢記好。").font(.largeTitle.bold())
                        Text("本月收支 · 已確認記錄").foregroundStyle(.secondary)
                    }
                    let totals = WorkspaceSummary.monthlyTotals(receipts, ledger: .personal)
                    if totals.isEmpty { Text("今個月未有已確認收支。\n由記低第一筆開始。").foregroundStyle(.secondary) }
                    ForEach(totals) { total in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(total.currency).font(.headline)
                            Text("支出 \(total.expense.formatted())").font(.largeTitle.weight(.semibold))
                            Text("收入 \(total.income.formatted())").font(.title3)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                            .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 24))
                    }
                    Button { adding = true } label: {
                        Label("記一筆", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.borderedProminent).tint(.personalAccent)
                    let pending = receipts.filter { $0.reviewStatus != .reviewed }.count
                    Button { openRecords(.pending) } label: {
                        Label("\(pending) 筆待確認", systemImage: "checkmark.circle")
                    }
                    let undated = receipts.filter { $0.transactionDate == nil }.count
                    if undated > 0 {
                        Button("\(undated) 筆未填日期 · 未計入本月") { openRecords(.undated) }
                    }
                    HStack { Text("最近記錄").font(.title2.bold()); Spacer(); Button("查看全部") { openRecords(.all) } }
                    ForEach(Array(receipts.prefix(8))) { receipt in
                        Button { selected = receipt } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "circle.fill").font(.caption2).foregroundStyle(Color.personalAccent).padding(.top, 8)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(receipt.displayMerchantName).font(.headline)
                                    Text(receipt.transactionDate?.formatted(date: .abbreviated, time: .omitted) ?? "未填日期").font(.caption).foregroundStyle(.secondary)
                                    if receipt.reviewStatus != .reviewed { Text("待確認").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text("\(receipt.currencyCode ?? "—") \(receipt.totalAmount?.formatted() ?? "—")")
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Color.personalBackground).navigationTitle("個人 · 生活")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationDestination(isPresented: $adding) { ManualEntryView(initialExpenseType: .personal) }
                .navigationDestination(item: $selected) { ReceiptDetailView(receipt: $0) }
        }
        .onChange(of: adding || selected != nil) { _, locked in workspace.setLocked(locked, owner: lockID) }
        .onDisappear { if !adding && selected == nil { workspace.setLocked(false, owner: lockID) } }
    }
}

struct BusinessHomeView: View {
    @Environment(\.receiptWorkspace) private var workspace
    @Query private var allReceipts: [Receipt]
    let openReceipts: (ReceiptListScope) -> Void
    private var receipts: [Receipt] { allReceipts.filter { ReceiptLedger.business.includes($0) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("業務工作台", systemImage: "briefcase.fill").font(.headline).foregroundStyle(Color.receiptAccentBlue)
                    Text("今日要處理嘅單據").font(.largeTitle.bold())
                    Text("抽取資料 → 核對 → 匯出").foregroundStyle(.secondary)
                    Button { workspace.captureRequested = true; openReceipts(.all) } label: { Label("加入收據", systemImage: "plus.viewfinder").frame(maxWidth: .infinity).padding(10) }
                        .buttonStyle(.borderedProminent)
                    taskRow("未用過 Gemini", symbol: "sparkles", scope: .neverExtracted)
                    taskRow("待確認", symbol: "checklist", scope: .pending)
                    taskRow("資料不完整", symbol: "exclamationmark.triangle", scope: .incomplete)
                    Text("待辦可能重疊；只處理業務及報銷收據。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("本月已確認收支").font(.headline)
                    let totals = WorkspaceSummary.monthlyTotals(receipts, ledger: .business)
                    if totals.isEmpty { Text("未有已確認金額").foregroundStyle(.secondary) }
                    ForEach(totals) { total in
                        Text("\(total.currency)  ·  支出 \(total.expense.formatted())  ·  收入 \(total.income.formatted())")
                    }
                    let undated = receipts.filter { $0.transactionDate == nil }.count
                    if undated > 0 { Button("\(undated) 張未填日期 · 未計入本月") { openReceipts(.undated) } }
                }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Color.receiptGroupedBackground).navigationTitle("業務 · 工作台")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }
    private func taskRow(_ title: String, symbol: String, scope: ReceiptListScope) -> some View {
        Button { openReceipts(scope) } label: {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                Text("\(receipts.filter { scope.includes($0) }.count)").font(.title.bold())
                Image(systemName: "chevron.right")
            }.padding(20).background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
