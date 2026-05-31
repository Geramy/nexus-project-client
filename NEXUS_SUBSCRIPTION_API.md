# Nexus Router — Subscription / Account API Integration Guide

How the **Nexus Projects** desktop client talks to the **Nexus Router** backend
(the managed gateway that handles auth, billing, subscription entitlements, and
AI inference). This document is written for the **lemonade_mobile** team so a
second client can integrate the same subscription backend.

The Router is a separate C#/.NET service. JSON is **snake_case** on the wire.
The same bearer token is used for BOTH the account/billing API and for
authenticating inference calls.

---

## 1. Gateway base URL

- **Production:** `https://api.nexus-projects.ai`
- **Local dev override:** `http://localhost:5098`
- **Website dashboard:** `https://nexus-projects.ai/dashboard` (the `api.` host
  with the `api.` prefix stripped)

### URL normalization (client-side)
The client normalizes whatever base URL it's given to an `/api/v1` root:
- If no scheme, default to `https://`.
- Strip trailing slashes.
- If it already ends with `/api/v1`, `/v1`, or `/api`, keep/extend accordingly.
- Otherwise append `/api/v1`.

So every endpoint below is called at **`<base>/api/v1<path>`**, e.g.
`https://api.nexus-projects.ai/api/v1/auth/login`.

---

## 2. Authentication

- **Token format:** `nxr_<prefix>_<secret>` (an opaque bearer string).
- **Header:** `Authorization: Bearer <token>` on every authenticated request.
- **No refresh flow.** Tokens are static. A `401`/`403` means the token is
  invalid/expired — surface a re-login, there is no refresh endpoint.
- **The login/register token IS the inference credential.** The same token is
  used as the API key for routed inference calls (see §6).

### Secure storage (how the client persists it)
- iOS: Keychain, `first_unlock` accessibility.
- Android: encrypted SharedPreferences.
- macOS: legacy file-based keychain (avoids data-protection entitlement issues).
- Storage keys used by the client (informational):
  - `nexus/account_token` — the bearer token
  - `nexus/account_identity` — cached user + client JSON
  - `nexus/gateway_base_url` — optional base URL override

The token must **never be logged**.

---

## 3. Endpoints

All paths are relative to `<base>/api/v1`. Content-Type and Accept are
`application/json`.

| Method | Path | Auth | Request body | Response |
|--------|------|------|--------------|----------|
| POST | `/auth/register` | No | `{ "client_name", "email", "password", "device_id"?, "device_name"?, "app_name"? }` | `AuthResult` |
| POST | `/auth/login` | No | `{ "email", "password", "device_id"?, "device_name"?, "app_name"? }` | `AuthResult` |
| GET | `/plans` | No | — | `PlanCatalog` |
| GET | `/account` | Yes | — | `AccountSummary` |
| GET | `/usage` | Yes | — | `UsageSnapshot` |
| GET | `/usage/agents` | Yes | — (optional `?days=<N>`) | `AgentUsageReport` |
| POST | `/billing/checkout` | Yes | `{ "plan", "addons": [] }` | `{ "url" }` |
| POST | `/billing/portal` | Yes | `{}` | `{ "url" }` |

Notes:
- `/billing/checkout` returns a Stripe **Checkout** URL; `/billing/portal`
  returns a Stripe **billing portal** URL. The client opens both in the system
  browser. Subscription changes are picked up by polling `/account` + `/usage`
  (see §6), not via a callback.
- `/usage/agents?days=<N>` windows the per-agent cost scan; omit `days` to get
  the current billing period.
- **Multi-device sign-in (`device_id` / `device_name` / `app_name`, all optional):**
  send a stable per-device id and the minted token is scoped to that device.
  Signing in on a new device mints an independent token and does **not** revoke
  other devices' tokens, so several devices stay signed in at once. Re-signing
  in on the **same** `device_id` with the same `app_name` revokes that device's
  previous token and mints a fresh one. `device_name` ("Geramy's iPhone") and
  `app_name` ("Omni AI Chat") are stored for display. Omit `device_id` entirely
  to keep the legacy behavior (one shared token per user, rotated each sign-in).

