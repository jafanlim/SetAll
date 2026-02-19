// Supabase Edge Function: notify a user by email that they were added to a group.
// Deploy: supabase functions deploy notify-group-invite
// To actually send email, add a provider (e.g. Resend) and set RESEND_API_KEY in Supabase secrets.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  try {
    const { email, groupId, groupName } = await req.json();
    if (!email) {
      return new Response(JSON.stringify({ error: "email required" }), { status: 400 });
    }
    // TODO: send email via Resend/SendGrid, e.g.:
    // await fetch("https://api.resend.com/emails", { method: "POST", headers: { "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`, "Content-Type": "application/json" }, body: JSON.stringify({ from: "...", to: email, subject: "You were added to a group", html: `You were added to the group ${groupName || groupId}. Open the SetAll app to see it.` }) });
    console.log("Notify group invite:", email, groupId, groupName);
    return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" }, status: 200 });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
