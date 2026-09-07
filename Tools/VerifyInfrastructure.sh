#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing required file: $path"
}

require_pattern() {
  local pattern="$1"
  local path="$2"
  local message="$3"
  rg -q "$pattern" "$path" || fail "$message"
}

first_match_line() {
  local pattern="$1"
  local path="$2"
  local message="$3"
  local match
  match="$(rg -n "$pattern" "$path" | head -n 1 || true)"
  [[ -n "$match" ]] || fail "$message"
  printf '%s' "${match%%:*}"
}

last_match_line() {
  local pattern="$1"
  local path="$2"
  local message="$3"
  local match
  match="$(rg -n "$pattern" "$path" | tail -n 1 || true)"
  [[ -n "$match" ]] || fail "$message"
  printf '%s' "${match%%:*}"
}

require_order() {
  local first_pattern="$1"
  local second_pattern="$2"
  local path="$3"
  local message="$4"
  local first_line
  local second_line
  first_line="$(first_match_line "$first_pattern" "$path" "$message")"
  second_line="$(first_match_line "$second_pattern" "$path" "$message")"
  (( first_line < second_line )) || fail "$message"
}

reject_pattern() {
  local pattern="$1"
  local path="$2"
  local message="$3"
  if rg -n "$pattern" "$path"; then
    fail "$message"
  fi
}

require_file "PocketPal/Docs/InfrastructureRedesign.md"
require_file "PocketPal/Docs/InfrastructureCompletionAudit.md"
require_file "PocketPal/Sources/Shared/Persistence/PocketPalModelContainer.swift"
require_file "PocketPal/Sources/Shared/Persistence/CloudSyncConfiguration.swift"
require_file "PocketPal/Sources/Shared/App/PocketPalApp.swift"
require_file "PocketPal/Sources/Shared/App/MacWorkspaceView.swift"
require_file "PocketPal/Sources/Shared/Features/Accounting/AccountingView.swift"
require_file "PocketPal/Sources/Shared/Features/Settings/SettingsView.swift"
require_file "PocketPal/Sources/Shared/Features/Tax/TaxReportView.swift"
require_file "PocketPal/Sources/Shared/Domain/UseCases/ImportReceiptUseCase.swift"
require_file "PocketPal/Sources/Shared/Services/ReceiptFileStorageService.swift"
require_file "PocketPal/Sources/Shared/Services/TaxExportService.swift"
require_file "PocketPal/Sources/Shared/Services/Security/KeychainService.swift"
require_file "PocketPal/Tests/iOS/Infrastructure/ImportReceiptUseCaseInfrastructureTests.swift"
require_file "PocketPal/Tests/iOS/Infrastructure/LegacyStoreMigrationInfrastructureTests.swift"
require_file "PocketPal/Tests/iOS/Infrastructure/PersistentStoreIsolationInfrastructureTests.swift"
require_file "PocketPal/Tests/iOS/Infrastructure/ReceiptFileStorageInfrastructureTests.swift"
require_file "PocketPal/Tests/iOS/Infrastructure/TaxExportInfrastructureTests.swift"
require_file "PocketPal/Tests/macOS/Infrastructure/MacAccountingWorkspaceInfrastructureTests.swift"
require_file "PocketPal/Tests/macOS/Infrastructure/MacCoreSettingsInfrastructureTests.swift"
require_file "PocketPal/Tests/macOS/Infrastructure/MacReceiptLoopInfrastructureTests.swift"
require_file "Tools/RunInfrastructureGate.sh"
require_file ".github/workflows/infrastructure.yml"
require_file ".gitignore"
require_file "project.yml"

