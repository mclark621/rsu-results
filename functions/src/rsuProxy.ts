import { onRequest } from "firebase-functions/v2/https";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-RSU-API-SECRET, x-rsu-api-secret",
};

function isAllowedTarget(rawUrl: string): boolean {
  try {
    const u = new URL(rawUrl);
    if (u.protocol !== "https:") return false;

    // Allow only RunSignup hosts we intentionally call.
    const allowedHosts = new Set(["runsignup.com", "api.runsignup.com"]);
    if (!allowedHosts.has(u.hostname)) return false;

    // Allow RunSignup REST endpoints we use.
    if (u.pathname.startsWith("/Rest/")) return true;
    if (u.pathname.startsWith("/rest/")) return true;
    if (u.pathname.startsWith("/Profile/")) return true;
    return false;
  } catch {
    return false;
  }
}

export const rsuProxy = onRequest({
  region: "us-central1",
  timeoutSeconds: 60,
  memory: "256MiB",
}, async (req, res) => {
  Object.entries(corsHeaders).forEach(([k, v]) => res.setHeader(k, v));
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed", allowed: ["GET", "OPTIONS"] });
    return;
  }

  const urlParam = (req.query.url ?? "").toString();
  if (!urlParam) {
    res.status(400).json({ error: "missing_url", message: "Query parameter 'url' is required." });
    return;
  }

  if (!isAllowedTarget(urlParam)) {
    res.status(400).json({ error: "invalid_target", message: "Target url is not allowed." });
    return;
  }

  const outgoingHeaders: Record<string, string> = {
    "Accept": req.get("accept") ?? "application/json",
  };

  // Timer API secret is passed as a header (never put this in the URL).
  const timerSecret = req.get("x-rsu-api-secret") ?? "";
  if (timerSecret) outgoingHeaders["X-RSU-API-SECRET"] = timerSecret;

  // RunSignup REST endpoints commonly accept OAuth tokens via `access_token` query parameter.
  // The Flutter web app calls this proxy with `Authorization: Bearer <token>` so we keep the
  // token out of the browser-visible URL and translate it server-side.
  let upstreamUrl = urlParam;
  const auth = req.get("authorization") ?? "";
  if (auth) {
    const m = auth.match(/^Bearer\s+(.+)$/i);
    if (m && m[1]) {
      try {
        const u = new URL(urlParam);
        if (!u.searchParams.get("access_token")) u.searchParams.set("access_token", m[1]);
        upstreamUrl = u.toString();
      } catch {
        // If URL parsing fails, fall back to passing the header through.
        outgoingHeaders["Authorization"] = auth;
      }
    } else {
      outgoingHeaders["Authorization"] = auth;
    }
  }

  try {
    const upstream = await fetch(upstreamUrl, { method: "GET", headers: outgoingHeaders });
    const bodyBuffer = Buffer.from(await upstream.arrayBuffer());

    // Pass-through some headers; avoid setting hop-by-hop headers.
    const contentType = upstream.headers.get("content-type");
    if (contentType) res.setHeader("Content-Type", contentType);

    // Prevent caching in browsers by default (safer for auth'd calls).
    res.setHeader("Cache-Control", "no-store");

    res.status(upstream.status).send(bodyBuffer);
  } catch (e: any) {
    res.status(502).json({
      error: "upstream_fetch_failed",
      message: e?.message ?? String(e),
      target: urlParam,
    });
  }
});
