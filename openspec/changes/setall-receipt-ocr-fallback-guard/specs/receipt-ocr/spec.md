# Receipt OCR Reliability & Telemetry

## ADDED Requirements

### Requirement: Vision OCR Retry
The receipt-ingest function SHALL retry the Google Vision OCR call exactly once on transient
failure (HTTP 429, 5xx, or network error) with a short backoff, before falling back to the
vision-LLM path. Non-transient failures (400, 403) SHALL NOT be retried.

#### Scenario: Transient rate-limit
- **WHEN** the first Vision call returns 429 and the retry succeeds
- **THEN** the OCR-text path is used and the response meta reports `ocr: true`

#### Scenario: Persistent failure
- **WHEN** both Vision attempts fail
- **THEN** the function falls back to the gpt-4.1 vision path and meta reports `ocr: false` with a machine-readable `ocrFailReason`

### Requirement: Degraded-Mode Visibility
The receipt entry UI SHALL visibly distinguish a draft produced by the fallback vision-LLM path
(when a Vision key is configured) from a draft produced by the dedicated-OCR path, via a
persistent, non-blocking warning asking the user to verify item names, localized in all 6 locales.

#### Scenario: Fallback draft
- **WHEN** the ingest response carries `ocr: false` and `ocrFailReason != 'no_key'`
- **THEN** the warning chip is shown; the user can still edit/accept the draft normally

#### Scenario: OCR draft
- **WHEN** the response carries `ocr: true`
- **THEN** no warning is shown

### Requirement: OCR Failure Telemetry via Bug-Report Pipeline
Every degraded receipt recognition (Vision configured but failed) SHALL automatically submit a
report through the existing `bug_reports` Supabase insert — the same pipeline as the manual
bug-report button — carrying the failure reason, breadcrumb tail, device info, and app version.
The report SHALL NOT contain the receipt image or recognized item contents. Telemetry submission
SHALL be best-effort and SHALL NOT affect the receipt flow on failure. At most one report is
submitted per scan attempt.

#### Scenario: Vision quota exhausted
- **WHEN** a scan degrades with `ocrFailReason: 'quota'`
- **THEN** one `bug_reports` row is inserted with `severity: 'auto'` and a description identifying the OCR fallback and reason, and the DB trigger routes it into bug-triage as usual

#### Scenario: Telemetry insert fails offline
- **WHEN** the `bug_reports` insert throws (offline, RLS, etc.)
- **THEN** the error is swallowed and the receipt draft flow completes unaffected
