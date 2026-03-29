import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const ADMIN_EMAILS = Deno.env.get("ADMIN_EMAILS")?.split(",") ?? [];

serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Auth check — get the calling user from the JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Create a client with the user's JWT to identify them
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Check if user is admin
    if (!ADMIN_EMAILS.includes(user.email ?? "")) {
      return new Response(JSON.stringify({ error: "Forbidden: admin only" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const { business_id, action } = await req.json();

    if (!business_id || !["approve", "reject"].includes(action)) {
      return new Response(
        JSON.stringify({ error: "Required: business_id and action (approve|reject)" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Use service role client to update (bypasses RLS)
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    const newStatus = action === "approve" ? "verified" : "rejected";

    const { data: business, error: updateError } = await adminClient
      .from("businesses")
      .update({ verification_status: newStatus })
      .eq("id", business_id)
      .eq("verification_status", "pending") // only act on pending requests
      .select("id, name, owner_id, verification_status")
      .single();

    if (updateError || !business) {
      return new Response(
        JSON.stringify({ error: "Business not found or not in pending state" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // Notify the business owner
    await adminClient.from("notifications").insert({
      user_id: business.owner_id,
      type: "verification_update",
      title: action === "approve"
        ? `${business.name} is now verified!`
        : `Verification update for ${business.name}`,
      body: action === "approve"
        ? "Your business patent has been reviewed and approved. Your business now shows a verified badge."
        : "Your business patent could not be verified. Please upload a clearer document and try again.",
      business_id: business.id,
      is_read: false,
    });

    return new Response(
      JSON.stringify({
        success: true,
        business_id: business.id,
        new_status: newStatus,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
