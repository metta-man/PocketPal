# Receipt review vertical slice

Goal: reduce the work needed to confirm a receipt and make formal tax export require explicit confirmation.

Scope: progressive disclosure in the shared detail editor; a stable review session from the current Inbox/Tax selection; advance only after successful confirmation; a shared validation rule for draft fields and persisted receipts; export regression tests. Preserve existing stored data, schema, unrelated workspace edits, and general-purpose backups.

Acceptance:
- Merchant, date, amount/currency and purpose are easy to reach; optional fields are disclosed separately. Required category issues remain visible.
- Confirm and next uses a snapshot of the selected list, skips already reviewed/deleted/unprocessed entries, and finishes without stacking detail pages.
- Save failure preserves draft input, restores this receipt's previous stored fields in memory, and never advances or rolls back unrelated changes.
- Complete but unconfirmed receipts cannot enter formal tax CSV; general ledger exports retain all records and their review status.
- iOS and macOS compile; infrastructure tests and static verifier pass. A real 20-receipt timing comparison remains manual QA.
