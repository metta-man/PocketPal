import SwiftUI

struct SettingsView: View {
    @AppStorage(OCRPreferences.selectedLanguageCodesKey)
    private var storedLanguageCodes = OCRPreferences.defaultLanguageCodes.joined(separator: ",")

    private var selectedLanguageCodes: [String] {
        OCRPreferences.selectedRecognitionLanguages()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.receiptGroupedBackground
                    .ignoresSafeArea()

                List {
                    Section {
                        settingsHero
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("OCR Languages") {
                        ForEach(OCRLanguageOption.allCases) { option in
                            Toggle(isOn: binding(for: option)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.displayName)
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        Text("Pick one or more languages to improve OCR on your receipts. PocketPal will use these languages on the next OCR run.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                #endif
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            #endif
        }
    }

    private var settingsHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tune OCR for the languages you actually scan.")
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("Selecting fewer languages can help Vision focus on the right script. Keep multiple languages enabled if your receipts mix them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.14), Color.teal.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func binding(for option: OCRLanguageOption) -> Binding<Bool> {
        Binding(
            get: {
                selectedLanguageCodes.contains(option.rawValue)
            },
            set: { isEnabled in
                var updatedCodes = selectedLanguageCodes

                if isEnabled {
                    updatedCodes.append(option.rawValue)
                } else {
                    updatedCodes.removeAll { $0 == option.rawValue }
                }

                OCRPreferences.updateSelectedRecognitionLanguages(updatedCodes)
                storedLanguageCodes = OCRPreferences.selectedRecognitionLanguages().joined(separator: ",")
            }
        )
    }
}

#Preview {
    SettingsView()
}
