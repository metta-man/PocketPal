# Gemini receipt extraction

Goal: replace the default cloud extractor with Gemini 3.5 Flash-Lite, directly reading receipt images/PDFs rather than trusting local OCR candidates. Keep local-only use possible.

Scope: REST adapter and nullable structured fields; separate Gemini Keychain credential and upload consent; opt-in automatic extraction for every new supported receipt (not only low-confidence OCR); manual retry for unconfirmed receipts; safe replacement of machine fields and race protection; provider/network/pipeline tests on iOS and shared macOS build.

No schema migration, embedded API key, production deployment or bulk upload of existing receipts. Legacy OpenAI provenance and credentials remain readable/untouched. User enters their Gemini API key in Settings; no key is requested in chat. Live API quality and account access require that key and real receipt samples.
