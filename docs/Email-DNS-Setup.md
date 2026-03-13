# Email & DNS Setup — noreply@setall.app

## Overview

SetAll uses **Resend** to send transactional emails (invite notifications, test emails) from
`noreply@setall.app`. The domain `setall.app` is managed on **Cloudflare**.

---

## Step 1: Add Domain in Resend Dashboard

1. Go to [resend.com/domains](https://resend.com/domains) → **Add Domain**
2. Enter `setall.app`
3. Resend will display the exact DNS records to add — use **those** values (they include your unique DKIM selector).

---

## Step 2: Cloudflare DNS Records

Add the following records in Cloudflare → setall.app → **DNS** → Records.

> ⚠️ The DKIM `p=` value below is a placeholder. Replace with the actual key from your Resend dashboard.

### SPF Record
| Type | Name        | Content                                       | Proxy  |
|------|-------------|-----------------------------------------------|--------|
| TXT  | `setall.app` | `v=spf1 include:_spf.resend.com ~all`        | DNS only |

### DKIM Record
| Type  | Name                                     | Content                  | Proxy    |
|-------|------------------------------------------|--------------------------|----------|
| TXT   | `resend._domainkey.setall.app`           | *(copy from Resend dashboard)* | DNS only |

### DMARC Record
| Type | Name                 | Content                                                           | Proxy    |
|------|----------------------|-------------------------------------------------------------------|----------|
| TXT  | `_dmarc.setall.app`  | `v=DMARC1; p=quarantine; rua=mailto:dmarc@setall.app; pct=100`   | DNS only |

### MX Record (for bounce handling — optional but recommended)
| Type | Name        | Content                 | Priority | Proxy    |
|------|-------------|-------------------------|----------|----------|
| MX   | `setall.app` | `feedback-smtp.us-east-1.amazonses.com` | 10 | DNS only |

---

## Step 3: Cloudflare Settings

- **Proxy status:** All DNS records above must be **DNS only** (grey cloud), NOT proxied.
- **Email Routing:** If Cloudflare Email Routing is enabled for `setall.app`, ensure it does not
  conflict with the SPF record. If needed, disable Cloudflare Email Routing or adjust the SPF to
  include both: `v=spf1 include:_spf.resend.com include:_spf.mx.cloudflare.net ~all`

---

## Step 4: Verify in Resend

After adding the records, return to the Resend dashboard and click **Verify DNS Records**.
Propagation typically takes 5–30 minutes on Cloudflare.

Expected result: all three records (SPF, DKIM, DMARC) show ✓ green.

---

## Step 5: Configure Supabase Secret

The `send-test-email` edge function (and future email functions) read `RESEND_API_KEY` from
Supabase secrets:

```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Or via the Supabase dashboard: **Project Settings → Edge Functions → Secrets → Add secret**.

---

## Step 6: Update Supabase Auth Email Settings

In the Supabase dashboard → **Authentication → Email Templates**:

- **SMTP Host:** `smtp.resend.com`
- **SMTP Port:** `465`
- **SMTP User:** `resend`
- **SMTP Password:** *(your Resend API key)*
- **Sender name:** `SetAll`
- **Sender email:** `noreply@setall.app`

---

## Step 7: Test via Developer Settings

In the SetAll app (debug build):
1. Go to **Settings** → scroll to **Developer** section (visible in debug mode only)
2. Tap **Send Test Email**
3. A test email will be sent to your account email via `noreply@setall.app`
4. Check your inbox — you should receive it within seconds

---

## Deploy the Edge Function

```bash
supabase functions deploy send-test-email
```

---

## Reference

- Resend docs: https://resend.com/docs/send-with-supabase-smtp
- Cloudflare DNS: https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/
- DMARC spec: https://dmarc.org/overview/
