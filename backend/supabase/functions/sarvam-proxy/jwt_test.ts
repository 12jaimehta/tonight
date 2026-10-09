import { verifyParentJwt, verifySupabaseJwt, type FetchLike } from "./jwt.ts";

const SECRET = "test-secret-with-at-least-32-characters";

Deno.test("HS256 parent token verifies and a bad signature does not", async () => {
  const token = await sign({ sub: "parent-1", exp: Math.floor(Date.now() / 1000) + 60 }, SECRET);
  const ok = await verifySupabaseJwt(token, SECRET);
  assertEquals(ok, { parentId: "parent-1" });

  const flipped = token.slice(0, -2) + (token.endsWith("a") ? "b" : "a");
  assertEquals(await verifySupabaseJwt(flipped, SECRET), null);
  assertEquals(await verifySupabaseJwt(token, "other-secret-with-at-least-32-characters"), null);
});

Deno.test("auth server fallback reads only the parent id", async () => {
  let called = "";
  const fetchImpl: FetchLike = async (input, init) => {
    called = `${input} ${new Headers(init?.headers).get("authorization")}`;
    return new Response(JSON.stringify({ id: "parent-9", email: "hidden@example.com" }), { status: 200 });
  };
  const session = await verifyParentJwt("header.payload.sig", {
    jwtSecret: "",
    supabaseUrl: "http://127.0.0.1:54321",
    anonKey: "anon",
    fetchImpl,
  });
  assertEquals(session, { parentId: "parent-9" });
  assertEquals(called, "http://127.0.0.1:54321/auth/v1/user Bearer header.payload.sig");
});

async function sign(payload: Record<string, unknown>, secret: string): Promise<string> {
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = base64Url(new TextEncoder().encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${body}`)));
  return `${header}.${body}.${base64Url(signature)}`;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function assertEquals(actual: unknown, expected: unknown) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right} but got ${left}`);
}