IMPORT_USE_CASE="PocketPal/Sources/Shared/Domain/UseCases/ImportReceiptUseCase.swift"
MODEL_CONTAINER="PocketPal/Sources/Shared/Persistence/PocketPalModelContainer.swift"
CLOUD_SYNC_CONFIGURATION="PocketPal/Sources/Shared/Persistence/CloudSyncConfiguration.swift"
FILE_STORAGE_SERVICE="PocketPal/Sources/Shared/Services/ReceiptFileStorageService.swift"
SERVICE_CONTAINER="PocketPal/Sources/Shared/App/ServiceContainer.swift"
KEYCHAIN_SERVICE="PocketPal/Sources/Shared/Services/Security/KeychainService.swift"
SETTINGS_VIEW="PocketPal/Sources/Shared/Features/Settings/SettingsView.swift"
TAX_REPORT_VIEW="PocketPal/Sources/Shared/Features/Tax/TaxReportView.swift"
TAX_EXPORT_SERVICE="PocketPal/Sources/Shared/Services/TaxExportService.swift"
IMPORT_INFRA_TEST="PocketPal/Tests/iOS/Infrastructure/ImportReceiptUseCaseInfrastructureTests.swift"
LEGACY_MIGRATION_TEST="PocketPal/Tests/iOS/Infrastructure/LegacyStoreMigrationInfrastructureTests.swift"
STORE_ISOLATION_TEST="PocketPal/Tests/iOS/Infrastructure/PersistentStoreIsolationInfrastructureTests.swift"
FILE_STORAGE_TEST="PocketPal/Tests/iOS/Infrastructure/ReceiptFileStorageInfrastructureTests.swift"
TAX_EXPORT_TEST="PocketPal/Tests/iOS/Infrastructure/TaxExportInfrastructureTests.swift"
MAC_ACCOUNTING_WORKSPACE_TEST="PocketPal/Tests/macOS/Infrastructure/MacAccountingWorkspaceInfrastructureTests.swift"
MAC_CORE_SETTINGS_TEST="PocketPal/Tests/macOS/Infrastructure/MacCoreSettingsInfrastructureTests.swift"
MAC_RECEIPT_LOOP_TEST="PocketPal/Tests/macOS/Infrastructure/MacReceiptLoopInfrastructureTests.swift"
COMPLETION_AUDIT="PocketPal/Docs/InfrastructureCompletionAudit.md"

require_pattern "static func makeExperiments" \
  "$MODEL_CONTAINER" \
  "PocketPalModelContainer must expose an experiments-only container"
require_pattern "ModelContainer\\(for: experimentsSchema" \
  "$MODEL_CONTAINER" \
  "experiments container must be built from experimentsSchema"
require_pattern "ModelContainer\\(for: receiptLedgerSchema" \
  "$MODEL_CONTAINER" \
  "core container must be built from receiptLedgerSchema"
require_pattern "MigrationBackups" \
  "$MODEL_CONTAINER" \
  "legacy split migration must keep backups"
require_pattern "experimentEntityNames" \
  "$MODEL_CONTAINER" \
  "legacy split migration must detect experiment entities from store metadata"
require_pattern "POCKETPAL_STORE_ROOT_OVERRIDE" \
  "$MODEL_CONTAINER" \
  "persistent store root must remain overridable for isolated runtime migration tests"
require_pattern "persistentStoreRootDirectory" \
  "$MODEL_CONTAINER" \
  "persistent store URL construction must keep the isolated store root helper"
require_pattern "sqliteStoreMetadataContainsAnyEntity" \
  "$MODEL_CONTAINER" \
  "legacy split migration must not rely only on SQLite table-name detection"
require_pattern "POCKETPAL_ENABLE_CLOUDKIT" \
  "$CLOUD_SYNC_CONFIGURATION" \
  "CloudKit sync must require an explicit environment override or user setting"
require_pattern "UserDefaults\\.standard\\.bool\\(forKey: userDefaultsKey\\)" \
  "$CLOUD_SYNC_CONFIGURATION" \
  "CloudKit sync must stay off by default through UserDefaults false"
require_pattern "cloudSyncEnabled \\? \\.automatic : \\.none" \
  "$MODEL_CONTAINER" \
  "receipt ledger CloudKit configuration must stay controlled by cloudSyncEnabled"
require_pattern "return try make\\(isStoredInMemoryOnly: false, cloudSyncEnabled: false\\)" \
  "$MODEL_CONTAINER" \
  "CloudKit store failures must fall back to a local receipt store"

require_pattern "POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE" \
  "PocketPal/Sources/Shared/App/AppPreferences.swift" \
  "accounting workspace must remain feature-flagged"
require_pattern "makeExperiments\\(" \
  "PocketPal/Sources/Shared/App/PocketPalApp.swift" \
  "macOS app must create the experiment container only through makeExperiments"
require_pattern "\\.modelContainer\\(experimentsContainer\\)" \
  "PocketPal/Sources/Shared/App/MacWorkspaceView.swift" \
  "accounting subtree must override SwiftData with the experiment container"
require_pattern "selectedDestinationOverride" \
  "PocketPal/Sources/Shared/App/MacWorkspaceView.swift" \
  "macOS accounting workspace must keep a runtime-testable destination override"
require_pattern "struct MacWorkspaceContentView" \
  "PocketPal/Sources/Shared/App/MacWorkspaceView.swift" \
  "macOS workspace routing must be renderable without SceneStorage for hosted runtime tests"
require_pattern "final class LazyKeychainService" \
  "$KEYCHAIN_SERVICE" \
  "keychain access must remain behind a lazy wrapper"
require_pattern "keychainServiceProvider" \
  "$SERVICE_CONTAINER" \
  "ServiceContainer must expose a lazy keychain provider seam"
