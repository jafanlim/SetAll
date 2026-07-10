# Regional Date Format Resolution

## ADDED Requirements

### Requirement: System Region Drives Date Format on All Mobile/Desktop Platforms
The app SHALL resolve the effective date format from the operating system's REGION setting (not
the language locale) on iOS, Android, and macOS, via the `com.setall.app/region` platform
channel, falling back to the platform-dispatcher locale only where no handler exists (web,
Windows, Linux).

#### Scenario: English language, Georgian region (the reported bug)
- **WHEN** the device is set to Language=English, Region=Georgia
- **THEN** the app resolves locale `en_GE` and renders dates `dd/MM/yyyy` app-wide, and the Regional Settings screen displays the region-bearing locale

#### Scenario: US device
- **WHEN** the device is Language=English, Region=United States
- **THEN** dates render `MM/dd/yyyy` (unchanged behaviour)

#### Scenario: Channel unavailable
- **WHEN** the platform has no channel handler (web/Windows/Linux)
- **THEN** resolution falls back to the platform-dispatcher locale exactly as before this change

### Requirement: Manual Override Precedence
A manual date-format override in Regional Settings SHALL continue to take precedence over any
system-derived format.

#### Scenario: Override active
- **WHEN** the user enables manual override with `YYYY-MM-DD`
- **THEN** dates render `yyyy-MM-dd` regardless of system region
