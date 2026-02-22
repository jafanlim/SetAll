Mandatory Debugging Protocol (For Gemini CLI)

You are forbidden from generating "fix" code until you follow these steps.

Step 1: Evidence Audit

Read the provided Error Log/Stack Trace.

Locate the exact line of code mentioned in the trace.

Compare that line against the TECHNICAL_CONTEXT.md (Schema names).

Step 2: The "Why" Statement

Before providing code, write a 2-line explanation of WHY the error is happening.

If you are making an assumption about a file you haven't seen, you MUST ask for that file first.

Step 3: Minimalist Fix

Provide the fix for ONLY the affected lines.

Do not rewrite the entire file unless it is structurally necessary.

Ensure all financial math uses Decimal.parse().

Step 4: Regression Check

Explain if this fix affects any other part of the sync logic (e.g., if changing a Model affects the Repository).