require_pattern "LazyKeychainService\\(" \
  "$SERVICE_CONTAINER" \
  "ServiceContainer must wrap default keychain access lazily"
reject_pattern "keychainService \\?\\? KeychainService\\(" \
  "$SERVICE_CONTAINER" \
  "ServiceContainer must not construct KeychainService during initialization"
require_pattern "let resolvedCloudExtractionServiceProvider = cloudExtractionServiceProvider \\?\\? \\{" \
  "$SERVICE_CONTAINER" \
  "ServiceContainer must keep Gemini construction behind a provider closure"
require_pattern "GeminiReceiptExtractionService\\(keychainService: resolvedKeychainService\\)" \
  "$SERVICE_CONTAINER" \
  "ServiceContainer default cloud provider must use the lazy keychain wrapper"
reject_pattern "cloudExtractionServiceProvider\\?\\(\\)" \
  "$SERVICE_CONTAINER" \
  "ServiceContainer must not call the cloud provider during initialization"

reject_pattern "\\bReceipt\\b" \
  "PocketPal/Sources/Shared/Features/Accounting/AccountingView.swift" \
  "accounting workspace must not query, create, or mutate Receipt rows"
reject_pattern "\\bConnection\\b" \
  "PocketPal/Sources/Shared/Features/Settings/SettingsView.swift" \
  "core settings must not query or export Connection rows"
reject_pattern "\\.path\\(\\)" \
  "PocketPal/Sources" \
  "filesystem checks must use path(percentEncoded: false), not URL.path()"

require_pattern "let receipt = Receipt\\(importSource: source, expenseType: expenseType\\)" \
  "$IMPORT_USE_CASE" \
  "import path must create the core Receipt row in the requested workspace"
require_pattern "modelContext\\.insert\\(receipt\\)" \
  "$IMPORT_USE_CASE" \
  "import path must insert the Receipt before storing the asset"
require_pattern "storageService\\.storeImportedFile\\(from: fileURL, receiptID: receipt\\.id\\)" \
  "$IMPORT_USE_CASE" \
  "file imports must be stored through ReceiptFileStorageService"
require_pattern "storageService\\.storeImportedData\\(document, receiptID: receipt\\.id\\)" \
  "$IMPORT_USE_CASE" \
  "in-memory imports must be stored through ReceiptFileStorageService"
require_order "modelContext\\.insert\\(receipt\\)" "storageService\\.storeImported" \
  "$IMPORT_USE_CASE" \
  "Receipt must exist before storage writes use its id"
require_order "storageService\\.storeImported" "modelContext\\.delete\\(receipt\\)" \
  "$IMPORT_USE_CASE" \
  "failed storage writes must roll back the pending Receipt"

require_pattern "let asset = ReceiptAsset\\(" \
  "$IMPORT_USE_CASE" \
  "import path must create a ReceiptAsset row"
require_pattern "asset\\.receipt = receipt" \
  "$IMPORT_USE_CASE" \
  "ReceiptAsset must point back to its Receipt"
require_pattern "receipt\\.asset = asset" \
  "$IMPORT_USE_CASE" \
  "Receipt must own the imported ReceiptAsset"
require_pattern "modelContext\\.insert\\(asset\\)" \
  "$IMPORT_USE_CASE" \
  "import path must insert the ReceiptAsset"
require_order "let asset = ReceiptAsset\\(" "modelContext\\.insert\\(asset\\)" \
  "$IMPORT_USE_CASE" \
  "ReceiptAsset must be created before it is inserted"
asset_insert_line="$(first_match_line "modelContext\\.insert\\(asset\\)" "$IMPORT_USE_CASE" "import path must insert the ReceiptAsset")"
asset_delete_line="$(last_match_line "modelContext\\.delete\\(asset\\)" "$IMPORT_USE_CASE" "failed saves must roll back the ReceiptAsset")"
receipt_delete_line="$(last_match_line "modelContext\\.delete\\(receipt\\)" "$IMPORT_USE_CASE" "failed saves must roll back the Receipt")"
(( asset_insert_line < asset_delete_line )) || fail "failed saves must delete the staged ReceiptAsset"
(( asset_delete_line < receipt_delete_line )) || fail "failed saves must delete ReceiptAsset before Receipt"

require_pattern "if storedFile\\.kind == \\.image" \
  "$IMPORT_USE_CASE" \
  "OCR should only auto-run for image assets"
require_pattern "private func processOCRIfNeeded" \
  "$IMPORT_USE_CASE" \
  "image imports must keep the optional OCR processing path"
