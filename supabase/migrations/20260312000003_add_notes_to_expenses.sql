-- Long-form notes field; also stores content extracted from .txt / .md attachments
ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS notes TEXT;
