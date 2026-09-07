import SwiftUI

/// Blocking recovery state shown when the SwiftData persistent store cannot be
/// opened. This prevents the app from presenting an editable empty in-memory
/// store that could be mistaken for missing data.
struct PersistentStoreErrorView: View {
    let error: Error?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Unable to Open Data Store")
                    .font(.title2.weight(.bold))

                Text("PocketPal could not open its local database. Your data has not been deleted or reset. Please restart the app to try again. If the problem persists, contact support.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error {
                Text(error.localizedDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.receiptGroupedBackground)
    }
}

#Preview {
    PersistentStoreErrorView(error: NSError(domain: "SwiftData", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "The persistent store could not be loaded."
    ]))
}
