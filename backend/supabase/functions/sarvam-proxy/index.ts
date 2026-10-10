import { createConsentLookup } from "./consent.ts";
import { handleSarvamProxy, logLine } from "./handler.ts";
import { verifyParentJwt } from "./jwt.ts";
import { createSarvamClient } from "./sarvam.ts";

// config.toml sets verify_jwt = true, so the platform checks the parent JWT
// before this function runs. A custom SUPABASE_JWT_SECRET is not used: hosted
// projects reject that secret name. With no HMAC secret, verifyParentJwt asks
// Auth for the user.
const jwtSecret = "";
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
