# PocketPal MVP Architecture

## Proposed folder structure

```text
PocketPal/
  Sources/
    Shared/
      App/
      Domain/
        Models/
        Parsing/
        UseCases/
      Features/
        Inbox/
        ReceiptDetail/
        Archive/
        Shared/
      Persistence/
      Services/
      PreviewSupport/
      Platform/
        iOS/
        macOS/
```

This keeps SwiftUI features separate from domain rules and from infrastructure code. `Platform/` isolates scanner and import affordances that are not shared. `Services/` owns OCR, asset storage, and field extraction. `Persistence/` owns SwiftData schema and model-container setup.

## SwiftData schema

### `Receipt`

- Business record for one receipt.
- Stores extracted fields, review state, search text, and timestamps.
- Owns one `ReceiptAsset` and optionally one `OCRResult`.

### `ReceiptAsset`

- Stores permanent local asset metadata for the original imported file.
- Tracks relative storage paths instead of transient picker URLs.
- Supports image and PDF assets with an optional thumbnail path.

### `OCRResult`

- Stores raw OCR text and aggregate confidence.
- Decouples OCR provenance from editable receipt fields so future AI enrichment can append more derived records without rewriting the original OCR payload.

## Local file storage strategy

- Base directory: app-specific `Application Support/PocketPal/Receipts/`.
- Each receipt gets its own subdirectory named with the receipt UUID.
- Original imported file is copied into that directory as `original.<ext>`.
- Optional thumbnail is stored beside it as `thumbnail.jpg`.
- SwiftData stores only relative paths like `<receipt-id>/original.pdf`, not absolute sandbox paths.
- The storage service resolves absolute URLs at runtime, so the persistence layer stays stable if the app container moves between installs or future sync models.
- External picker URLs are copied immediately into app-controlled storage. The app never relies on the original external location after import.

## Future CloudKit insertion points

- Replace the local-only `ModelConfiguration` with a CloudKit-backed configuration in `PocketPalModelContainer`.
- Keep the asset storage service behind its protocol so later versions can swap local storage for local-plus-cloud mirroring.
- `OCRResult` is intentionally separate from `Receipt` so future AI extraction passes can add versioned enrichment records without mutating user-edited fields directly.
