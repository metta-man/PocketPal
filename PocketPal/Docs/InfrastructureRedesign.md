# PocketPal Infrastructure Redesign

## 2026-09-07 Gemini update

The cloud provider is now Gemini 3.5 Flash-Lite. With a Gemini key and separate Google upload consent, every new image/PDF uses Gemini as the authoritative machine extraction, including when local OCR fails. The local-only launch/import contract remains unchanged. This supersedes the OpenAI/low-confidence-only statements below; see `GeminiReceiptSetup.md` for current behavior and verification.


## First-principles verdict

PocketPal is not an accounting suite. It is a local-first receipt ledger that turns messy purchase evidence into reviewed, searchable, tax-ready records.

Everything else is optional payload.

## Asymptotic target

The minimum viable infrastructure is:

1. Import one receipt asset into app-owned storage.
2. Run local OCR and deterministic extraction.
3. Preserve the raw OCR payload and the editable business fields separately.
4. Make review state explicit.
5. Export tax-ready records.

The theoretical lower bound is one durable file copy, one OCR pass, one SwiftData transaction, and one CSV export. Any infrastructure that does not improve that loop must be deleted, feature-flagged, or moved out of the core path.

## Current idiot index

| Area | Current shape | Verdict |
| --- | --- | --- |
| Receipt import | Local file storage, OCR, extraction, review state | Core |
| Cloud extraction | Useful only after user consent and local failure | Optional fallback |
| CloudKit | Off by default, recoverable local store required | Optional sync |
| Email/e-commerce connections | Models exist before provider workflows are proven | Quarantine |
| Accounting workspace | Banking, invoices, projects, payroll, inventory inside the same app shell | Scope explosion |
| Tax export | Direct output from reviewed receipts | Core output |

## Target architecture

```text
App
  ServiceContainer
    Receipt core
      ReceiptFileStorageService
      VisionOCRService
      ReceiptExtractionService
      ImportReceiptUseCase
      ReceiptProcessingPolicy
    Optional enhancement
      FoundationModelReceiptRefinementService
      lazy OpenAIReceiptExtractionService provider
  Experimental modules
    AccountingModuleView
      BankStatementImportService

Persistence
  Receipt ledger schema
    Receipt
    ReceiptAsset
    OCRResult
    store: PocketPal.store
    receipt files local by default
    optional CloudKit sync
  Quarantined schema
    Connection
    SyncLog
    Accounting models retained for migration safety
    store: PocketPalExperiments.store
    no CloudKit
```

Legacy note: existing installs may still have a combined `PocketPal.store`. On startup, the app detects legacy experiment tables, copies the combined SQLite cluster into `MigrationBackups/`, rebuilds `PocketPal.store` as receipt-only, and copies quarantined records into `PocketPalExperiments.store`. The legacy combined-store fallback remains as a recovery path if split-store startup fails.

Runtime note: feature-flagged accounting UI must mount its own experiments-only `ModelContainer`. It must not query or mutate `Receipt` rows through the accounting subtree. If accounting needs receipt data later, it must use an explicit import/link adapter, not a shared SwiftData context.

## Operating rules

1. Core code must work with no network, no API key, and no CloudKit.
2. Optional cloud services must be policy-driven, consent-gated, injectable, and lazily constructed only when enhancement is attempted.
3. Advanced accounting UI stays feature-flagged and owns its own services until receipt import, review, and tax export are boring.
4. New provider integrations must ship as import adapters into `Receipt`, not as parallel ledgers.
5. Every new module needs an owner, an acceptance test, and a deletion condition before implementation.
6. Experimental models must use a separate SwiftData store. They do not get CloudKit until they prove they deserve to exist.
7. Feature flags must be true isolation boundaries. Turning on an experiment cannot change the core receipt ledger schema or model context.

## Module ownership

