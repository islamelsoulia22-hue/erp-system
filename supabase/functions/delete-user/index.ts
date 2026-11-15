// Edge Function: delete-user
// المدير فقط (users.manage) يقدر يحذف حساب نهائيا.
// ممنوع يحذف نفسه. حذف auth user بيشيل profile + roles (cascade).
// POST { user_id }
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const jwt = (req.headers.get("Authorization") ?? "").replace(
      "Bearer ",
      "",
    );
    if (!jwt) {
      return Response.json({ error: "NOT_AUTHENTICATED" }, {
        status: 401,
        headers: cors,
      });
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: callerData, error: callerErr } = await callerClient.auth
      .getUser(jwt);
    if (callerErr || !callerData?.user) {
      return Response.json({ error: "NOT_AUTHENTICATED" }, {
        status: 401,
        headers: cors,
      });
    }
    const callerId = callerData.user.id;
    const admin = createClient(supabaseUrl, serviceKey);

    const { data: myRoles } = await admin
      .from("user_roles")
      .select("role_id")
      .eq("user_id", callerId);
    const roleIds = ((myRoles ?? []) as Record<string, unknown>[]).map(
      (r) => r["role_id"] as string,
    );
    let hasManage = false;
    if (roleIds.length > 0) {
      const { data: rpRows } = await admin
        .from("role_permissions")
        .select("role_id, permissions!inner(key)")
        .in("role_id", roleIds);
      hasManage = ((rpRows ?? []) as Record<string, unknown>[]).some(
        (x) =>
          ((x["permissions"] ?? {}) as Record<string, unknown>)["key"] ===
            "users.manage",
      );
    }
    if (!hasManage) {
      return Response.json({ error: "NO_PERMISSION" }, {
        status: 403,
        headers: cors,
      });
    }

    const body = await req.json();
    const userId = (body.user_id ?? "").toString();
    if (!userId) {
      return Response.json({ error: "INVALID_INPUT" }, {
        status: 400,
        headers: cors,
      });
    }
    if (userId === callerId) {
      return Response.json({ error: "CANNOT_DELETE_SELF" }, {
        status: 400,
        headers: cors,
      });
    }

    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) {
      return Response.json(
        { error: "DELETE_FAILED", detail: delErr.message },
        { status: 400, headers: cors },
      );
    }

    await admin.from("audit_logs").insert({
      user_id: callerId,
      action: "DELETE",
      entity_type: "USER",
      entity_id: userId,
    });

    return Response.json({ deleted: userId }, {
      status: 200,
      headers: cors,
    });
  } catch (e) {
    return Response.json({ error: "UNKNOWN", detail: String(e) }, {
      status: 500,
      headers: cors,
    });
  }
});
