#!/usr/bin/env bash
# =============================================================================
# SetAll — Cloudflare DNS Automation Script
# Usage: CLOUDFLARE_TOKEN=<token> bash scripts/cloudflare_dns_setup.sh
#
# Adds all required DNS records for:
#   - Firebase Hosting (A records for setall.app + www)
#   - Resend mailing (SPF, DKIM, DMARC, MX)
#
# IMPORTANT: Before running, replace RESEND_DKIM_VALUE below with the
# actual p= value from your Resend dashboard → Domains → setall.app → DKIM.
# =============================================================================

set -euo pipefail

ZONE_ID="26842adc5985dc863a84b17189586b62"
TOKEN="${CLOUDFLARE_TOKEN:?Set CLOUDFLARE_TOKEN env var}"
API="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records"

# ── REPLACE THIS with actual value from Resend dashboard ─────────────────────
RESEND_DKIM_VALUE="p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDKMHWQ/Kt1ftO1bzmb+mC/gV/680y55Imd7F45LpMtjsxkZoeYR7eTw8d/1OvOuRlkfDwBt5niTn7UmMGXM5k7+MCSd1WXIagfQkz9H8WR7ynewOuL7lFfs8o7K30xr0BgkmqJEo4+MADEBgH+obBUDflbJgUeXWryRawRR3MfFwIDAQAB"
# ─────────────────────────────────────────────────────────────────────────────

add() {
  local label="$1"
  local payload="$2"
  local result
  result=$(curl -s -X POST "$API" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "$payload")
  if echo "$result" | python3 -c "import sys,json; r=json.load(sys.stdin); exit(0 if r.get('success') else 1)" 2>/dev/null; then
    echo "  ✓  $label"
  else
    local err
    err=$(echo "$result" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('errors',r))" 2>/dev/null || echo "$result")
    # Code 81058 = record already exists — treat as success
    if echo "$err" | grep -q "81058"; then
      echo "  ↩  $label (already exists)"
    else
      echo "  ✗  $label — $err" >&2
    fi
  fi
}

echo ""
echo "=== Firebase Hosting — A records ==="
add "setall.app A 151.101.1.195"  '{"type":"A","name":"setall.app","content":"151.101.1.195","ttl":1,"proxied":false}'
add "setall.app A 151.101.65.195" '{"type":"A","name":"setall.app","content":"151.101.65.195","ttl":1,"proxied":false}'
add "www        A 151.101.1.195"  '{"type":"A","name":"www","content":"151.101.1.195","ttl":1,"proxied":false}'
add "www        A 151.101.65.195" '{"type":"A","name":"www","content":"151.101.65.195","ttl":1,"proxied":false}'

echo ""
echo "=== Resend Mailing — SPF ==="
add "SPF TXT" '{"type":"TXT","name":"setall.app","content":"v=spf1 include:_spf.resend.com ~all","ttl":1,"proxied":false}'

echo ""
echo "=== Resend Mailing — DKIM ==="
add "DKIM TXT" "{\"type\":\"TXT\",\"name\":\"resend._domainkey.setall.app\",\"content\":\"${RESEND_DKIM_VALUE}\",\"ttl\":1,\"proxied\":false}"

echo ""
echo "=== Resend Mailing — DMARC ==="
add "DMARC TXT" '{"type":"TXT","name":"_dmarc.setall.app","content":"v=DMARC1; p=quarantine; rua=mailto:dmarc@setall.app; pct=100","ttl":1,"proxied":false}'

echo ""
echo "=== Resend Mailing — MX (bounce) ==="
add "MX" '{"type":"MX","name":"setall.app","content":"feedback-smtp.us-east-1.amazonses.com","ttl":1,"proxied":false,"priority":10}'

echo ""
echo "=== Current DNS records ==="
curl -s "${API}?per_page=100" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
records = d.get('result', [])
for r in records:
    print(f\"  {r['type']:<6} {r['name']:<45} {r['content'][:80]}\")
print(f\"\nTotal: {len(records)} records\")
"

echo ""
echo "Done. Next steps:"
echo "  1. Go to resend.com/domains → Add setall.app"
echo "  2. Copy the DKIM p= value and re-run this script with RESEND_DKIM_VALUE set"
echo "  3. Run: supabase secrets set RESEND_API_KEY=re_xxxx"
echo "  4. Run: supabase functions deploy send-test-email"
