import { handleSarvamProxy, logLine, type ProxyDeps, type ProxyLog } from "./handler.ts";

const CHILD = "11111111-1111-4111-8111-111111111111";
const CONSENT = "22222222-2222-4222-8222-222222222222";
const CONSENT_VERSION = "2026-10-09";
const AUDIO_TEXT = "AUDIO_MARKER_DO_NOT_LOG";
const TRANSCRIPT = "TRANSCRIPT_MARKER_DO_NOT_LOG";
const AUDIO_BASE64 = btoa(AUDIO_TEXT);

function contractBody(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    child_profile_id: CHILD,
    audio_base64: AUDIO_BASE64,
    locale: "en-IN",
    consent_record_id: CONSENT,
    consent_version: CONSENT_VERSION,
    ...extra,
  };
}

Deno.test("missing JWT is rejected and does not call Sarvam", async () => {
  const seen = tracker();
  const response = await handleSarvamProxy(request(null, contractBody()), seen.deps);
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "missing_token" });
  assertEquals(seen.sarvamCalls, 0);
  assertEquals(seen.consentCalls, 0);
  assertEquals(seen.logs, []);
});

Deno.test("invalid JWT is rejected and does not call Sarvam", async () => {
  const seen = tracker({ parentId: null });
  const response = await handleSarvamProxy(
    request("not-a-jwt", contractBody()),
    seen.deps,
  );
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "invalid_token" });
  assertEquals(seen.sarvamCalls, 0);
  assertEquals(seen.consentCalls, 0);
});

Deno.test("consent denied returns 403 and does not call Sarvam", async () => {
  const seen = tracker({ parentId: "parent-1", consent: false });
  const response = await handleSarvamProxy(
    request("parent-token", contractBody({ nickname: "should-not-matter" })),
    seen.deps,
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "consent_required" });
  assertEquals(seen.sarvamCalls, 0);
  assertEquals(seen.consentCalls, 1);
  assertEquals(seen.consentChild, CHILD);
  assertEquals(seen.logs, []);
});

Deno.test("consent granted returns the transcript and logs latency and cost only", async () => {
  let clock = 1_000;
  const seen = tracker({
    parentId: "parent-1",
    consent: true,
    transcript: TRANSCRIPT,
    cost: 0.42,
    now: () => {
      const value = clock;
      clock += 250;
      return value;
    },
  });
  const response = await handleSarvamProxy(
    request("parent-token", contractBody({ locale: "hi-IN" })),
    seen.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { transcript: TRANSCRIPT, latencyMs: 250, cost: "0.42" });
  assertEquals(seen.sarvamCalls, 1);
  assertEquals(seen.logs, [{ latency_ms: 250, cost: 0.42 }]);
  const logged = JSON.stringify(seen.logs);
  assertEquals(logged.includes(AUDIO_BASE64), false);
  assertEquals(logged.includes(AUDIO_TEXT), false);
  assertEquals(logged.includes(TRANSCRIPT), false);
  assertEquals(logged.includes("parent-token"), false);
  assertEquals(Object.keys(seen.logs[0]).sort(), ["cost", "latency_ms"]);
});

Deno.test("the contract body is required before consent or Sarvam", async () => {
  const seen = tracker({ parentId: "parent-1", consent: true });
  const missingChild = await handleSarvamProxy(
    request("parent-token", contractBody({ child_profile_id: "" })),
    seen.deps,
  );
  assertEquals(missingChild.status, 400);
  assertEquals(await missingChild.json(), { error: "child_required" });

  const camelCase = await handleSarvamProxy(
    request("parent-token", {
      childProfileId: CHILD,
      audioBase64: AUDIO_BASE64,
      locale: "en-IN",
      consentRecordId: CONSENT,
      consentVersion: CONSENT_VERSION,
    }),
    seen.deps,
  );
  assertEquals(camelCase.status, 400);
  assertEquals(await camelCase.json(), { error: "child_required" });

  const missingConsent = await handleSarvamProxy(
    request("parent-token", contractBody({ consent_record_id: undefined, consent_version: undefined })),
    seen.deps,
  );
  assertEquals(missingConsent.status, 400);
  assertEquals(await missingConsent.json(), { error: "consent_record_required" });
  assertEquals(seen.sarvamCalls, 0);
  assertEquals(seen.consentCalls, 0);
});

Deno.test("log line keeps latency and cost even if extra fields are passed", () => {
  const line = logLine({ latency_ms: 1, cost: 2, audio: AUDIO_TEXT } as ProxyLog);
  assertEquals(line, '{"latency_ms":1,"cost":2}');
  assertEquals(line.includes(AUDIO_TEXT), false);
});

function request(token: string | null, body: Record<string, unknown>): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (token) headers.set("authorization", `Bearer ${token}`);
  return new Request("http://127.0.0.1/functions/v1/sarvam-proxy", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function tracker(options: {
  parentId?: string | null;
  consent?: boolean;
  transcript?: string;
  cost?: number;
  now?: () => number;
} = {}): {
  deps: ProxyDeps;
  logs: ProxyLog[];
  sarvamCalls: number;
  consentCalls: number;
  consentChild: string | null;
} {
  const state = {
    deps: {} as ProxyDeps,
    logs: [] as ProxyLog[],
    sarvamCalls: 0,
    consentCalls: 0,
    consentChild: null as string | null,
  };
  state.deps = {
    verifyJwt: async () => {
      if (!options.parentId) return null;
      return { parentId: options.parentId };
    },
    lookupConsent: async (input) => {
      state.consentCalls += 1;
      state.consentChild = input.childProfileId;
      return options.consent ?? false;
    },
    callSarvam: async (input) => {
      state.sarvamCalls += 1;
      const text = new TextDecoder().decode(input.audio);
      if (!text.includes(AUDIO_TEXT)) throw new Error("mock expected the audio bytes");
      return { transcript: options.transcript ?? TRANSCRIPT, cost: options.cost ?? 0.42 };
    },
    log: (entry) => {
      state.logs.push(entry);
    },
    now: options.now,
  };
  return state;
}

function assertEquals(actual: unknown, expected: unknown) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(`expected ${right} but got ${left}`);
  }
}
