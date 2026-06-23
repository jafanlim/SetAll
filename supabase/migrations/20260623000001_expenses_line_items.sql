ALTER TABLE expenses ADD COLUMN IF NOT EXISTS line_items jsonb;
