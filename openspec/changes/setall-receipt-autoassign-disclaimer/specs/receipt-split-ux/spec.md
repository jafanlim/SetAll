# Receipt Split UX — Auto-Assignment Transparency

## ADDED Requirements

### Requirement: Unassigned-Items Disclaimer
Wherever line items can be assigned to members (receipt entry sheet, edit-expense itemized
editor), the UI SHALL display a persistent, localized hint stating that items left unassigned
are charged to the payer.

#### Scenario: Receipt with unassigned items
- **WHEN** a recognized receipt's items are shown for assignment
- **THEN** the hint "Items left unassigned are charged to the payer" (localized) is visible without any user action

#### Scenario: Localization
- **WHEN** the app locale is any of en/de/es/fr/ka/ru
- **THEN** the hint renders in that locale