require_pattern "let ocrResult: OCRResult" \
  "$IMPORT_USE_CASE" \
  "OCR path must create or update OCRResult"
require_pattern "receipt\\.ocrResult = ocrResult" \
  "$IMPORT_USE_CASE" \
  "OCRResult must be attached to its Receipt"
require_pattern "modelContext\\.insert\\(ocrResult\\)" \
  "$IMPORT_USE_CASE" \
  "new OCRResult rows must be inserted"

require_pattern "automaticCloudEnhancementEnabled\\(\\)" \
  "$IMPORT_USE_CASE" \
  "automatic cloud fallback must check the enhancement policy"
require_pattern "cloudUploadConsentGranted\\(\\)" \
  "$IMPORT_USE_CASE" \
  "automatic cloud fallback must check upload consent"
require_pattern "var allowsAutomaticCloudExtraction: Bool" \
  "$IMPORT_USE_CASE" \
  "Gemini extraction must expose the opt-in policy independently of local confidence"
require_order "processingPolicy\\.allowsAutomaticCloudFallback\\(for: extraction\\)" "cloudExtractionServiceProvider\\(\\)" \
  "$IMPORT_USE_CASE" \
  "automatic cloud extraction must stay behind the policy gate"
reject_pattern "\\b(Connection|BankTransaction|AccountingAccount|JournalEntryRecord|SyncLog)\\b" \
  "$IMPORT_USE_CASE" \
  "import path must not depend on experimental accounting models"

require_pattern "func storeImportedFile\\(from sourceURL: URL, receiptID: UUID\\)" \
  "$FILE_STORAGE_SERVICE" \
  "file storage must support file URL imports"
require_pattern "func storeImportedData\\(_ document: ImportedReceiptDocument, receiptID: UUID\\)" \
  "$FILE_STORAGE_SERVICE" \
  "file storage must support in-memory document imports"
require_pattern "receiptDirectory\\(for: receiptID\\)" \
  "$FILE_STORAGE_SERVICE" \
  "stored files must live under the receipt id directory"
require_pattern "fileExists\\(atPath: destinationURL\\.path\\(percentEncoded: false\\)\\)" \
  "$FILE_STORAGE_SERVICE" \
  "stored imports must verify destination files with decoded paths"
require_pattern "relativePath\\(for: destinationURL\\)" \
  "$FILE_STORAGE_SERVICE" \
  "stored imports must persist relative asset paths"
require_pattern "contentType: storedContentType" \
  "$FILE_STORAGE_SERVICE" \
  "stored imports must pass the resolved content type into thumbnail generation"
require_pattern "guard contentType\\.conforms\\(to: \\.image\\) \\|\\| contentType\\.conforms\\(to: \\.pdf\\)" \
  "$FILE_STORAGE_SERVICE" \
  "thumbnail generation must be skipped for unsupported content types"
require_pattern "enum ReceiptFileStorageLocationPolicy" \
  "$FILE_STORAGE_SERVICE" \
  "receipt file storage must have an explicit location policy"
require_pattern "locationPolicy: ReceiptFileStorageLocationPolicy = \\.localOnly" \
  "$FILE_STORAGE_SERVICE" \
  "receipt file storage must default to local-only storage"
require_pattern "guard locationPolicy == \\.iCloudDocumentsWhenAvailable" \
  "$FILE_STORAGE_SERVICE" \
  "iCloud file storage must be behind an explicit opt-in policy"
require_order "guard locationPolicy == \\.iCloudDocumentsWhenAvailable" "iCloudBaseDirectory\\(\\)" \
  "$FILE_STORAGE_SERVICE" \
  "receipt file storage must not probe iCloud before the explicit opt-in guard"

require_pattern "PocketPal-iOSTests:" \
  "project.yml" \
  "project must keep the iOS infrastructure test target"
require_pattern "type: bundle\\.unit-test" \
  "project.yml" \
  "iOS infrastructure tests must remain a unit-test bundle"
require_pattern "PocketPal-iOSTests: \\[test\\]" \
  "project.yml" \
  "PocketPal-iOS scheme must build the infrastructure tests for test"
require_pattern "PocketPal-macOSTests:" \
  "project.yml" \
  "project must keep the macOS infrastructure test target"
require_pattern "PocketPal-macOSTests: \\[test\\]" \
  "project.yml" \
  "PocketPal-macOS scheme must build the macOS infrastructure tests for test"
require_pattern "targets:" \
  "project.yml" \
  "PocketPal-iOS scheme must declare test targets"
require_pattern "testImageImportCreatesReceiptAssetAndOCRWithoutCloudFallback" \
  "$IMPORT_INFRA_TEST" \
  "runtime import test must prove Receipt, ReceiptAsset, and OCRResult creation"