---

## 4. Response models (snake_case JSON)

### AuthResult (register / login)
```json
{
  "token": "nxr_ab12_secret...",
  "prefix": "ab12",
  "user":   { "email": "", "display_name": "", "role": "Owner", "account_id": 1 },
  "client": { "id": 1, "name": "Acme" }
}
```
- `user.role`: `Member | Admin | Owner`.

### PlanCatalog (GET /plans)
```json
{
  "plans": [
    {
      "key": "pro", "name": "Pro", "description": "...",
      "price_cents": 2000,
      "monthly_tokens": 1000000, "monthly_images": 200,
      "agent_sessions": 10, "sort_order": 1
    }
  ],
  "addons": [
    {
      "key": "tokens_1m", "name": "+1M tokens", "description": "...",
      "price_cents": 500,
      "bonus_tokens": 1000000, "bonus_images": 0,
      "bonus_agent_sessions": 0, "sort_order": 1
    }
  ]
}
```
Client sorts each list by `sort_order` for display.

### AccountSummary (GET /account)
```json
{
  "user":   { "email": "", "display_name": "", "role": "Owner", "account_id": 1 },
  "client": { "id": 1, "name": "Acme" },
  "subscription": {
    "status": "Active",
    "plan_key": "pro",
    "current_period_start": "2026-05-01T00:00:00Z",
    "current_period_end":   "2026-06-01T00:00:00Z",
    "token_limit": 1000000,
    "image_limit": 200,
    "agent_limit": 10
  }
}
```
- `subscription.status`: `None | Trialing | Active | PastDue | Canceled | Incomplete | Paused`.
- Client treats `Active` and `Trialing` as "active".

### UsageSnapshot (GET /usage)
```json
{
  "status": "ok",
  "period_start": "2026-05-01T00:00:00Z",
  "period_end":   "2026-06-01T00:00:00Z",
  "tokens": { "used": 12345, "limit": 1000000, "remaining": 987655, "percent": 1.2 },
  "images": { "used": 3,     "limit": 200,     "remaining": 197,    "percent": 1.5 },
  "max_concurrent_connections": 4,
  "throttled": false,
  "throttle_tps": null
}
```
- `status`: `"ok"`, `"tokensexceeded"`, etc.
- Each meter (`tokens`, `images`) is `{ used, limit, remaining, percent }`;
  `percent` is `0–100+`.
- `throttled` / `throttle_tps`: see §7.

### AgentUsageReport (GET /usage/agents)
```json
{
  "since": "2026-05-01T00:00:00Z",
  "total_cost": 1.2345,
  "agents": [
    {
      "agent": "Coordinator",
      "calls": 42,
      "input_tokens": 10000,
      "output_tokens": 5000,
      "total_tokens": 15000,
      "cost": 0.42
    }
  ]
}
```
- `agent` is the `X-Nexus-Agent` label; calls sent without it roll up as
  `"(unattributed)"`.

### Billing URL responses
`POST /billing/checkout` and `POST /billing/portal` both return:
```json
{ "url": "https://checkout.stripe.com/..." }
```

---

## 5. Error envelope

Non-2xx responses are mapped to typed errors. The gateway may return any of
these envelopes; parse defensively and prefer in this order:
```json
{ "error": "message" }
{ "error": { "message": "..." } }
{ "errors": ["field error", ...] }      // joined with "; "
{ "message": "..." }
{ "detail": "..." }                      // or [{ "msg": "..." }]
```
Status mapping used by the client:
- `401` / `403` → Unauthorized (re-login)
- `404` → Not found
- `400` (validation, e.g. weak password) and `5xx` → Server error carrying the
  server's text.

---

## 6. Provisioning the Router as an inference server

On login/register, the client auto-wires the Router as an inference endpoint —
no manual API key entry:

