# Tasks

## 1. UI
- [ ] 1.1 Hint row in `receipt_entry_sheet.dart` item-assignment section (persistent, info icon + text)
- [ ] 1.2 Same hint in `edit_expense_screen.dart` line-item editor

## 2. i18n
- [ ] 2.1 `receipt.unassigned_to_payer_hint` ×6 locales (en/de/es/fr/ka/ru)

## 3. Tests + gate
- [ ] 3.1 Widget tests: hint renders on both screens when line items exist
- [ ] 3.2 Locale-parity: key present in all 6 files
- [ ] 3.3 `flutter analyze` = 0; full suite green; additive diff; tick boxes in the PR
