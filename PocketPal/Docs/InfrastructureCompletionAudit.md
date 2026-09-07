# PocketPal Infrastructure Completion Audit

## Verdict

Status: pass when `Tools/RunInfrastructureGate.sh` passes on the current worktree.

The redesigned infrastructure now matches the first-principles target in `InfrastructureRedesign.md`: PocketPal is a local-first receipt ledger. Optional cloud, CloudKit, accounting, and provider-connection surfaces are isolated behind policies, feature flags, separate stores, or explicit deletion conditions.

## Requirement Evidence

| Requirement | Evidence | Status |
| --- | --- | --- |
| Core loop imports one receipt asset into app-owned storage | `ImportReceiptUseCaseInfrastructureTests.testImageImportCreatesReceiptAssetAndOCRWithoutCloudFallback`, `MacReceiptLoopInfrastructureTests.testMacReceiptImportRunsLocalOCRAndExtractionInReceiptLedger` | Pass |
| Local OCR and deterministic extraction preserve raw OCR separately from editable fields | `ImportReceiptUseCase` creates `OCRResult` and applies `ReceiptExtraction`; iOS and macOS receipt-loop tests assert `Receipt`, `ReceiptAsset`, and `OCRResult` rows | Pass |
| Review state is explicit and exportable | `Receipt.reviewStatus`, `Receipt.reviewedAt`, `TaxExportInfrastructureTests`, Settings CSV/JSON invariants in `Tools/VerifyInfrastructure.sh` | Pass |
| Tax-ready records export from the receipt ledger only | `TaxExportInfrastructureTests.testTaxExportSummarizesAndSerializesReceiptLedgerRows`, `TaxReportView` and `TaxExportService` verifier rejects for experimental models | Pass |
| Core works with no network, no API key, and no CloudKit | Runtime tests call `PocketPalModelContainer.make(... cloudSyncEnabled: false)`; local-only import tests assert cloud/keychain providers are not constructed; receipt file storage default is `.localOnly` | Pass |
| Receipt files stay local by default | `ReceiptFileStorageInfrastructureTests.testDefaultReceiptFileStorageStaysLocalWhenICloudIsAvailable`; verifier requires explicit `ReceiptFileStorageLocationPolicy` opt-in before iCloud probing | Pass |
| Optional cloud extraction is policy-driven, consent-gated, injectable, and lazy | `ReceiptProcessingPolicy`, `ImportReceiptUseCase` policy/order invariants, service-container/keychain runtime tests | Pass |
| CloudKit is optional and default-off | `CloudSyncConfiguration` default false unless env/user setting; `PocketPalModelContainer` uses `.automatic` only when `cloudSyncEnabled` is true and falls back local on CloudKit open failure | Pass |
| Experimental models are quarantined from the receipt ledger | `PocketPalModelContainer.make()` uses `receiptLedgerSchema`; `makeExperiments()` uses `experimentsSchema`; `PersistentStoreIsolationInfrastructureTests` proves table separation | Pass |
| Legacy combined stores split safely | `LegacyStoreMigrationInfrastructureTests.testLegacyCombinedStoreSplitsReceiptLedgerAndExperimentModels`; migration backs up to `MigrationBackups` and detects legacy metadata | Pass |
| Accounting workspace is feature-flagged and uses its own store/context | `MacAccountingWorkspaceInfrastructureTests`; verifier rejects `Receipt` in `AccountingView` and requires `.modelContainer(experimentsContainer)` | Pass |
| Default macOS workspace stays receipt-first | `MacAccountingWorkspaceInfrastructureTests.testDefaultWorkspaceIgnoresAccountingDestinationsAndRendersReceiptLedger` | Pass |
| Settings default render stays out of Cloud AI keychain state | `MacCoreSettingsInfrastructureTests.testCollapsedSettingsDoesNotReadCloudAIKeychainState` | Pass |
| Service graph launch does not eagerly construct credential/cloud providers | `ImportReceiptUseCaseInfrastructureTests.testServiceContainerInitializationDoesNotConstructCredentialOrCloudProviders` | Pass |
| Every retained module has owner, acceptance test, and deletion condition | `InfrastructureRedesign.md` module ownership matrix; verifier requires the matrix and module rows | Pass |
| One local/CI gate validates the infrastructure | `Tools/RunInfrastructureGate.sh`, `.github/workflows/infrastructure.yml`, `Tools/VerifyInfrastructure.sh` | Pass |

## Required Commands

Run:

```sh
Tools/RunInfrastructureGate.sh
```

Expected result on a passing worktree:

- Static verifier: pass
- iOS infrastructure tests: pass
- macOS infrastructure tests: pass
- macOS build: pass

## Residual Risk

- The worktree is intentionally broad and not yet committed. Treat this audit as implementation-complete only after packaging or committing the infrastructure reset.
- CloudKit remains optional code, not a proven user-facing sync workflow. The architecture allows it only behind explicit opt-in and local-store recovery.
- Accounting and provider connections remain quarantined experiments. Their deletion conditions must be enforced before adding any default-path UX.
