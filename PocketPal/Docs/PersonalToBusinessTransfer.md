# Personal records to business

## Scope
Allow a user to move every existing personal receipt and manual entry into the business workspace from Settings > Data Management on iOS and macOS. The batch includes reviewed/archive records, income and expenses. Confirmation captures the records currently shown in the count; later imports are not silently added to the batch.

## Behavior
- Show the personal record count and disable the action when empty.
- Require confirmation explaining preserved data, workspace movement and review reset.
- Update the original records to business, rebuild search text and mark them pending review. Preserve IDs, source files, asset/OCR relationships, amounts, notes and tax categories.
- Save the batch once. On failure, restore only the fields changed by this operation.
- Show the actual successful count. Skip records deleted or reclassified since confirmation opened.
- Leave existing business/reimbursable records and new-entry preferences unchanged.

## Verification
MacCoreSettingsInfrastructureTests covers successful persistence, original asset identity/path, manual income, existing business/reimbursable exclusion, duplicate inputs, repeat execution and batch restoration on save failure. Device interaction and production CloudKit sync require separate QA.
