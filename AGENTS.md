# DSHMeter development guide

Native macOS 13+ menu bar balance monitor. Version 0.1.4, build 5.
Bundle: `com.huang.DSHMeter`. Remote: `HY916-cn/DSHMeter`.

## UI source

The authoritative interface is raycalrui/CodexMeter 1.7.0, commit
`4c6baeec0ce3a502d3fbcf833782f823b0c1ec32`. The full SwiftUI source lives directly
in `DSHMeter/`, with the original history, settings, notification, developer,
menu bar, and popover components. Preserve its layout, sizes, fonts, colors,
controls, window scenes, and component hierarchy. Adapt data bindings and product
identity. MenuBarProgressView.swift is the upstream implementation.

- Keep the 380-point popover, original scroll behavior and fixed header/footer.
- Settings preserve all six upstream categories and their original native forms.
- Balance metric rows reuse MetricBar and UsageWindowRow. Total and topped-up
  amounts occupy the original metric values; granted balance occupies the footer.
- A balance percentage requires an explicit positive reference. Unknown values
  remain unknown. The blue metric bar shows topped-up / total composition.
- History and token views retain the upstream empty/unavailable states when the
  source lacks data. Never fabricate reset periods or token activity.
- CodexUsageService is a UI contract adapter over BalanceService. It never starts
  Codex. Its history identity is salted and partitioned by credential and DSH home;
  reference changes use a separate history window identity.
- UpdateChecker uses this project's GitHub Releases. Manual downloads are
  supported; automatic installation stays disabled until a signed feed exists.
- Keep all MIT attribution and the bundled license.

## Data and credentials

DSHMeterCore owns credential parsing and balance requests. Prefer the existing
DSH account grant in `.credentials.yaml`; use API-key fallback only when no grant
exists. Read-only files, bounded reads, owner-only permission, no symlinks, no raw
credential or response logging. Do not read chats or profile information, modify
DSH configuration, or trigger login/logout/model requests.

Account credentials go only to the fixed official Platform wallet endpoint;
API keys go only to the official API balance endpoint. Reject redirects and
sanitize errors. Preserve exact decimal balances and separate currencies.

Refresh every 10 seconds while open, 60 seconds in the background, minimum
10 seconds between attempts. Preserve last good balances as stale on temporary
failure and use bounded retry backoff. Re-read credentials each refresh, clear
prior values on source changes, and discard responses from an obsolete identity.

Credentials and current balances stay in memory. Optional reference percentages
use the DSHMeter history database. Push credentials use its own Keychain namespace.
README first-use steps must remain explicit with a GitHub IMPORTANT callout.

## Delivery

Build with `bash Scripts/build_local.sh`. The user has requested that testing and
desktop probes stop; do not run tests, live API checks, UI probes, or CI for this
work. Use `[skip ci]` in commits. Preserve credentials and data when installing.
Commit completed changes and push to origin. Keep `.build`, `dist`, and local
credentials out of Git. Describe ad-hoc signing and notarization accurately.
