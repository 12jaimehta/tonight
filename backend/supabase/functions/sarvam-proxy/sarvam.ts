import type { FetchLike } from "./jwt.ts";

// Published Saaras REST rate: ₹30 per hour, billed per second, rounded up.
// Sarvam's transcript response has no cost field, so this is an estimate from duration.
const SARVAM_STT_INR_PER_HOUR = 30;
const SARVAM_URL = "https://api.sarvam.ai/speech-to-text";

const LANGUAGE_CODES = new Set([
  "unknown",
  "hi-IN",
  "bn-IN",
  "kn-IN",
  "ml-IN",
  "mr-IN",
  "od-IN",
  "pa-IN",
  "ta-IN",
  "te-IN",
  "en-IN",
  "gu-IN",
  "as-IN",
  "ur-IN",
  "ne-IN",
  "kok-IN",
  "ks-IN",
  "sd-IN",
  "sa-IN",
  "sat-IN",
  "mni-IN",
  "brx-IN",
  "mai-IN",
  "doi-IN",
]);

export function createSarvamClient(deps: { apiKey: string; fetchImpl: FetchLike }) {
  return async (input: { audio: Uint8Array; contentType: string; locale: string }) => {
    if (!deps.apiKey) throw new Error("sarvam_not_configured");

    const form = new FormData();
    const copy = new Uint8Array(input.audio);
    form.append("file", new Blob([copy.buffer], { type: input.contentType }), "clip");
    form.append("model", "saaras:v4");
    form.append("mode", "transcribe");
    form.append("language_code", LANGUAGE_CODES.has(input.locale) ? input.locale : "unknown");

    const response = await deps.fetchImpl(SARVAM_URL, {
      method: "POST",
      headers: { "api-subscription-key": deps.apiKey },
      body: form,
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error("sarvam_request_failed");
    }

    const body = await response.json();
    if (!body || typeof body !== "object" || typeof (body as { transcript?: unknown }).transcript !== "string") {
      throw new Error("sarvam_request_failed");
    }
    const transcript = (body as { transcript: string }).transcript;
    const reported = (body as { cost?: unknown }).cost;
    const cost = typeof reported === "number" && Number.isFinite(reported)
      ? reported
      : estimateSpeechCostInr(input.audio);
    return { transcript, cost };
  };
}

export function estimateSpeechCostInr(audio: Uint8Array): number {
  const seconds = wavDurationSeconds(audio);
  if (seconds == null || !Number.isFinite(seconds) || seconds <= 0) return 0;
  const billedSeconds = Math.ceil(seconds);
  return Math.round((billedSeconds * SARVAM_STT_INR_PER_HOUR) / 3600 * 1e6) / 1e6;
}

export function wavDurationSeconds(audio: Uint8Array): number | null {
  if (audio.byteLength < 12) return null;
  if (fourCc(audio, 0) !== "RIFF" || fourCc(audio, 8) !== "WAVE") return null;
  const view = new DataView(audio.buffer, audio.byteOffset, audio.byteLength);
  let offset = 12;
  let byteRate: number | null = null;
  while (offset + 8 <= audio.byteLength) {
    const id = fourCc(audio, offset);
    const size = view.getUint32(offset + 4, true);
    const dataStart = offset + 8;
    if (id === "fmt " && size >= 16 && dataStart + 12 <= audio.byteLength) {
      byteRate = view.getUint32(dataStart + 8, true);
    }
    if (id === "data") {
      if (!byteRate || byteRate <= 0) return null;
      return size / byteRate;
    }
    const next = dataStart + size + (size % 2);
    if (next <= offset) return null;
    offset = next;
  }
  return null;
}

function fourCc(audio: Uint8Array, offset: number): string {
  return String.fromCharCode(audio[offset], audio[offset + 1], audio[offset + 2], audio[offset + 3]);
}
