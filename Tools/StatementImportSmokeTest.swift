import AppKit
import CoreGraphics
import Darwin
import Foundation

private struct StatementSmokeCase {
    let name: String
    let url: URL
    let expected: [ExpectedTransaction]
    let minimumSkippedRows: Int
}

private struct ExpectedTransaction {
    let date: String
    let descriptionContains: String
    let amount: Double
}

@main
private struct StatementImportSmokeTest {
    static func main() async {
        do {
            let cases = try makeSelfTestCases()
            let service = BankStatementImportService()
            var passedCases = 0
            var failedCases = 0

            for testCase in cases {
                let result = try await service.parseStatement(at: testCase.url, accountName: "Smoke Test Bank")
                let failures = failures(for: result, expected: testCase.expected, minimumSkippedRows: testCase.minimumSkippedRows)
                if failures.isEmpty {
                    passedCases += 1
                } else {
                    failedCases += 1
                }

                print("""

                == \(testCase.name) ==
                File: \(testCase.url.path)
                Parsed: \(result.transactions.count), skipped: \(result.skippedRowCount)
                Status: \(failures.isEmpty ? "OK" : "MISS")
                \(renderTransactions(result.transactions))
                \(failures.map { "Failure: \($0)" }.joined(separator: "\n"))
                """)
            }

            print("""

            == Summary ==
            Cases: \(passedCases)/\(cases.count)
            """)

            if failedCases > 0 {
                Darwin.exit(1)
            }
        } catch {
            print("ERROR: \(error.localizedDescription)")
            Darwin.exit(1)
        }
    }

    private static func makeSelfTestCases() throws -> [StatementSmokeCase] {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocketpal-statement-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let signedCSV = baseURL.appendingPathComponent("signed_amount.csv")
        try """
        Date,Description,Amount
        2026-06-01,Wellcome Supermarket,-123.45
        2026-06-02,Salary June,25000.00
        2026-06-03,Opening Balance,9999.00
        """.write(to: signedCSV, atomically: true, encoding: .utf8)

        let debitCreditCSV = baseURL.appendingPathComponent("debit_credit_zh.csv")
        try """
        交易日期,交易詳情,支出,收入
        01/06/2026,7-ELEVEN HKG,35.50,
        02/06/2026,FPS RECEIVED LUMI,,500.00
        03/06/2026,Closing Balance,1000.00,
        """.write(to: debitCreditCSV, atomically: true, encoding: .utf8)

        let plainText = baseURL.appendingPathComponent("plain_text.txt")
        try """
        Account number 123-456-789
        01 Jun 2026 MTR MOBILE PAYMENT 12.00 DR
        02 Jun 2026 INTEREST CREDIT 1.25 CR
        03/06/2026 NETFLIX.COM 98.00 DR
        Closing balance 10891.80
        """.write(to: plainText, atomically: true, encoding: .utf8)

        let headerVariantsCSV = baseURL.appendingPathComponent("header_variants.csv")
        try """
        Posted Date,Narrative,Money Out,Money In
        04/06/26,"APPLE.COM/BILL, HK",78.00,
        05/06/26,REFUND APPLE,,HK$12.50
        06/06/26,CARD REVERSAL,,(45.60)
        """.write(to: headerVariantsCSV, atomically: true, encoding: .utf8)

        let pdf = baseURL.appendingPathComponent("text_statement.pdf")
        try writePDF(
            """
            Statement Period 01 Jun 2026 - 30 Jun 2026
            Date Description Amount
            2026-06-04 PARKNSHOP -88.20
            2026-06-05 CLIENT TRANSFER 1200.00 CR
            Closing Balance 12103.60
            """,
            to: pdf
        )

        return [
            StatementSmokeCase(
                name: "Signed CSV amount column",
                url: signedCSV,
                expected: [
                    ExpectedTransaction(date: "2026-06-01", descriptionContains: "Wellcome", amount: -123.45),
                    ExpectedTransaction(date: "2026-06-02", descriptionContains: "Salary", amount: 25000)
                ],
                minimumSkippedRows: 1
            ),
            StatementSmokeCase(
                name: "Chinese debit/credit CSV",
                url: debitCreditCSV,
                expected: [
                    ExpectedTransaction(date: "2026-06-01", descriptionContains: "7-ELEVEN", amount: -35.50),
                    ExpectedTransaction(date: "2026-06-02", descriptionContains: "FPS", amount: 500)
                ],
                minimumSkippedRows: 1
            ),
            StatementSmokeCase(
                name: "Plain text statement",
                url: plainText,
                expected: [
                    ExpectedTransaction(date: "2026-06-01", descriptionContains: "MTR", amount: -12),
                    ExpectedTransaction(date: "2026-06-02", descriptionContains: "INTEREST", amount: 1.25),
                    ExpectedTransaction(date: "2026-06-03", descriptionContains: "NETFLIX", amount: -98)
                ],
                minimumSkippedRows: 2
            ),
            StatementSmokeCase(
                name: "Header variants CSV",
                url: headerVariantsCSV,
                expected: [
                    ExpectedTransaction(date: "2026-06-04", descriptionContains: "APPLE.COM", amount: -78),
                    ExpectedTransaction(date: "2026-06-05", descriptionContains: "REFUND", amount: 12.50),
                    ExpectedTransaction(date: "2026-06-06", descriptionContains: "REVERSAL", amount: 45.60)
                ],
                minimumSkippedRows: 0
            ),
            StatementSmokeCase(
                name: "Text-based PDF statement",
                url: pdf,
                expected: [
                    ExpectedTransaction(date: "2026-06-04", descriptionContains: "PARKNSHOP", amount: -88.20),
                    ExpectedTransaction(date: "2026-06-05", descriptionContains: "CLIENT", amount: 1200)
                ],
                minimumSkippedRows: 2
            )
        ]
    }

    private static func failures(
        for result: BankStatementImportResult,
        expected: [ExpectedTransaction],
        minimumSkippedRows: Int
    ) -> [String] {
        var failures: [String] = []
        if result.transactions.count != expected.count {
            failures.append("expected \(expected.count) transactions, got \(result.transactions.count)")
        }
        if result.skippedRowCount < minimumSkippedRows {
            failures.append("expected at least \(minimumSkippedRows) skipped rows, got \(result.skippedRowCount)")
        }

        for expectation in expected {
            guard result.transactions.contains(where: { transaction in
                isSameDate(transaction.postedAt, expectation.date)
                    && normalize(transaction.descriptionText).contains(normalize(expectation.descriptionContains))
                    && abs(transaction.amountHKD - expectation.amount) < 0.01
            }) else {
                failures.append("missing \(expectation.date) \(expectation.descriptionContains) \(String(format: "%.2f", expectation.amount))")
                continue
            }
        }

        return failures
    }

    private static func renderTransactions(_ transactions: [BankStatementTransactionDraft]) -> String {
        transactions
            .map {
                "\(formatDate($0.postedAt)) | \(String(format: "%+.2f", $0.amountHKD)) | \($0.descriptionText)"
            }
            .joined(separator: "\n")
    }

    private static func writePDF(_ text: String, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        text.draw(in: CGRect(x: 48, y: 96, width: 520, height: 620), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }

    private static func isSameDate(_ date: Date, _ expected: String) -> Bool {
        guard let expectedDate = parseDate(expected) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: expectedDate)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9\p{Han}]+"#, with: "", options: .regularExpression)
            .lowercased()
    }
}
