-- Create private storage bucket for expense attachments
INSERT INTO storage.buckets (id, name, public)
VALUES ('expense-attachments', 'expense-attachments', false)
ON CONFLICT (id) DO NOTHING;

-- RLS: authenticated users can upload into their own folder ({uid}/...)
CREATE POLICY IF NOT EXISTS "Users upload own attachments"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'expense-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- RLS: authenticated users can read their own files
CREATE POLICY IF NOT EXISTS "Users read own attachments"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'expense-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- RLS: authenticated users can delete their own files
CREATE POLICY IF NOT EXISTS "Users delete own attachments"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'expense-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Add attachment_urls column (JSON array of storage paths, e.g. ["uid/expId/receipt.jpg"])
ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS attachment_urls TEXT;