require_pattern "testStorageFailureDoesNotLeaveReceiptRows" \
  "$IMPORT_INFRA_TEST" \
  "runtime import test must prove failed storage leaves no orphan rows"
require_pattern "PocketPalModelContainer\\.make\\(isStoredInMemoryOnly: true, cloudSyncEnabled: false\\)" \
  "$IMPORT_INFRA_TEST" \
  "runtime import tests must use local in-memory SwiftData"
require_pattern "processingPolicy: \\.localOnly" \
  "$IMPORT_INFRA_TEST" \
  "runtime import tests must keep cloud fallback disabled"
require_pattern "XCTAssertEqual\\(cloudProbe\\.makeCount, 0\\)" \
  "$IMPORT_INFRA_TEST" \
  "runtime import test must prove cloud provider is not constructed for local-only import"
require_pattern "testServiceContainerInitializationDoesNotConstructCredentialOrCloudProviders" \
  "$IMPORT_INFRA_TEST" \
  "runtime service container test must prove launch graph construction is local-only"
require_pattern "_ = services\\.importReceiptUseCase" \
  "$IMPORT_INFRA_TEST" \
  "runtime service container test must force the service graph to be retained"
require_pattern "testDefaultServiceContainerDoesNotConstructKeychainForLocalOnlyImport" \
  "$IMPORT_INFRA_TEST" \
  "runtime import test must prove ServiceContainer does not construct keychain on local-only import"
require_pattern "keychainServiceProvider: \\{ keychainProbe\\.makeService\\(\\) \\}" \
  "$IMPORT_INFRA_TEST" \
  "runtime import test must inject the lazy keychain provider"
require_pattern "XCTAssertEqual\\(keychainProbe\\.makeCount, 0\\)" \
  "$IMPORT_INFRA_TEST" \
  "runtime import test must assert keychain provider is not constructed"
require_pattern "testDefaultReceiptFileStorageStaysLocalWhenICloudIsAvailable" \
  "$FILE_STORAGE_TEST" \
  "runtime file storage test must prove default storage remains local"
require_pattern "UbiquityAvailableFileManager" \
  "$FILE_STORAGE_TEST" \
  "runtime file storage test must simulate iCloud availability"
require_pattern "ReceiptFileStorageService\\(fileManager: fileManager\\)" \
  "$FILE_STORAGE_TEST" \
  "runtime file storage test must exercise the default storage policy"
require_pattern "XCTAssertEqual\\(fileManager\\.ubiquityContainerLookupCount, 0\\)" \
  "$FILE_STORAGE_TEST" \
  "runtime file storage test must prove default storage does not query iCloud"
require_pattern "XCTAssertTrue\\(FileManager\\.default\\.fileExists\\(atPath: expectedLocalURL\\.path\\(percentEncoded: false\\)\\)\\)" \
  "$FILE_STORAGE_TEST" \
  "runtime file storage test must prove the receipt file lands in local storage"
require_pattern "XCTAssertFalse\\(FileManager\\.default\\.fileExists\\(atPath: unexpectedICloudURL\\.path\\(percentEncoded: false\\)\\)\\)" \
  "$FILE_STORAGE_TEST" \
  "runtime file storage test must prove default storage does not write receipt files to iCloud"
require_pattern "testTaxExportSummarizesAndSerializesReceiptLedgerRows" \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must prove receipt-ledger CSV output"
require_pattern "PocketPalModelContainer\\.make\\(isStoredInMemoryOnly: true, cloudSyncEnabled: false\\)" \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must use a local in-memory receipt ledger"
require_pattern "TaxExportService\\.summary\\(for: receipts\\)" \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must prove summary output from Receipt rows"
require_pattern "receipts\\.filter\\(\\\\.taxReadiness\\.isReadyForTaxExport\\)" \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must prove only tax-ready receipts are exported"
require_pattern "TaxExportService\\.makeTaxCSVData\\(receipts: readyReceipts\\)" \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must serialize the ready receipt subset"
require_pattern "\\[UInt8\\]\\(allRowsData\\.prefix\\(3\\)\\), \\[0xEF, 0xBB, 0xBF\\]" \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must prove CSV keeps the UTF-8 BOM"
require_pattern '\\\"\\\"Lunch\\\"\\\"' \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must prove CSV escaping"
require_pattern "XCTAssertFalse\\(readyRowsCSV\\.contains\\(incompleteReceiptID\\.uuidString\\)\\)" \
  "$TAX_EXPORT_TEST" \
  "runtime tax export test must keep incomplete receipts out of ready exports"
