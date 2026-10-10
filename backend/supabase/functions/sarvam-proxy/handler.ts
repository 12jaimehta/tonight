// Parent JWT in, transcript out. Audio stays in memory for the Sarvam call and is not stored.

export type ProxyLog = {
  latency_ms: number;
  cost: number;
};

export type ProxyDeps = {
  verifyJwt: (token: string) => Promise<{ parentId: string } | null>;
  lookupConsent: (input: {
    parentId: string;
    childProfileId: string;
    consentRecordId: string;
    consentVersion: string;
    accessToken: string;
  }) => Promise<boolean>;
  callSarvam: (input: {
    audio: Uint8Array;
    contentType: string;
    locale: string;
  }) => Promise<{ transcript: string; cost: number }>;
  log: (entry: ProxyLog) => void;
  now?: () => number;
};

const CHILD_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function logLine(entry: ProxyLog): string {
  return JSON.stringify({
    latency_ms: entry.latency_ms,
    cost: entry.cost,
  });
}

export async function handleSarvamProxy(req: Request, deps: ProxyDeps): Promise<Response> {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const header = req.headers.get("authorization");
  if (!header) {
    return json({ error: "missing_token" }, 401);
  }
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  if (!match) {
    return json({ error: "missing_token" }, 401);
  }
  const token = match[1];

  let session: { parentId: string } | null;
  try {
    session = await deps.verifyJwt(token);
  } catch {
    return json({ error: "invalid_token" }, 401);
  }
  if (!session?.parentId) {
    return json({ error: "invalid_token" }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return json({ error: "invalid_json" }, 400);
    }
    payload = parsed as Record<string, unknown>;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const childProfileId = textField(payload, "child_profile_id");
  if (!childProfileId || !CHILD_ID.test(childProfileId)) {
    return json({ error: "child_required" }, 400);
  }
  const audioBase64 = textField(payload, "audio_base64");
  if (!audioBase64) {
    return json({ error: "audio_required" }, 400);
  }
  const locale = textField(payload, "locale");
  if (!locale) {
    return json({ error: "locale_required" }, 400);
  }
  const consentRecordId = textField(payload, "consent_record_id");
  if (!consentRecordId || !CHILD_ID.test(consentRecordId)) {
    return json({ error: "consent_record_required" }, 400);
  }
  const consentVersion = textField(payload, "consent_version");
  if (!consentVersion) {
    return json({ error: "consent_version_required" }, 400);
  }
  // The contract body does not carry a content type. Clips are WAV.
  const contentType = "audio/wav";

  let allowed = false;
  try {
    allowed = await deps.lookupConsent({
      parentId: session.parentId,
      childProfileId,
      consentRecordId,
      consentVersion,
      accessToken: token,
    });
  } catch {
    return json({ error: "consent_lookup_failed" }, 503);
  }
  if (!allowed) {
    return json({ error: "consent_required" }, 403);
  }

  const audio = decodeBase64(audioBase64);
  if (!audio || audio.byteLength === 0) {
    return json({ error: "invalid_audio" }, 400);
  }

  const now = deps.now ?? Date.now;
  const started = now();
  let result: { transcript: string; cost: number };
  try {
    result = await deps.callSarvam({ audio, contentType, locale });
  } catch {
    return json({ error: "speech_provider_failed" }, 502);
  }
  const latencyMs = Math.max(0, now() - started);
  const cost = typeof result.cost === "number" && Number.isFinite(result.cost) ? result.cost : 0;
  deps.log({ latency_ms: latencyMs, cost });
  return json({ transcript: result.transcript, latencyMs, cost: formatCost(cost) }, 200);
}

function formatCost(cost: number): string {
  if (!Number.isFinite(cost) || cost === 0) return "0";
  return cost.toFixed(6).replace(/\.?0+$/, "");
}

function textField(payload: Record<string, unknown>, key: string): string | null {
  const value = payload[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function decodeBase64(value: string): Uint8Array | null {
  try {
    const normalized = value.replace(/\s/g, "");
    const binary = atob(normalized);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
