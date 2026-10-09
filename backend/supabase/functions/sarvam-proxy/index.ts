import { createConsentLookup } from "./consent.ts";
import { handleSarvamProxy, logLine } from "./handler.ts";
import { verifyParentJwt } from "./jwt.ts";
import { createSarvamClient } from "./sarvam.ts";

const jwtSecret = Deno.env.get("SUPABASE_JWT_SECRET") ?? "";
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const sarvamKey = Deno.env.get("SARVAM_API_KEY") ?? "";

Deno.serve((req) =>
  handleSarvamProxy(req, {
    verifyJwt: (token) =>
      verifyParentJwt(token, {
        jwtSecret,
        supabaseUrl,
        anonKey,
        fetchImpl: globalThis.fetch,
      }),
    lookupConsent: createConsentLookup({
      supabaseUrl,
      anonKey,
      fetchImpl: globalThis.fetch,
    }),
    callSarvam: createSarvamClient({
      apiKey: sarvamKey,
      fetchImpl: globalThis.fetch,
    }),
    log: (entry) => {
      console.log(logLine(entry));
    },
  })
);