1. `GET /account` → read `subscription.agent_limit`.
2. `GET /usage` → read `max_concurrent_connections`.
3. Register an inference server with:
   - `name = "Nexus Router (Subscription)"`
   - `providerType = "routed"`
   - `baseUrl =` the gateway base URL
   - `apiKey =` the **account bearer token** (same token from step §2)
   - `maxAgents = subscription.agent_limit`
   - `maxConcurrency = usage.max_concurrent_connections`
4. **Re-poll every 60s** to keep entitlements in sync with subscription changes.
5. On logout, delete the routed server(s) for the client.

### Inference call headers (against the Router)
The Router speaks an OpenAI-compatible inference API. Each call sends:
- `Authorization: Bearer <token>` — the same account token.
- `X-Nexus-Agent: <agent_name>` — **per-agent cost attribution.** Capped at 128
  chars server-side. Calls without it roll up as `"(unattributed)"` in
  `/usage/agents`. Set this to a stable label per logical agent/feature so cost
  reporting is meaningful.

For lemonade_mobile: set `X-Nexus-Agent` to whatever per-feature label you want
to attribute cost to (e.g. the assistant/persona name).

---

## 7. Over-quota throttling

The Router **never hard-blocks** over-quota usage — it paces output instead:
- `UsageSnapshot.throttled` (bool) — currently throttled.
- `UsageSnapshot.throttle_tps` (int, nullable) — the paced tokens-per-second
  rate when throttled.
- `UsageSnapshot.status` may also read `"tokensexceeded"`.

Client behavior: show a "Throttled · `<tps>` tps" badge and an in-app upgrade
prompt; keep functioning at the reduced rate rather than erroring out. The
throttle window aligns with the Stripe billing period (`period_start` /
`period_end`).

---

## 8. Quick integration checklist (lemonade_mobile)

1. Point at `https://api.nexus-projects.ai`; normalize to `/api/v1`.
2. `POST /auth/login` (or `/auth/register`) → store `token` securely.
3. Send `Authorization: Bearer <token>` on all authenticated calls.
4. `GET /account` + `GET /usage` for subscription state and limits; poll ~60s.
5. Drive paywall/upgrade UI from `subscription.status` + the usage meters.
6. For inference: reuse the SAME token as `Authorization: Bearer`, and set
   `X-Nexus-Agent` per feature for cost attribution.
7. Upgrade/manage → `POST /billing/checkout` / `POST /billing/portal`, open the
   returned `url` in a browser; re-poll `/account` after.
8. Respect `throttled` / `throttle_tps` — pace, don't block.

---

### Source references (Nexus Projects client)
- `lib/infrastructure/nexus/nexus_account_client.dart` — HTTP client + endpoints
- `lib/infrastructure/nexus/models/nexus_account_models.dart` — all models
- `lib/infrastructure/nexus/nexus_account_store.dart` — secure token storage
- `lib/features/ai_providers/providers/router_server_sync.dart` — auto-provision + 60s poll
- `lib/infrastructure/lemonade/api/lemonade_client.dart` — inference headers (`Authorization`, `X-Nexus-Agent`)
- Canonical spec: `nexus-router/docs/api/nexus-projects-api.yaml`

---
---

# Part 2 — Inference API (OpenAI-compatible)

The Router exposes an **OpenAI-compatible** inference surface (the "Lemonade"
API). It is a **separate client** from the account/billing API above, but uses
the **same bearer token** and the **same `/api/v1` base**.

- **Base:** `<gateway>/api/v1` (same normalization as Part 1 — every path below
  is `<gateway>/api/v1<path>`, e.g. `.../api/v1/chat/completions`).
- **Auth header:** `Authorization: Bearer <token>` (the account token; if blank
  the client falls back to `Bearer lemonade` for local Lemonade servers).
- **Cost attribution:** `X-Nexus-Agent: <label>` (≤128 chars) on every call.
  Omitting it rolls the cost up as `"(unattributed)"` in `/usage/agents`.

Capabilities covered: text generation (chat), TTS, STT, image generation,
vision (image→text), image editing, and model listing.

---

## 9. Text generation — chat completions

**`POST /chat/completions`** (JSON; SSE when `stream: true`).

