# Insight Improvement

## ADDED Requirements

### Requirement: Behavior Signal Capture
The system SHALL record insight engagement events per user, isolated by row-level security, without altering insight generation.

#### Scenario: Insight dismissed
- **WHEN** a user dismisses an insight
- **THEN** an `insight_signal` row with event `dismissed` is recorded, scoped to the user

#### Scenario: Chat follow-up
- **WHEN** a user asks a follow-up in chat
- **THEN** an event `followup` is recorded

### Requirement: Prompt Variant Promotion
The system SHALL promote a system-prompt variant only when it beats the baseline on both the locked evaluation set and the behavior signal, and SHALL never modify the evaluation set.

#### Scenario: Variant fails the eval set
- **WHEN** a candidate variant scores below baseline on the locked eval set
- **THEN** it is not promoted, regardless of behavior signal