require_pattern "testLegacyCombinedStoreSplitsReceiptLedgerAndExperimentModels" \
  "$LEGACY_MIGRATION_TEST" \
  "runtime migration test must prove legacy combined-store split behavior"
require_pattern "POCKETPAL_STORE_ROOT_OVERRIDE" \
  "$LEGACY_MIGRATION_TEST" \
  "runtime migration test must use an isolated persistent store root"
require_pattern "createLegacyCombinedStore" \
  "$LEGACY_MIGRATION_TEST" \
  "runtime migration test must build a real legacy combined SwiftData store"
require_pattern "PocketPalModelContainer\\.make\\(" \
  "$LEGACY_MIGRATION_TEST" \
  "runtime migration test must trigger the production receipt container path"
require_pattern "PocketPalModelContainer\\.makeExperiments\\(" \
  "$LEGACY_MIGRATION_TEST" \
  "runtime migration test must verify the production experiments container path"
require_pattern "XCTAssertFalse\\(Self\\.sqliteTableExists\\(\"ZCONNECTION\", at: receiptStoreURL\\)\\)" \
  "$LEGACY_MIGRATION_TEST" \
  "runtime migration test must prove experiment tables leave the receipt store"
require_pattern "XCTAssertFalse\\(Self\\.sqliteTableExists\\(\"ZRECEIPT\", at: experimentsStoreURL\\)\\)" \
  "$LEGACY_MIGRATION_TEST" \
  "runtime migration test must prove receipt tables stay out of the experiments store"
require_pattern "testProductionReceiptAndExperimentContainersUseSeparateStores" \
  "$STORE_ISOLATION_TEST" \
  "runtime store isolation test must prove production receipt and experiment containers use separate stores"
require_pattern "PocketPalModelContainer\\.make\\(" \
  "$STORE_ISOLATION_TEST" \
  "runtime store isolation test must use the production receipt container factory"
require_pattern "PocketPalModelContainer\\.makeExperiments\\(" \
  "$STORE_ISOLATION_TEST" \
  "runtime store isolation test must use the production experiments container factory"
require_pattern "AccountingAccount\\(" \
  "$STORE_ISOLATION_TEST" \
  "runtime store isolation test must cover advanced accounting experiment tables"
require_pattern "XCTAssertFalse\\(Self\\.sqliteTableExists\\(\"ZCONNECTION\", at: receiptStoreURL\\)\\)" \
  "$STORE_ISOLATION_TEST" \
  "runtime store isolation test must keep connection tables out of the receipt store"
require_pattern "XCTAssertFalse\\(Self\\.sqliteTableExists\\(\"ZACCOUNTINGACCOUNT\", at: receiptStoreURL\\)\\)" \
  "$STORE_ISOLATION_TEST" \
  "runtime store isolation test must keep accounting tables out of the receipt store"
require_pattern "XCTAssertFalse\\(Self\\.sqliteTableExists\\(\"ZRECEIPT\", at: experimentsStoreURL\\)\\)" \
  "$STORE_ISOLATION_TEST" \
  "runtime store isolation test must keep receipt tables out of the experiments store"
require_pattern "testCollapsedSettingsDoesNotReadCloudAIKeychainState" \
  "$MAC_CORE_SETTINGS_TEST" \
  "macOS runtime test must prove default settings render does not read cloud AI keychain state"
require_pattern "SpyKeychainService" \
  "$MAC_CORE_SETTINGS_TEST" \
  "macOS settings runtime test must use a keychain spy"
require_pattern "XCTAssertEqual\\(keychainService\\.retrieveSecureStringCount, 0\\)" \
  "$MAC_CORE_SETTINGS_TEST" \
  "macOS settings runtime test must assert cloud AI keychain reads stay out of default settings render"
require_pattern "testFlagOnAccountingWorkspaceRendersWithExperimentStoreContainer" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must prove flag-on accounting workspace renders against the experiment store"
require_pattern "testDefaultWorkspaceIgnoresAccountingDestinationsAndRendersReceiptLedger" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must prove flag-off workspace stays on the receipt ledger"
require_pattern "setenv\\(\"POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE\", \"0\", 1\\)" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS default workspace runtime test must force the production flag off"
require_pattern "XCTAssertFalse\\(InfrastructureFeatureFlags\\.accountingWorkspaceEnabled\\)" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS default workspace runtime test must assert accounting is disabled"
require_pattern "XCTAssertFalse\\(MacWorkspaceDestination\\.enabledDestinations\\.contains\\(\\.banking\\)\\)" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS default workspace runtime test must keep accounting destinations out of the default workspace"
require_pattern "experimentsContainer: nil" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS default workspace runtime test must render without the experiments container"
require_pattern "POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must enable the accounting workspace through the production feature flag"
require_pattern "MacWorkspaceContentView\\(" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must instantiate the production workspace content"
require_pattern "selectedDestinationOverride: \\.banking" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must force an accounting destination"
require_pattern "NSHostingView" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must render the SwiftUI accounting workspace"
require_pattern "PocketPalModelContainer\\.make\\(" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must use the production receipt container factory"
require_pattern "PocketPalModelContainer\\.makeExperiments\\(" \
  "$MAC_ACCOUNTING_WORKSPACE_TEST" \
  "macOS runtime test must use the production experiments container factory"
