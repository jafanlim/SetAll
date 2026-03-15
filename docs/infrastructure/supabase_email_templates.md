# Supabase Email Templates — SetAll

> **Slate & Teal design** · Background `#020617` · Button `#14B8A6`

---

## ⚠️ Hook Status: DISABLED

The Supabase **"Send Email"** hook (`send-email` Edge Function) **MUST be disabled** for auth to work correctly.

**Why:** The hook was originally built to fix a PKCE token URL issue. That root cause turned out to be the auth flow type, not the email URL. Switching web to `AuthFlowType.implicit` resolved the cross-device confirmation issue natively. The hook was introducing rate limit problems (2/hr hard cap) and URL construction bugs.

**Where to verify:**
Dashboard → Authentication → Hooks → "Send Email" → must be **OFF**

The Edge Function code is preserved in `supabase/functions/send-email/index.ts` for reference / future use (e.g. if you want custom HTML via Resend).

---

## Supabase Dashboard Template Setup

Paste these HTML templates into:
**Dashboard → Authentication → Email Templates → [template name]**

Set the **redirect URL** in each template to: `https://setall.app`

---

## Shared Design System

| Token | Value |
|-------|-------|
| Background | `#020617` |
| Card background | `#0F172A` |
| Border | `#1E293B` |
| Body text | `#94A3B8` |
| Heading text | `#F1F5F9` |
| CTA button | `#14B8A6` |
| Button text | `#020617` |
| Footer text | `#334155` |
| Font stack | `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif` |

---

## 1. Confirm Signup

**Subject:** `Confirm your SetAll email address`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Confirm your SetAll email</title>
</head>
<body style="margin:0;padding:0;background:#020617;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;">Tap to verify your email address and activate your account.&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#020617;padding:40px 16px 24px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:540px;">

        <tr>
          <td style="padding:0 0 32px;text-align:center;">
            <span style="font-size:20px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">SetAll</span>
          </td>
        </tr>

        <tr>
          <td style="background:#0F172A;border-radius:16px;border:1px solid #1E293B;overflow:hidden;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="padding:48px 40px 40px;">
                  <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#334155;letter-spacing:1.5px;text-transform:uppercase;">Account confirmation</p>
                  <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#F1F5F9;line-height:1.2;letter-spacing:-0.5px;">Confirm your email</h1>
                  <p style="margin:0 0 6px;font-size:15px;color:#94A3B8;line-height:1.7;">You're one step away. Tap the button to verify</p>
                  <p style="margin:0 0 28px;font-size:15px;color:#F1F5F9;font-weight:600;line-height:1.7;">{{ .Email }}</p>

                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td align="center">
                        <a href="{{ .ConfirmationURL }}"
                           style="display:inline-block;background:#14B8A6;color:#020617;font-weight:700;font-size:15px;padding:15px 40px;border-radius:10px;text-decoration:none;letter-spacing:-0.1px;min-width:200px;text-align:center;">
                          Confirm Email Address
                        </a>
                      </td>
                    </tr>
                  </table>

                  <p style="margin:20px 0 0;font-size:12px;color:#334155;">Link expires in 24 hours.</p>
                  <p style="margin:24px 0 0;font-size:11px;color:#334155;line-height:1.8;">
                    Or copy this link into your browser:<br>
                    <a href="{{ .ConfirmationURL }}" style="color:#475569;word-break:break-all;">{{ .ConfirmationURL }}</a>
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:28px 0 0;text-align:center;">
            <p style="margin:0 0 6px;font-size:11px;color:#1E293B;line-height:1.7;">SetAll App · Dubai, UAE</p>
            <p style="margin:0;font-size:11px;color:#1E293B;line-height:1.7;">
              <a href="https://setall.app" style="color:#1E293B;text-decoration:underline;">setall.app</a>
              &nbsp;&middot;&nbsp;
              <a href="https://setall.app/privacy" style="color:#1E293B;text-decoration:underline;">Privacy</a>
              &nbsp;&middot;&nbsp;
              <a href="mailto:support@setall.app" style="color:#1E293B;text-decoration:underline;">Support</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>
