# Nexus Router — Multi-Device Token Minting & Rotation Spec

Audience: the AI/engineer implementing a Nexus Router client (e.g. the Lemonade
Mobile / "Omni AI Chat" app). This spec describes how to sign in so that **each
device keeps its own API token** and multiple devices can stay signed in at the
same time. It is additive and backwards compatible — a client that ignores the
new fields behaves exactly as before.

---

## 1. Goal

Today every sign-in mints one API token per user and revokes the previous one,
so signing in on a second device silently logs the first device out. This spec
adds an **optional** per-device identity to sign-in so the router mints and
rotates tokens **per device + per app** instead of per user.

Outcome:
- Phone and desktop can both be signed in at once, each with its own token.
- Signing in on a new device never revokes another device's token.
- Re-signing in on the **same** device (same app) revokes only that device's
  previous token and mints a fresh one.

---

## 2. Endpoints

Base URL: `https://api.nexus-projects.ai`, all paths under `/api/v1`.
Content-Type and Accept: `application/json`. JSON is **snake_case** on the wire.

| Method | Path | Auth |
|--------|------|------|
| POST | `/api/v1/auth/register` | none |
| POST | `/api/v1/auth/login` | none |

Both return the same `AuthResult` body (see §5).

---

## 3. Request fields

### `/auth/register`
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `client_name` | string | yes | Org/client display name. |
| `email` | string | yes | Valid email. |
| `password` | string | yes | 8–100 chars. |
| `device_id` | string | no | Stable per-device id. Max 200 chars. |
| `device_name` | string | no | Friendly label. Max 200 chars. |
| `app_name` | string | no | Minting app name. Max 200 chars. |

### `/auth/login`
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `email` | string | yes | Valid email. |
| `password` | string | yes | |
| `device_id` | string | no | Stable per-device id. Max 200 chars. |
| `device_name` | string | no | Friendly label. Max 200 chars. |
| `app_name` | string | no | Minting app name. Max 200 chars. |

### Field semantics

- **`device_id`** — a stable identifier unique to this installation/device. It
  is the **rotation key**. Generate it once on first launch and persist it in
  secure storage; reuse the same value on every subsequent sign-in from this
  device. Do **not** regenerate it per sign-in (that would orphan tokens). If
  omitted/blank, the request falls back to the legacy single-token behavior.
- **`device_name`** — human-friendly label shown in the account/tokens UI, e.g.
  `"Geramy's iPhone"`. Display only; not used for rotation.
- **`app_name`** — the client app's name, e.g. `"Omni AI Chat"`. Stored for
  display **and** included in the rotation key, so one physical device running
  two different Nexus apps keeps a separate token per app.

All three are trimmed server-side; blank/whitespace is treated as null.

---

## 4. Rotation rules (authoritative)

The rotation **bucket** is the tuple `(user, device_id, app_name)`. On sign-in:

1. The server revokes any existing non-revoked app token whose
   `(user, device_id, app_name)` matches the request.
2. It mints a brand-new token and returns the plaintext **once**.

Truth table (same authenticated user):

| Scenario | device_id | app_name | Effect on other tokens |
|----------|-----------|----------|------------------------|
| New device signs in | `D2` (new) | `A` | None revoked; `D1/A` stays valid. |
| Same device, same app, re-login | `D1` | `A` | Only `D1/A` prior token revoked. |
| Same device, different app | `D1` | `B` | `D1/A` untouched; `D1/B` rotates. |
| Legacy client (no device_id) | _omitted_ | _omitted_ | All legacy (null-bucket) tokens for the user rotate, as before. |

Notes:
- `register` does not revoke anything (the user has no prior tokens); it simply
  mints the first token, tagged with whatever device/app fields were sent.
- The null bucket (no `device_id`) preserves the original
  one-token-per-user-rotated-each-login behavior, so existing apps that don't
  send these fields are unaffected.

---

## 5. Response — `AuthResult`

```json
{
  "token": "nxr_ab12cd_<secret>",
  "prefix": "nxr_ab12cd",
  "user":   { "email": "u@x.com", "display_name": "u@x.com", "role": "Owner", "account_id": 1 },
  "client": { "id": 1, "name": "Acme" }
}
```

- `token` is the **full plaintext API token, shown once**. Persist it in secure
  storage immediately; it cannot be retrieved again.
- `prefix` is the non-secret public prefix (safe to display/log).
- The token format is `nxr_<pub>_<secret>`. The server stores only its SHA-256
  hash. The device/app fields are **not** echoed back in the response — keep a
  local copy of `device_id`/`device_name`/`app_name` if you need them.

---

## 6. Using the token

Every `/api/v1` call (inference, account, usage, billing) authenticates with:

```
Authorization: Bearer nxr_ab12cd_<secret>
```

The minted per-device token is a normal API token; nothing else about request
auth changes.

---

## 7. Error responses

- `400` — validation failure (e.g. weak password, malformed email, a field over
  200 chars). Body: `{ "error": "...", "errors": [ ... ] }`.
- `401` — bad credentials on login: `{ "error": "Invalid email or password." }`.
- Error envelope is JSON; surface `error` to the user.

---

## 8. Client implementation checklist

1. **Generate a stable `device_id` once.** On first launch, create a UUID (or
   use a platform device/installation id) and store it in secure storage. Read
   that same value on every later launch.
   - iOS/macOS: `identifierForVendor`, or a self-generated UUID in Keychain.
   - Android: a self-generated UUID in encrypted storage (avoid hardware serials
     that need extra permissions).
   - Treat it as opaque; only stability + uniqueness matter.
2. **Pick a constant `app_name`** for this app, e.g. `"Omni AI Chat"`. Send the
   same value every time.
3. **Build a `device_name`** for display, e.g. device model + user name.
4. **Send all three** on both `/auth/register` and `/auth/login` (snake_case).
5. **Store the returned `token`** securely; send it as `Authorization: Bearer`.
6. **On sign-out**, just drop the local token. (Server-side revoke-by-device is
   not exposed via this endpoint; re-login on the same device replaces it.)
7. **Never regenerate `device_id`** on logout/login — reuse the persisted value
   so rotation targets the right bucket.

---

## 9. Example calls

### Login (multi-device)
```bash
curl -X POST https://api.nexus-projects.ai/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
        "email": "u@x.com",
        "password": "••••••••",
        "device_id": "b3f1c2a4-...-stable-uuid",
        "device_name": "Geramy'\''s iPhone",
        "app_name": "Omni AI Chat"
      }'
```

### Register (multi-device)
```bash
curl -X POST https://api.nexus-projects.ai/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
        "client_name": "Acme",
        "email": "u@x.com",
        "password": "••••••••",
        "device_id": "b3f1c2a4-...-stable-uuid",
        "device_name": "Geramy'\''s iPhone",
        "app_name": "Omni AI Chat"
      }'
```

### Legacy (still valid — single token per user)
```bash
curl -X POST https://api.nexus-projects.ai/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{ "email": "u@x.com", "password": "••••••••" }'
```