### Request body
```json
{
  "model": "<model-id>",
  "messages": [ /* see message format */ ],
  "stream": true,
  "tools": [ /* optional OpenAI-style tool/function defs */ ],
  "temperature": 0.7,
  "top_p": 0.9,
  "top_k": 40,
  "repeat_penalty": 1.1,
  "max_completion_tokens": 1024,
  "stop": ["</s>"],
  "enable_thinking": false
}
```
- `model`, `messages`, `stream` are required. The rest are optional. Unknown
  extra fields are merged in last (passthrough). `enable_thinking` is a Lemonade
  extension. Note it's `max_completion_tokens`, not `max_tokens`.

### Message format
```json
{ "role": "system" | "user" | "assistant" | "tool",
  "content": "string OR array of content parts",
  "tool_calls": [ ... ],        // assistant only
  "tool_call_id": "...",         // tool role only
  "name": "..." }                // tool role only
```

Content parts (when `content` is an array):
```json
{ "type": "text", "text": "..." }
{ "type": "image_url", "image_url": { "url": "..." } }
{ "type": "input_audio", "input_audio": { "data": "<base64>", "format": "wav" } }
```

### Non-streaming response
```json
{
  "id": "...",
  "model": "...",
  "choices": [
    { "message": { "role": "assistant", "content": "...",
                   "tool_calls": [ { "id": "...", "type": "function",
                     "function": { "name": "...", "arguments": "{...}" } } ] },
      "finish_reason": "stop" | "tool_calls" | "length" | null } ],
  "usage": { "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0 }
}
```
Read the answer from `choices[0].message.content`.

### Streaming (SSE)
- Send `"stream": true`; set `Accept: text/event-stream`.
- Each event is `data: { ...chunk... }`; the stream ends with the literal
  sentinel `data: [DONE]`.
- Chunk shape:
```json
{ "choices": [ { "delta": { "content": "partial text",
      "tool_calls": [ { "index": 0, "id": "...",
        "function": { "name": "...", "arguments": "partial json" } } ] },
    "finish_reason": null } ] }
```
- Concatenate `choices[0].delta.content` across chunks. Tool calls arrive
  indexed and fragmented — accumulate by `index`, concatenating `function.arguments`
  until `finish_reason` arrives. Skip malformed JSON chunks silently.

---

## 10. Text-to-speech (TTS)

**`POST /audio/speech`** (JSON in, **raw audio bytes** out — no JSON wrapper).

### Request body
```json
{
  "model": "<tts-model-id>",
  "input": "text to speak",
  "voice": "af_heart",
  "response_format": "mp3",
  "speed": 1.0
}
```
- `model` + `input` required. `voice` and `response_format` have client defaults
  of `"alloy"` / `"mp3"` respectively, **but** the app's actual default voice is
  `af_heart` (Kokoro voices). `speed` optional.
- `response_format`: `mp3 | wav | opus | aac | flac | pcm`.

### Response
Raw bytes; infer MIME from the requested format:
`mp3→audio/mpeg, wav→audio/wav, opus→audio/opus, aac→audio/aac, flac→audio/flac, pcm→audio/pcm`.