```

---

## 2. Password Reset

**Subject:** `Reset your SetAll password`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Reset your SetAll password</title>
</head>
<body style="margin:0;padding:0;background:#020617;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;">A password reset was requested for your account.&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#020617;padding:40px 16px 24px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:540px;">

        <tr>
          <td style="padding:0 0 32px;text-align:center;">
            <span style="font-size:20px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">SetAll</span>
          </td>
        </tr>

        <tr>
          <td style="background:#0F172A;border-radius:16px;border:1px solid #1E293B;overflow:hidden;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="padding:48px 40px 40px;">
                  <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#334155;letter-spacing:1.5px;text-transform:uppercase;">Security</p>
                  <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#F1F5F9;line-height:1.2;letter-spacing:-0.5px;">Reset your password</h1>
                  <p style="margin:0 0 6px;font-size:15px;color:#94A3B8;line-height:1.7;">We received a reset request for</p>
                  <p style="margin:0 0 28px;font-size:15px;color:#F1F5F9;font-weight:600;line-height:1.7;">{{ .Email }}</p>

                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td align="center">
                        <a href="{{ .ConfirmationURL }}"
                           style="display:inline-block;background:#14B8A6;color:#020617;font-weight:700;font-size:15px;padding:15px 40px;border-radius:10px;text-decoration:none;letter-spacing:-0.1px;min-width:200px;text-align:center;">
                          Reset Password
                        </a>
                      </td>
                    </tr>
                  </table>

                  <p style="margin:20px 0 0;font-size:12px;color:#334155;">Expires in 1 hour. If you didn't request this, ignore this email — your password won't change.</p>
                  <p style="margin:24px 0 0;font-size:11px;color:#334155;line-height:1.8;">
                    Or copy this link into your browser:<br>
                    <a href="{{ .ConfirmationURL }}" style="color:#475569;word-break:break-all;">{{ .ConfirmationURL }}</a>
                  </p>
                </td>
              </tr>
              <tr>
                <td style="padding:0 40px 40px;">
                  <div style="border-top:1px solid #1E293B;padding-top:20px;">
                    <p style="margin:0;font-size:12px;color:#334155;line-height:1.6;">
                      SetAll will never ask for your password by email. Contact
                      <a href="mailto:support@setall.app" style="color:#475569;">support@setall.app</a> if concerned.
                    </p>
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:28px 0 0;text-align:center;">
            <p style="margin:0 0 6px;font-size:11px;color:#1E293B;line-height:1.7;">SetAll App · Dubai, UAE</p>
            <p style="margin:0;font-size:11px;color:#1E293B;line-height:1.7;">
              <a href="https://setall.app" style="color:#1E293B;text-decoration:underline;">setall.app</a>
              &nbsp;&middot;&nbsp;
              <a href="https://setall.app/privacy" style="color:#1E293B;text-decoration:underline;">Privacy</a>
              &nbsp;&middot;&nbsp;
              <a href="mailto:support@setall.app" style="color:#1E293B;text-decoration:underline;">Support</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>
```

---

## 3. Magic Link

**Subject:** `Your SetAll sign-in link`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Sign in to SetAll</title>
</head>
<body style="margin:0;padding:0;background:#020617;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;">Your one-tap sign-in link is ready.&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#020617;padding:40px 16px 24px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:540px;">

        <tr>
          <td style="padding:0 0 32px;text-align:center;">
            <span style="font-size:20px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">SetAll</span>
          </td>
        </tr>

        <tr>
          <td style="background:#0F172A;border-radius:16px;border:1px solid #1E293B;overflow:hidden;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="padding:48px 40px 40px;">
                  <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#334155;letter-spacing:1.5px;text-transform:uppercase;">Sign in</p>
                  <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#F1F5F9;line-height:1.2;letter-spacing:-0.5px;">Your sign-in link</h1>
                  <p style="margin:0 0 6px;font-size:15px;color:#94A3B8;line-height:1.7;">Sign in as</p>
                  <p style="margin:0 0 28px;font-size:15px;color:#F1F5F9;font-weight:600;line-height:1.7;">{{ .Email }}</p>

                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td align="center">
                        <a href="{{ .ConfirmationURL }}"
                           style="display:inline-block;background:#14B8A6;color:#020617;font-weight:700;font-size:15px;padding:15px 40px;border-radius:10px;text-decoration:none;letter-spacing:-0.1px;min-width:200px;text-align:center;">
                          Sign In to SetAll
                        </a>
                      </td>
                    </tr>
                  </table>

                  <p style="margin:20px 0 0;font-size:12px;color:#334155;">This link expires in 1 hour and can only be used once.</p>
                  <p style="margin:24px 0 0;font-size:11px;color:#334155;line-height:1.8;">
                    Or copy this link into your browser:<br>
                    <a href="{{ .ConfirmationURL }}" style="color:#475569;word-break:break-all;">{{ .ConfirmationURL }}</a>
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:28px 0 0;text-align:center;">
            <p style="margin:0 0 6px;font-size:11px;color:#1E293B;line-height:1.7;">SetAll App · Dubai, UAE</p>
            <p style="margin:0;font-size:11px;color:#1E293B;line-height:1.7;">
              <a href="https://setall.app" style="color:#1E293B;text-decoration:underline;">setall.app</a>
              &nbsp;&middot;&nbsp;
              <a href="https://setall.app/privacy" style="color:#1E293B;text-decoration:underline;">Privacy</a>
              &nbsp;&middot;&nbsp;
              <a href="mailto:support@setall.app" style="color:#1E293B;text-decoration:underline;">Support</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>