require_pattern "testMacReceiptImportRunsLocalOCRAndExtractionInReceiptLedger" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS runtime test must prove the receipt import loop"
require_pattern "PocketPalModelContainer\\.make\\(isStoredInMemoryOnly: true, cloudSyncEnabled: false\\)" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must use a local in-memory receipt ledger"
require_pattern "ImportReceiptUseCase\\(" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must use the production import use case"
require_pattern "processingPolicy: \\.localOnly" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must keep cloud fallback disabled"
require_pattern "waitForOCRResult" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must wait for OCR completion"
require_pattern "XCTAssertEqual\\(receipts\\.count, 1\\)" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must prove Receipt row creation"
require_pattern "XCTAssertEqual\\(assets\\.count, 1\\)" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must prove ReceiptAsset row creation"
require_pattern "XCTAssertEqual\\(ocrResults\\.count, 1\\)" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must prove OCRResult row creation"
require_pattern "XCTAssertEqual\\(cloudProbe\\.makeCount, 0\\)" \
  "$MAC_RECEIPT_LOOP_TEST" \
  "macOS receipt loop test must prove cloud provider is not constructed"

require_pattern "@Query\\(sort: \\[SortDescriptor\\(\\\\Receipt\\.importedAt" \
  "$SETTINGS_VIEW" \
  "settings data management must query the receipt ledger only"
require_pattern "AdvancedCloudAISettingsSection\\(\\)" \
  "$SETTINGS_VIEW" \
  "settings must keep cloud AI controls behind the advanced cloud section"
require_pattern "DisclosureGroup\\(isExpanded" \
  "$SETTINGS_VIEW" \
  "cloud AI controls must stay collapsed behind an explicit advanced disclosure"
require_pattern "receipts: receipts\\.map\\(ReceiptExport\\.init\\)" \
  "$SETTINGS_VIEW" \
  "settings JSON export must serialize ReceiptExport rows"
require_pattern "\"receipts\\.csv\": FileWrapper\\(regularFileWithContents: makeCSVData\\(\\)\\)" \
  "$SETTINGS_VIEW" \
  "folder export must include the receipt CSV"
require_pattern "services\\.fileStorageService\\.fileURL\\(forRelativePath: relativePath\\)" \
  "$SETTINGS_VIEW" \
  "folder export must read receipt assets through the storage service"
require_pattern "FileManager\\.default\\.fileExists\\(atPath: sourceURL\\.path\\(percentEncoded: false\\)\\)" \
  "$SETTINGS_VIEW" \
  "folder export must use decoded file paths for asset existence checks"
require_order "try services\\.fileStorageService\\.removeAllStoredFiles\\(\\)" "modelContext\\.delete\\(receipt\\)" \
  "$SETTINGS_VIEW" \
  "clearing receipt data must remove stored files before staging Receipt deletions"
require_order "modelContext\\.delete\\(receipt\\)" "try modelContext\\.save\\(\\)" \
  "$SETTINGS_VIEW" \
  "clearing receipt data must save after staging Receipt deletions"
reject_pattern "\\b(Connection|BankTransaction|AccountingAccount|JournalEntryRecord|SyncLog)\\b" \
  "$SETTINGS_VIEW" \
  "settings export/delete must not depend on experimental accounting models"

require_pattern "@Query\\(sort: \\[SortDescriptor\\(\\\\Receipt\\.transactionDate" \
  "$TAX_REPORT_VIEW" \
  "tax report must query the receipt ledger only"
require_pattern "TaxExportService\\.makeConfirmedTaxCSVData\\(receipts: filteredReceipts\\)" \
  "$TAX_REPORT_VIEW" \
  "tax export must use only tax-ready Receipt rows"
require_pattern "static func makeTaxCSVData\\(receipts: \\[Receipt\\]\\) -> Data" \
  "$TAX_EXPORT_SERVICE" \
  "tax export service must accept Receipt rows directly"
reject_pattern "\\b(Connection|BankTransaction|AccountingAccount|JournalEntryRecord|SyncLog)\\b" \
  "$TAX_REPORT_VIEW" \
  "tax report must not depend on experimental accounting models"
