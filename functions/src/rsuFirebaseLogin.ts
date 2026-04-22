import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function getBearerToken(reqAuthHeader: string | undefined): string {
  const raw = (reqAuthHeader ?? "").trim();
  const m = raw.match(/^Bearer\s+(.+)$/i);
  return m?.[1]?.trim() ?? "";
}

function parseRsuUser(payload: any): { userId: string; email: string; firstName: string; lastName: string } {
  const decoded = payload as Record<string, any>;
  const userNode = (decoded?.user && typeof decoded.user === "object") ? decoded.user : decoded;
  const userId = String(userNode?.user_id ?? userNode?.id ?? "").trim();
  const email = String(userNode?.email ?? "").trim();
  const firstName = String(userNode?.first_name ?? userNode?.firstname ?? "").trim();
  const lastName = String(userNode?.last_name ?? userNode?.lastname ?? "").trim();
  if (!userId) throw new Error("Could not parse user_id from RunSignup Get User response");
  return { userId, email, firstName, lastName };
}

function normalizeFirebaseUid(rsuUserId: string): string {
  // Firebase Auth UID must be <= 128 chars.
  return `rsu:${rsuUserId}`;
}

export const rsuFirebaseLogin = onRequest({
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (req, res) => {
  Object.entries(corsHeaders).forEach(([k, v]) => res.setHeader(k, v));
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed", allowed: ["POST", "OPTIONS"] });
    return;
  }

  const contentType = (req.get("content-type") ?? "").toLowerCase();
  if (!contentType.includes("application/json")) {
    res.status(415).json({ error: "unsupported_media_type", message: "Expected Content-Type: application/json" });
    return;
  }

  try {
    if (!admin.apps.length) admin.initializeApp();

    const rsuAccessToken = getBearerToken(req.header("authorization"));
    if (!rsuAccessToken) {
      res.status(401).json({ error: "missing_bearer_token", message: "Send Authorization: Bearer <RunSignup OAuth access token>" });
      return;
    }

    // Validate the RSU OAuth token and obtain the stable RSU user_id.
    // Per RunSignup docs, when using OAuth 2.0 you can omit the :user_id path param.
    const rsuUrl = new URL("https://api.runsignup.com/rest/user");
    rsuUrl.searchParams.set("format", "json");

    const upstream = await fetch(rsuUrl.toString(), {
      method: "GET",
      headers: {
        "Accept": "application/json",
        "Authorization": `Bearer ${rsuAccessToken}`,
      },
    });

    const text = await upstream.text();
    if (upstream.status !== 200) {
      res.status(401).json({
        error: "rsu_user_fetch_failed",
        status: upstream.status,
        body: text.slice(0, 2000),
      });
      return;
    }

    const rsuPayload = JSON.parse(text);
    const rsuUser = parseRsuUser(rsuPayload);

    const uid = normalizeFirebaseUid(rsuUser.userId);
    const customToken = await admin.auth().createCustomToken(uid, {
      provider: "runsignup",
      rsuUserId: rsuUser.userId,
      email: rsuUser.email,
      firstName: rsuUser.firstName,
      lastName: rsuUser.lastName,
    });

    res.status(200).json({
      firebaseCustomToken: customToken,
      rsuUser,
      uid,
    });
  } catch (e: any) {
    res.status(500).json({
      error: "internal_error",
      message: e?.message ?? String(e),
    });
  }
});
