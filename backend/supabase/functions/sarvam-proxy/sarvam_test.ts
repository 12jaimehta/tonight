import type { FetchLike } from "./jwt.ts";
import { createSarvamClient, estimateSpeechCostInr } from "./sarvam.ts";

const KEY = "sarvam-test-key-do-not-log";

Deno.test("sarvam client sends the key header and does not return the key or the audio", async () => {
  const audio = tinyWav();
  let capturedUrl = "";
  let capturedKey: string | null = null;
  let fetchCalls = 0;
  const fetchImpl: FetchLike = async (input, init) => {
    fetchCalls += 1;
    capturedUrl = input;
    capturedKey = new Headers(init?.headers).get("api-subscription-key");
    const body = init?.body;
    if (typeof body === "string" && (body.includes(KEY) || body.includes("RIFF"))) {
      throw new Error("audio or key was placed in a string body");
    }
    return new Response(JSON.stringify({ transcript: "hello", language_code: "hi-IN" }), { status: 200 });
  };

  const client = createSarvamClient({ apiKey: KEY, fetchImpl });
  const result = await client({ audio, contentType: "audio/wav", locale: "hi-IN" });
  assertEquals(fetchCalls, 1);
  assertEquals(capturedUrl, "https://api.sarvam.ai/speech-to-text");
  assertEquals(capturedKey, KEY);
  assertEquals(result.transcript, "hello");
  assertEquals(result.cost, estimateSpeechCostInr(audio));
  const dumped = JSON.stringify(result);
  assertEquals(dumped.includes(KEY), false);
  assertEquals(dumped.includes("RIFF"), false);
});

Deno.test("sarvam client prefers a cost on the mock response", async () => {
  const fetchImpl: FetchLike = async () =>
    new Response(JSON.stringify({ transcript: "hello", cost: 1.25 }), { status: 200 });
  const result = await createSarvamClient({ apiKey: KEY, fetchImpl })({
    audio: tinyWav(),
    contentType: "audio/wav",
    locale: "not-a-language",
  });
  assertEquals(result, { transcript: "hello", cost: 1.25 });
});

Deno.test("missing Sarvam key does not call fetch", async () => {
  let fetchCalls = 0;
  const fetchImpl: FetchLike = async () => {
    fetchCalls += 1;
    return new Response("nope", { status: 500 });
  };
  let message = "";
  try {
    await createSarvamClient({ apiKey: "", fetchImpl })({
      audio: tinyWav(),
      contentType: "audio/wav",
      locale: "hi-IN",
    });
  } catch (error) {
    message = error instanceof Error ? error.message : "";
  }
  assertEquals(fetchCalls, 0);
  assertEquals(message, "sarvam_not_configured");
  assertEquals(message.includes(KEY), false);
});

function tinyWav(): Uint8Array {
  const dataSize = 8;
  const bytes = new Uint8Array(44 + dataSize);
  const view = new DataView(bytes.buffer);
  write(bytes, 0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  write(bytes, 8, "WAVE");
  write(bytes, 12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, 8000, true);
  view.setUint32(28, 16000, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  write(bytes, 36, "data");
  view.setUint32(40, dataSize, true);
  return bytes;
}

function write(bytes: Uint8Array, offset: number, value: string) {
  for (let i = 0; i < value.length; i++) bytes[offset + i] = value.charCodeAt(i);
}

function assertEquals(actual: unknown, expected: unknown) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right} but got ${left}`);
}