| Module | Owner | Acceptance test | Deletion condition |
| --- | --- | --- | --- |
| Receipt ledger core | Founder / Codex quality gate | `ImportReceiptUseCaseInfrastructureTests`, `MacReceiptLoopInfrastructureTests`, `TaxExportInfrastructureTests` | Never delete while PocketPal exists; only replace with an equivalent receipt-ledger adapter that passes the same gate |
| Receipt file storage | Founder / Codex quality gate | `ReceiptFileStorageInfrastructureTests` | Delete iCloud file placement unless there is explicit user opt-in, recovery UX, and a passing storage-location test |
| Cloud extraction | Founder / Codex quality gate | `testServiceContainerInitializationDoesNotConstructCredentialOrCloudProviders`, `testDefaultServiceContainerDoesNotConstructKeychainForLocalOnlyImport` | Delete automatic cloud enhancement if local extraction reaches acceptable review accuracy or if consent/configuration cannot be proven at runtime |
| CloudKit sync | Founder / Codex quality gate | `CloudSyncConfiguration` default-off verifier checks and `PocketPalModelContainer.make(... cloudSyncEnabled: false)` runtime tests | Delete CloudKit activation until there is explicit user opt-in, recovery UX, and production migration evidence |
| Tax export | Founder / Codex quality gate | `TaxExportInfrastructureTests` and Settings/Tax static invariants | Delete any export path that reads experimental stores or bypasses receipt readiness |
| Accounting workspace | Founder / Codex quality gate | `MacAccountingWorkspaceInfrastructureTests` and `PersistentStoreIsolationInfrastructureTests` | Delete the workspace if it requires receipt-store schema changes, default navigation exposure, CloudKit, or shared SwiftData contexts before real usage evidence |
| Email/e-commerce connections | Founder / Codex quality gate | Quarantine-only persistence checks in `LegacyStoreMigrationInfrastructureTests` and `PersistentStoreIsolationInfrastructureTests` | Delete connection models unless a provider ships as an import adapter into `Receipt` with owner, consent gate, and acceptance test |

## Execution sequence

1. Prove the receipt loop on iOS and macOS.
2. Improve extraction accuracy with local rules and Apple on-device refinement.
3. Keep OpenAI as a manual or low-confidence fallback only.
4. Harden tax export around the receipt ledger.
5. Revisit banking and accounting only after the core ledger has real usage evidence.

## Verification gates

Each infra change must pass:

- `Tools/RunInfrastructureGate.sh` is the single local and CI entry point for infrastructure validation.
- `InfrastructureCompletionAudit.md` records the requirement-by-requirement completion evidence.
- iOS simulator build for `PocketPal-iOS`.
- iOS simulator tests for `PocketPal-iOS` / `PocketPal-iOSTests`.
- macOS build for `PocketPal-macOS` when macOS code is touched.
- macOS hosted tests for `PocketPal-macOS` / `PocketPal-macOSTests` prove flag-on accounting UI still renders with the experiments-only container.
- macOS hosted tests also prove the collapsed default Settings screen does not read Cloud AI keychain state.
- macOS receipt-loop runtime test proves the shared import use case creates `Receipt`, `ReceiptAsset`, and `OCRResult` rows on macOS without constructing cloud providers.
- `Tools/VerifyInfrastructure.sh` passes before merging infra changes.
- Manual import path invariant in `Tools/VerifyInfrastructure.sh` proves imports still create `Receipt`, `ReceiptAsset`, and optional `OCRResult`.
- Receipt lifecycle export/delete invariant in `Tools/VerifyInfrastructure.sh` proves Settings and Tax exports only read `Receipt`, and receipt clearing removes stored files before deleting rows.
- Tax export runtime test in `PocketPal-iOSTests` proves tax summaries and CSV exports are derived from receipt-ledger rows, keep CSV escaping/BOM behavior, and exclude incomplete receipts from ready exports.
- Receipt file storage runtime test proves default storage stays local even when iCloud ubiquity is available; iCloud file placement requires an explicit opt-in policy.
- Cloud fallback remains disabled unless the policy, consent, and provider configuration all allow it.
- Keychain and OpenAI provider construction remain lazy; default launch and local-only import must not construct cloud credential services.
- Default macOS workspace shows the receipt ledger, not the advanced accounting experiment.
- macOS default workspace runtime test proves the flag-off workspace rejects accounting destinations and renders without an experiments container.
- `PocketPal.store` remains the receipt ledger store; `PocketPalExperiments.store` holds quarantined models.
- Accounting workspace flag-on smoke test keeps `Receipt` tables out of `PocketPalExperiments.store` and accounting tables out of `PocketPal.store`.
- Production store isolation runtime test in `PocketPal-iOSTests` proves `make()` and `makeExperiments()` create separate receipt-only and experiments-only stores.
- macOS accounting workspace runtime test in `PocketPal-macOSTests` renders an accounting destination with the receipt container at the app root and the experiments container at the accounting subtree.
- macOS core settings runtime test in `PocketPal-macOSTests` renders Settings with a keychain spy and proves Cloud AI stays out of the default Settings render path.
- Service container initialization runtime test proves launch graph construction does not evaluate keychain or cloud provider closures.
- Service container runtime import test proves local-only receipt import completes without constructing the lazy keychain provider.
- Legacy combined-store runtime test in `PocketPal-iOSTests` proves old combined stores split into receipt-only and experiments-only stores.
- Legacy combined-store fallback is allowed only as a recovery bridge, not as the target architecture.
