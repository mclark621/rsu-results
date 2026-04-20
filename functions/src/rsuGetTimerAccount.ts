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

export const rsuGetTimerAccount = onRequest({
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

  try {
    if (!admin.apps.length) admin.initializeApp();

    const idToken = getBearerToken(req.header("authorization"));
    if (!idToken) {
      res.status(401).json({ error: "missing_bearer_token", message: "Send Authorization: Bearer <Firebase ID token>" });
      return;
    }

    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = String(decoded.uid ?? "").trim();
    if (!uid) {
      res.status(401).json({ error: "invalid_token", message: "Token did not contain a uid" });
      return;
    }

    const docRef = admin.firestore().collection("rsu_timer_accounts").doc(uid);
    const snap = await docRef.get();
    if (!snap.exists) {
      res.status(404).json({ error: "not_found", message: `No timer account stored for uid ${uid}` });
      return;
    }

    const data = snap.data() ?? {};

    // Defense-in-depth: if a record has an ownerUid field, enforce it.
    const ownerUid = String((data as any).ownerUid ?? "").trim();
    if (ownerUid && ownerUid !== uid) {
      res.status(403).json({ error: "forbidden", message: "Timer account is not owned by this user" });
      return;
    }

    res.status(200).json({ uid, timerAccount: data });
  } catch (e: any) {
    res.status(500).json({ error: "internal_error", message: e?.message ?? String(e) });
  }
});
