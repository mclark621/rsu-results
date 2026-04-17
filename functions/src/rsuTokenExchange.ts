import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const rsuOauthClientSecret = defineSecret("RSU_OAUTH_CLIENT_SECRET");

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function readBodyStringField(rawBody: any, key: string): string {
  const v = (rawBody && typeof rawBody === "object") ? (rawBody as any)[key] : undefined;
  return String(v ?? "").trim();
}

export const rsuTokenExchange = onRequest({
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "256MiB",
  secrets: [rsuOauthClientSecret],
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
    const clientId = readBodyStringField(req.body, "client_id");
    const redirectUri = readBodyStringField(req.body, "redirect_uri");
    const code = readBodyStringField(req.body, "code");
    const codeVerifier = readBodyStringField(req.body, "code_verifier");

    if (!clientId || !redirectUri || !code || !codeVerifier) {
      res.status(400).json({
        error: "missing_params",
        required: ["client_id", "redirect_uri", "code", "code_verifier"],
      });
      return;
    }

    const secret = rsuOauthClientSecret.value().trim();
    if (!secret) {
      res.status(500).json({ error: "missing_server_secret", message: "RSU_OAUTH_CLIENT_SECRET is not configured." });
      return;
    }

    // RunSignup's auth-code redemption endpoint (matches the Flutter client direct exchange).
    // IMPORTANT: Keep the parameter names aligned with their expected payload.
    const body = new URLSearchParams();
    // OAuth2 Authorization Code + PKCE
    body.set("grant_type", "authorization_code");
    body.set("client_id", clientId);
    body.set("client_secret", secret);
    body.set("redirect_uri", redirectUri);
    body.set("code", code);
    body.set("code_verifier", codeVerifier);

    const upstream = await fetch("https://runsignup.com/rest/v2/auth/auth-code-redemption.json", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
      },
      body,
    });

    const text = await upstream.text();
    res.setHeader("Cache-Control", "no-store");

    if (upstream.status !== 200) {
      res.status(400).json({
        error: "token_exchange_failed",
        status: upstream.status,
        body: text.slice(0, 2000),
      });
      return;
    }

    // Return the OAuth payload as-is (JSON string), letting the client parse it.
    res.status(200).send(text);
  } catch (e: any) {
    res.status(500).json({
      error: "internal_error",
      message: e?.message ?? String(e),
    });
  }
});