```

---

## 4. Email Change — New Address

**Subject:** `Confirm your new SetAll email`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Confirm new email</title>
</head>
<body style="margin:0;padding:0;background:#020617;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;">Confirm your new email address.&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#020617;padding:40px 16px 24px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:540px;">

        <tr>
          <td style="padding:0 0 32px;text-align:center;">
            <span style="font-size:20px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">SetAll</span>
          </td>
        </tr>

        <tr>
          <td style="background:#0F172A;border-radius:16px;border:1px solid #1E293B;overflow:hidden;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="padding:48px 40px 40px;">
                  <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#334155;letter-spacing:1.5px;text-transform:uppercase;">Email change</p>
                  <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#F1F5F9;line-height:1.2;letter-spacing:-0.5px;">Confirm new email</h1>
                  <p style="margin:0 0 6px;font-size:15px;color:#94A3B8;line-height:1.7;">Tap below to confirm your new address:</p>
                  <p style="margin:0 0 28px;font-size:15px;color:#F1F5F9;font-weight:600;line-height:1.7;">{{ .Email }}</p>

                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td align="center">
                        <a href="{{ .ConfirmationURL }}"
                           style="display:inline-block;background:#14B8A6;color:#020617;font-weight:700;font-size:15px;padding:15px 40px;border-radius:10px;text-decoration:none;letter-spacing:-0.1px;min-width:200px;text-align:center;">
                          Confirm New Email
                        </a>
                      </td>
                    </tr>
                  </table>

                  <p style="margin:24px 0 0;font-size:11px;color:#334155;line-height:1.8;">
                    Or copy this link into your browser:<br>
                    <a href="{{ .ConfirmationURL }}" style="color:#475569;word-break:break-all;">{{ .ConfirmationURL }}</a>
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:28px 0 0;text-align:center;">
            <p style="margin:0 0 6px;font-size:11px;color:#1E293B;line-height:1.7;">SetAll App · Dubai, UAE</p>
            <p style="margin:0;font-size:11px;color:#1E293B;line-height:1.7;">
              <a href="https://setall.app" style="color:#1E293B;text-decoration:underline;">setall.app</a>
              &nbsp;&middot;&nbsp;
              <a href="https://setall.app/privacy" style="color:#1E293B;text-decoration:underline;">Privacy</a>
              &nbsp;&middot;&nbsp;
              <a href="mailto:support@setall.app" style="color:#1E293B;text-decoration:underline;">Support</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>
```

---

## 5. Email Change — Current Address Notice

**Subject:** `Your SetAll email is being changed`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Email change notice</title>
</head>
<body style="margin:0;padding:0;background:#020617;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;">Your email address is being changed.&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#020617;padding:40px 16px 24px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:540px;">

        <tr>
          <td style="padding:0 0 32px;text-align:center;">
            <span style="font-size:20px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">SetAll</span>
          </td>
        </tr>

        <tr>
          <td style="background:#0F172A;border-radius:16px;border:1px solid #1E293B;overflow:hidden;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="padding:48px 40px 40px;">
                  <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#334155;letter-spacing:1.5px;text-transform:uppercase;">Security notice</p>
                  <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#F1F5F9;line-height:1.2;letter-spacing:-0.5px;">Email change notice</h1>
                  <p style="margin:0 0 28px;font-size:15px;color:#94A3B8;line-height:1.7;">A request was made to change the email on your account. If this wasn't you, contact support immediately.</p>
                  <p style="margin:24px 0 0;font-size:12px;color:#334155;">If you requested this change, no action is needed.</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:28px 0 0;text-align:center;">
            <p style="margin:0 0 6px;font-size:11px;color:#1E293B;line-height:1.7;">SetAll App · Dubai, UAE</p>
            <p style="margin:0;font-size:11px;color:#1E293B;line-height:1.7;">
              <a href="https://setall.app" style="color:#1E293B;text-decoration:underline;">setall.app</a>
              &nbsp;&middot;&nbsp;
              <a href="https://setall.app/privacy" style="color:#1E293B;text-decoration:underline;">Privacy</a>
              &nbsp;&middot;&nbsp;
              <a href="mailto:support@setall.app" style="color:#1E293B;text-decoration:underline;">Support</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>
```

---

## Supabase Template Variables

| Variable | Description |
|----------|-------------|
| `{{ .Email }}` | Recipient email address |
| `{{ .ConfirmationURL }}` | Full action URL (built by GoTrue, includes token + redirect) |
| `{{ .Token }}` | OTP token (6-digit code, if using OTP flow) |
| `{{ .TokenHash }}` | Token hash (internal use) |
| `{{ .SiteURL }}` | Project site URL |

---

## Auth Flow Architecture

```
User registers at setall.app/login (web, implicit flow)
        ↓
GoTrue sends confirmation email with {{ .ConfirmationURL }}
        ↓
User clicks link (any browser, any device) ✓
        ↓
GoTrue /verify validates token → redirects to setall.app/#access_token=xxx
        ↓
Flutter getSessionFromUrl() picks up #access_token from fragment
        ↓
main.dart marks registration_complete = true (provider == 'email')
        ↓
Router redirect allows through to dashboard ✓
```

**Mobile** uses `AuthFlowType.pkce` (via `_initSupabase()`).  
**Web** uses `AuthFlowType.implicit` (fragment tokens, cross-device safe).

---

*Last updated: 2026-03-15*