reject_pattern "\\b(Connection|BankTransaction|AccountingAccount|JournalEntryRecord|SyncLog)\\b" \
  "$TAX_EXPORT_SERVICE" \
  "tax export service must not depend on experimental accounting models"

require_pattern "feature-flagged accounting UI must mount its own experiments-only" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must declare the accounting runtime isolation rule"
require_pattern "## Module ownership" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must keep the module ownership matrix"
require_pattern "Owner \\| Acceptance test \\| Deletion condition" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must name owner, acceptance test, and deletion condition"
require_pattern "Receipt ledger core" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must cover the receipt ledger core"
require_pattern "Receipt file storage" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must cover receipt file storage"
require_pattern "Cloud extraction" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must cover optional cloud extraction"
require_pattern "CloudKit sync" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must cover optional CloudKit sync"
require_pattern "Tax export" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must cover tax export"
require_pattern "Accounting workspace" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must cover the accounting experiment"
require_pattern "Email/e-commerce connections" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "module matrix must cover quarantined provider connections"
require_pattern "Accounting workspace flag-on smoke test" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must include the flag-on store-shape verification gate"
require_pattern "Manual import path invariant" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must bind the manual import path to the infrastructure verifier"
require_pattern "Receipt lifecycle export/delete invariant" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must bind receipt lifecycle export/delete to the infrastructure verifier"
require_pattern "Receipt file storage runtime test" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must bind local-first file storage to the infrastructure verifier"
require_pattern "Tax export runtime test" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must bind tax export runtime proof to the infrastructure verifier"
require_pattern "macOS receipt-loop runtime test" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must bind the macOS receipt loop proof to the infrastructure verifier"
require_pattern "PocketPal-iOSTests" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must include the runtime import infrastructure test gate"
require_pattern "Legacy combined-store runtime test" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must include the runtime legacy migration test gate"
require_pattern "Production store isolation runtime test" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must include the runtime production store isolation test gate"
require_pattern "Tools/RunInfrastructureGate.sh" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must declare the single infrastructure gate entry point"
require_pattern "InfrastructureCompletionAudit\\.md" \
  "PocketPal/Docs/InfrastructureRedesign.md" \
  "docs must link the completion audit"
require_pattern 'Status: pass when `Tools/RunInfrastructureGate\.sh` passes' \
  "$COMPLETION_AUDIT" \
  "completion audit must bind completion to the infrastructure gate"
require_pattern "Core loop imports one receipt asset" \
  "$COMPLETION_AUDIT" \
  "completion audit must cover the receipt import loop"
require_pattern "Tax-ready records export from the receipt ledger only" \
  "$COMPLETION_AUDIT" \
  "completion audit must cover tax export"
require_pattern "Core works with no network, no API key, and no CloudKit" \
  "$COMPLETION_AUDIT" \
  "completion audit must cover local-first operation"
require_pattern "Experimental models are quarantined from the receipt ledger" \
  "$COMPLETION_AUDIT" \
  "completion audit must cover experiment-store isolation"
require_pattern "Every retained module has owner, acceptance test, and deletion condition" \
  "$COMPLETION_AUDIT" \
  "completion audit must cover the module ownership rule"
require_pattern "Tools/RunInfrastructureGate.sh" \
  ".github/workflows/infrastructure.yml" \
  "GitHub Actions must call the same infrastructure gate script used locally"
require_pattern "ripgrep" \
  ".github/workflows/infrastructure.yml" \
  "GitHub Actions must install ripgrep for the verifier and log guards"
require_pattern "xcodegen generate" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must regenerate the Xcode project from project.yml"
require_pattern "Tools/VerifyInfrastructure.sh" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must run the static verifier"
require_pattern "PocketPal-iOS" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must run the iOS scheme"
require_pattern "PocketPal-macOS" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must run the macOS scheme"
require_pattern "macOS infrastructure tests" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must run macOS infrastructure tests"
require_pattern "reject_log_pattern" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must reject known macOS runtime-test infrastructure warnings"
require_pattern "SceneStorage\\|BUG IN CLIENT" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must fail on SwiftUI lifecycle misuse or open SQLite store teardown warnings"
require_pattern "CODE_SIGNING_ALLOWED=NO" \
  "Tools/RunInfrastructureGate.sh" \
  "infrastructure gate must disable code signing for repeatable local and CI validation"
require_pattern "^\\.build/$" \
  ".gitignore" \
  "infrastructure gate logs and DerivedData must stay ignored"
require_pattern "^\\.DS_Store$" \
  ".gitignore" \
  "macOS finder metadata must stay ignored"

printf 'PASS: infrastructure invariants hold\n'
