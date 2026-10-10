import { createConsentLookup } from "./consent.ts";

const POLICY = "2026-10-09";
const CHILD = "11111111-1111-4111-8111-111111111111";

Deno.test("CG-09 a stale consent version is denied", async () => {
  const lookup = lookupReturning({
    version: "2020-01-01",
    scopes: ["on_device_speech", "server_speech"],
    withdrawn_at: null,
  });
  const allowed = await lookup({
    parentId: "parent-1",
    childProfileId: CHILD,
    accessToken: "token",
  });
  assertEquals(allowed, false);
});

Deno.test("CG-15 a withdrawn consent record is denied", async () => {
  const lookup = lookupReturning({
    version: POLICY,
    scopes: ["on_device_speech", "server_speech"],
    withdrawn_at: "2026-10-10T00:00:00Z",
  });
  const allowed = await lookup({
    parentId: "parent-1",
    childProfileId: CHILD,
    accessToken: "token",
  });
  assertEquals(allowed, false);
});

Deno.test("CG-08 the current version needs both speech scopes", async () => {
  const missingOnDevice = lookupReturning({
    version: POLICY,
    scopes: ["server_speech"],
    withdrawn_at: null,
  });
  assertEquals(
    await missingOnDevice({ parentId: "parent-1", childProfileId: CHILD, accessToken: "token" }),
    false,
  );
  const current = lookupReturning({
    version: POLICY,
    scopes: ["on_device_speech", "server_speech"],
    withdrawn_at: null,
  });
  assertEquals(
    await current({ parentId: "parent-1", childProfileId: CHILD, accessToken: "token" }),
    true,
  );
});

function lookupReturning(row: { version: string; scopes: string[]; withdrawn_at: string | null }) {
  return createConsentLookup({
    supabaseUrl: "https://project-ref.supabase.co",
    anonKey: "anon",
    policyVersion: POLICY,
    fetchImpl: async () =>
      new Response(JSON.stringify([row]), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
  });
}

function assertEquals(actual: unknown, expected: unknown) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right} but got ${left}`);
}
