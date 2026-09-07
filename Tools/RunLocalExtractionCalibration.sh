#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${LOCAL_EXTRACTION_CALIBRATION_BUILD_DIR:-$ROOT_DIR/.build/local-extraction-calibration}"
FIXTURE_DIR="${LOCAL_EXTRACTION_CALIBRATION_FIXTURE_DIR:-/tmp/pocketpal-receipt-smoke}"
mkdir -p "$BUILD_DIR" "$FIXTURE_DIR/img" "$FIXTURE_DIR/key"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool: $tool"
}

download_if_missing() {
  local url="$1"
  local path="$2"
  if [[ -s "$path" ]]; then
    return 0
  fi
  curl -fL -sS -o "$path" "$url"
}

require_tool curl
require_tool xcrun

printf '== Prepare SROIE receipt fixtures ==\n'
sample_ids=(000 001 002 003 004 005 006 007 008 009)
labeled_ids=(000 001 002 004 005 006 007 008 009)

for id in "${sample_ids[@]}"; do
  download_if_missing \
    "https://raw.githubusercontent.com/zzzDavid/ICDAR-2019-SROIE/master/data/img/$id.jpg" \
    "$FIXTURE_DIR/img/$id.jpg"
done

for id in "${labeled_ids[@]}"; do
  download_if_missing \
    "https://raw.githubusercontent.com/zzzDavid/ICDAR-2019-SROIE/master/data/key/$id.json" \
    "$FIXTURE_DIR/key/$id.json"
done

printf '== Build receipt calibration harness ==\n'
xcrun swiftc \
  -o "$BUILD_DIR/ReceiptExtractionSmokeTest" \
  Tools/ReceiptExtractionSmokeTest.swift \
  PocketPal/Sources/Shared/Domain/Parsing/AmountParser.swift \
  PocketPal/Sources/Shared/Domain/Models/ConnectionModels.swift \
  PocketPal/Sources/Shared/Domain/Models/ReceiptEnums.swift \
  PocketPal/Sources/Shared/App/AppPreferences.swift \
  PocketPal/Sources/Shared/Domain/Models/ReceiptExtraction.swift \
  PocketPal/Sources/Shared/Services/OCRPreferences.swift \
  PocketPal/Sources/Shared/Services/ReceiptCategoryClassifier.swift \
  PocketPal/Sources/Shared/Services/ReceiptExtractionService.swift \
  -framework Vision \
  -framework ImageIO

printf '== Run receipt calibration ==\n'
"$BUILD_DIR/ReceiptExtractionSmokeTest" \
  --key-dir "$FIXTURE_DIR/key" \
  --min-samples 9 \
  --min-merchant-matches 7 \
  --min-date-matches 9 \
  --min-total-matches 9 \
  "$FIXTURE_DIR"/img/*.jpg

printf '== Build statement calibration harness ==\n'
xcrun swiftc \
  -o "$BUILD_DIR/StatementImportSmokeTest" \
  Tools/StatementImportSmokeTest.swift \
  PocketPal/Sources/Shared/Domain/Parsing/AmountParser.swift \
  PocketPal/Sources/Shared/Domain/Models/ConnectionModels.swift \
  PocketPal/Sources/Shared/Domain/Models/ReceiptEnums.swift \
  PocketPal/Sources/Shared/App/AppPreferences.swift \
  PocketPal/Sources/Shared/Services/OCRPreferences.swift \
  PocketPal/Sources/Shared/Services/ReceiptCategoryClassifier.swift \
  PocketPal/Sources/Shared/Services/BankStatementImportService.swift \
  -framework PDFKit \
  -framework Vision \
  -framework AppKit \
  -framework CoreGraphics

printf '== Run statement calibration ==\n'
"$BUILD_DIR/StatementImportSmokeTest"

printf 'PASS: local receipt and statement extraction calibration completed\n'
