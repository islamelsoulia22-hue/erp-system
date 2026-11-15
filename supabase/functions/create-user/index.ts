// Edge Function: create-user
// المدير فقط (users.manage) يقدر ينشئ حساب لموظف جديد ويديله دور.
// POST { email, password, full_name?, role_id? }
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

    // تحقق من هوية الطالب بتوكنه هو.
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

    // لازم يكون معاه صلاحية إدارة المستخدمين.
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
    const email = (body.email ?? "").toString().trim();
    const password = (body.password ?? "").toString();
    const fullName = (body.full_name ?? "").toString().trim();
    const roleId = body.role_id ? body.role_id.toString() : null;

    if (!email || password.length < 6) {
      return Response.json({ error: "INVALID_INPUT" }, {
        status: 400,
        headers: cors,
      });
    }
    if (roleId) {
      const { data: role } = await admin.from("roles").select("id").eq(
        "id",
        roleId,
      ).maybeSingle();
      if (!role) {
        return Response.json({ error: "ROLE_NOT_FOUND" }, {
          status: 400,
          headers: cors,
        });
      }
    }

    // إنشاء اليوزر (الإيميل متأكد تلقائيا) — تريجر handle_new_user
    // بينشئ الـ profile.
    const { data: created, error: createErr } = await admin.auth.admin
      .createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName },
      });
    if (createErr || !created?.user) {
      const msg = (createErr?.message ?? "").toLowerCase();
      const code = msg.includes("already") || msg.includes("registered")
        ? "EMAIL_EXISTS"
        : "CREATE_FAILED";
      return Response.json(
        { error: code, detail: createErr?.message ?? null },
        { status: 400, headers: cors },
      );
    }
    const newId = created.user.id;

    if (roleId) {
      const { error: roleErr } = await admin.from("user_roles").upsert({
        user_id: newId,
        role_id: roleId,
        assigned_by: callerId,
      });
      if (roleErr) {
        return Response.json(
          { error: "ROLE_ASSIGN_FAILED", id: newId },
          { status: 500, headers: cors },
        );
      }
    }

    await admin.from("audit_logs").insert({
      user_id: callerId,
      action: "CREATE",
      entity_type: "USER",
      entity_id: newId,
      new_data: { email, full_name: fullName, role_id: roleId },
    });

    return Response.json({ id: newId, email }, {
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
