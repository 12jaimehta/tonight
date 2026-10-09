// HS256 check for the local JWT secret. Hosted projects that only have asymmetric
// signing keys fall back to Auth's /user endpoint. Neither path logs the token.

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export async function verifySupabaseJwt(
  token: string,
  secret: string,
): Promise<{ parentId: string } | null> {
  try {
    if (!token || !secret) return null;
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const [encodedHeader, encodedPayload, encodedSignature] = parts;
    const header = JSON.parse(bytesToText(base64UrlToBytes(encodedHeader))) as { alg?: string };
    const payload = JSON.parse(bytesToText(base64UrlToBytes(encodedPayload))) as { sub?: string; exp?: number };
    if (header.alg !== "HS256" || typeof payload.sub !== "string" || payload.sub.length === 0) {
      return null;
    }
    if (typeof payload.exp === "number" && payload.exp * 1000 <= Date.now()) {
      return null;
    }

    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const ok = await crypto.subtle.verify(
      "HMAC",
      key,
      bytesToBuffer(base64UrlToBytes(encodedSignature)),
      new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
    );
    if (!ok) return null;
    return { parentId: payload.sub };
  } catch {
    return null;
  }
}

export async function verifyWithAuthServer(
  token: string,
  deps: { supabaseUrl: string; anonKey: string; fetchImpl: FetchLike },
): Promise<{ parentId: string } | null> {
  if (!deps.supabaseUrl) return null;
  const response = await deps.fetchImpl(`${deps.supabaseUrl.replace(/\/$/, "")}/auth/v1/user`, {
    method: "GET",
    headers: {
      authorization: `Bearer ${token}`,
      apikey: deps.anonKey,
    },
  });
  if (!response.ok) {
    await response.body?.cancel();
    return null;
  }
  const body = await response.json();
  if (!body || typeof body !== "object") return null;
  const id = (body as { id?: unknown }).id;
  if (typeof id !== "string" || id.length === 0) return null;
  return { parentId: id };
}

export async function verifyParentJwt(
  token: string,
  deps: { jwtSecret: string; supabaseUrl: string; anonKey: string; fetchImpl: FetchLike },
): Promise<{ parentId: string } | null> {
  if (deps.jwtSecret) return verifySupabaseJwt(token, deps.jwtSecret);
  return verifyWithAuthServer(token, deps);
}

function bytesToBuffer(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  const copy = new ArrayBuffer(bytes.byteLength);
  const view = new Uint8Array(copy);
  view.set(bytes);
  return view;
}

function base64UrlToBytes(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToText(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}
