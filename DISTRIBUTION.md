# Distributing Lumen (and the ARXNDEV suite)

## 1. Getting trusted by macOS (Gatekeeper)

Right now `make-app.sh` ad-hoc signs the app — fine for your own Mac, but
other Macs will show "Lumen can't be opened" warnings. To ship to clients:

1. **Join the Apple Developer Program** — developer.apple.com/programs,
   $99/year. This is the only way to be "trusted by macOS"; there is no
   workaround.
2. **Create a Developer ID Application certificate** in Xcode →
   Settings → Accounts → Manage Certificates (or developer.apple.com).
3. **Sign with hardened runtime** (replace the codesign line in make-app.sh):
   ```bash
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: YOUR NAME (TEAMID)" Lumen.app
   ```
4. **Notarize** (Apple scans the app and blesses it):
   ```bash
   ditto -c -k --keepParent Lumen.app Lumen.zip
   xcrun notarytool submit Lumen.zip --apple-id you@example.com \
     --team-id TEAMID --password <app-specific-password> --wait
   xcrun stapler staple Lumen.app
   ```
5. **Ship as a DMG or zip.** Users double-click and it just opens — no
   warnings, fully trusted.

## 2. The $1/month suite subscription (how it works today)

- **7-day free trial** starts on first launch, tracked in
  `~/Library/Application Support/ArxOne/license.json`.
- That folder is **shared by every ARXNDEV app** — Lumen, Launchpad, Notch,
  etc. all read the same license: one subscription unlocks everything.
  Reuse `LicenseManager.swift` verbatim in each new app.
- After the trial, AI features show the **Lumen Pro paywall** ($1/month).
  Launcher basics stay free — that's the freemium hook.
- When someone subscribes, generate their license key:
  ```bash
  ./scripts/gen-license.sh        # → ARX1-XXXX-XXXX-CCCC
  ```
  Send it to them; they paste it in the paywall → activated across the suite.

### Payment processor

Connect the paywall's Subscribe button (`LicenseManager.checkoutURL`) to a
checkout page. Easiest options for a solo dev, in order:

- **Gumroad** — 10 min setup, handles subscriptions, no company needed
- **Lemon Squeezy / Paddle** — merchant of record, handles global sales tax
- **Stripe** — most control, but you handle tax/invoices

Set up a webhook (or start manually): on successful payment → run
`gen-license.sh` → email the key. Later, automate with the backend.

## 3. AI key pool & rotation (how it works today)

- Build with multiple keys: `LUMEN_AI_KEYS="key1,key2,key3" ./make-app.sh`
- Keys are baked into the app (`LumenAIKeys` in Info.plist), **never** in git.
- Each install randomly picks a starting key (users spread across the pool),
  and the client auto-rotates to the next key on HTTP 401/403/429.

## 4. The v2 backend (do this before scaling)

Local trials and bundled keys are fine to launch with, but both can be
bypassed/extracted by a technical user. The proper architecture:

```
Lumen app ──license token──▶ api.yourdomain.com ──your keys──▶ AI provider
```

One small server (Cloudflare Workers is basically free) that:
1. validates the subscription (license key or Stripe customer id),
2. proxies AI requests using keys that never leave your server,
3. meters usage per customer, enforces the trial server-side.

This also gives you: instant key rotation without shipping updates, per-user
rate limits, usage analytics, and remote kill-switch for refunded users.
