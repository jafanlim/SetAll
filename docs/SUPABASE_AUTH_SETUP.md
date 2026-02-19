# SetAll – Supabase Auth setup

## 1. Redirect URLs (fix “link goes to localhost” on iPhone)

Email confirmation and Google sign-in redirect the user back to your app. If the link points to `localhost`, it won’t work on a phone.

**In Supabase Dashboard:**

1. Go to **Authentication** → **URL Configuration**.
2. Set **Site URL** to your **deployed** web app URL, e.g.:
   - `https://your-app.vercel.app`
   - or your custom domain: `https://setall.example.com`
3. Under **Redirect URLs**, add the same URL (and with trailing slash if you use it), e.g.:
   - `https://your-app.vercel.app`
   - `https://your-app.vercel.app/**`
4. For local dev you can keep `http://localhost:PORT` in Redirect URLs so local testing still works.

**In the app:**

- In `lib/core/config/auth_config.dart`, set `kAuthRedirectBaseUrl` to that same URL, e.g. `https://your-app.vercel.app`.
- If you leave it `null`, the web app uses the current origin (correct when users are already on your production URL).

After this, when a user signs up and clicks the confirmation link in the email on their iPhone, they’ll open your **production** app and the session will be restored.

---

## 2. Emails from “SetAll” instead of Supabase

To send auth emails (e.g. confirm signup) from **SetAll** instead of the default Supabase sender:

1. In Supabase Dashboard go to **Project Settings** (gear) → **Auth**.
2. Under **SMTP Settings**, enable **Custom SMTP**.
3. Enter your SMTP provider (e.g. Resend, SendGrid, Mailgun, or your domain’s SMTP).
4. Set **Sender name** to `SetAll` and the **Sender email** to an address you control (e.g. `noreply@yourdomain.com`).

Alternatively, under **Authentication** → **Email Templates** you can edit the templates; some providers let you set a “from” name there. For full control (name + address), use Custom SMTP as above.

---

## 3. Google sign-in (“Unsupported provider: provider is not enabled”)

1. In [Google Cloud Console](https://console.cloud.google.com/) create or select a project.
2. **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID**.
3. Application type: **Web application** (for web).
4. Add **Authorized redirect URIs**:  
   `https://<YOUR-PROJECT-REF>.supabase.co/auth/v1/callback`  
   (find your project ref in Supabase Dashboard → Project Settings → General.)
5. Copy **Client ID** and **Client Secret**.
6. In Supabase: **Authentication** → **Providers** → **Google** → enable and paste Client ID and Secret.

After this, “Continue with Google” will work.