### Voices (Kokoro set)
- US Female: `af_heart` (default), `af_bella`, `af_nicole`, `af_aoede`, `af_kore`, `af_sarah`, `af_nova`, `af_sky`, `af_river`
- US Male: `am_adam`, `am_michael`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_onyx`, `am_puck`
- UK Female: `bf_emma`, `bf_isabella`, `bf_alice`, `bf_lily`
- UK Male: `bm_george`, `bm_daniel`, `bm_fable`, `bm_lewis`

---

## 11. Speech-to-text (STT / transcription)

**`POST /audio/transcriptions`** (`multipart/form-data`).

### Form fields
```
model            (required)  e.g. "whisper-1"
response_format  (required)  "json" | "text" | "verbose_json"
language         (optional)  ISO-639-1, e.g. "en"
file             (required)  the audio file part
```
- The audio part is sent as a file field named **`file`** with a filename and a
  MIME type (default `audio/wav`; mp3/ogg/flac also fine).

### Response (`response_format: "json"`)
```json
{ "text": "the transcript" }
```

---

## 12. Image generation (text-to-image)

**`POST /images/generations`** (JSON).

### Request body
```json
{
  "model": "<image-model-id>",
  "prompt": "a red bicycle",
  "size": "1024x1024",
  "n": 1,
  "response_format": "b64_json",
  "seed": 12345
}
```
- `model` + `prompt` required. `size` defaults to `"1024x1024"`. `n` is only
  sent when `> 1`. `response_format`: `b64_json | url`. `seed` optional.

### Response
```json
{ "data": [ { "b64_json": "<base64 png/jpeg>", "url": null } ] }
```
Each entry has either `b64_json` or `url` depending on `response_format`.

---

## 13. Vision (image → text)

**Not a separate endpoint** — vision runs through `POST /chat/completions`.
Send a user message whose `content` is an array including an `image_url` part:

```json
{ "role": "user", "content": [
    { "type": "text", "text": "What's in this image?" },
    { "type": "image_url", "image_url": {
        "url": "data:image/jpeg;base64,<BASE64>" } } ] }
```
- The `url` may be an external `http(s)` URL or a `data:` URI you build yourself.
  The client passes it through verbatim — it does **not** auto-encode files, so
  base64-encode and wrap as a data URI on your side. Use a vision-capable model.

---

## 14. Image-to-image editing

**`POST /images/edits`** (`multipart/form-data`).

### Form fields
```
model            (required)
prompt           (required)  description of the edit
response_format  (required)  "b64_json" | "url"
n                (required)  as a string, e.g. "1"
size             (optional)  e.g. "1024x1024"
image            (required)  the source image file part
```
- The source image is a file field named **`image`** (default filename
  `image.png`, MIME `image/png`).
- **No `mask` field is implemented** in this client. If the backend supports
  masked edits, you'd add a second file part named `mask` yourself.

### Response
Same shape as image generation: `{ "data": [ { "b64_json" | "url" } ] }`.

---

## 15. List models

**`GET /models`** (optionally `?show_all=true` to include downloadable-but-not-installed).

### Response
```json
{ "data": [
    { "id": "<model-id>",
      "labels": ["chat", "vision", "multimodal"],
      "recipe": "collection.omni" | "llm" | "embedding",
      "composite_models": ["..."],     // collections only
      "downloaded": true,
      "checkpoint": "...",
      "suggested": true } ] }
```
- Pick a `model` id from here for the calls above. A model is an "Omni
  collection" bundle when `recipe` is `collection.omni`/`collection` **and**
  `composite_models` is non-empty. Use `labels` to find a `vision`-capable model
  for §13.

---

## 16. Inference errors

Same envelope parsing as Part 1 (`error` / `error.message` / `message` /
`detail`). Status mapping for inference:
- `400` → model-mismatch / bad request
- `401` / `403` → unauthorized (re-login)
- `404` → not found (e.g. unknown model)
- `5xx` → server error.

> ⚠️ A blank/whitespace API key must **not** be sent as `Bearer ` (empty) — some
> backends reject it. The client substitutes `Bearer lemonade` in that case. With
> the Router you always have a real token, so always send the real one.

### Source references (inference)
- `lib/infrastructure/lemonade/api/lemonade_client.dart` — base client, headers, error mapping
- `lib/infrastructure/lemonade/api/endpoints/chat_endpoint.dart` — chat + SSE streaming
- `lib/infrastructure/lemonade/api/endpoints/audio_endpoint.dart` — TTS + STT
- `lib/infrastructure/lemonade/api/endpoints/images_endpoint.dart` — image gen + edits
- `lib/infrastructure/lemonade/api/endpoints/models_endpoint.dart` — model listing
- `lib/infrastructure/lemonade/api/types/*` — request/response shapes
- `lib/infrastructure/lemonade/api/sse/*` — SSE parser + tool-call assembler
- `lib/infrastructure/lemonade/services/tts_voices.dart` — voice catalog
