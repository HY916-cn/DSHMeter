# DSHMeter development guide

DSHMeter is a native macOS 13+ menu bar app that displays DeepSeek API balances.
Its popover and settings layout are derived from CodexMeter and ClaudeMeter;
preserve the MIT license and attribution. Product version: 0.1.2, build 3.

- Bundle identifier: `com.huang.DSHMeter`; GitHub: `HY916-cn/DSHMeter`.
- Reuse the source app's 380-point scrollable popover, compact caption metric
  rows, white/blue bars, 32-point settings row, and AppKit menu bar geometry.
  The menu bar uses 18-point rings and the original 10.5/6.5-point two-line
  text. Rings/bars show topped-up and granted shares of the current balance.
  Settings use the source's 180/200/240 sidebar and 760x600 minimum size.
  Keep accessibility labels and language/appearance choices consistent.
- Credentials are read only from the selected DSH home, inherited launch
  environment, and the DSH home `.env`. Prefer the stored
  `deepseek-account-platform/default` account grant;
  fall back to `DEEPSEEK_API_KEY` only when no account grant exists.
  Never write DSH configuration, persist/copy keys, log secrets, or read chats.
- Parse YAML with Yams, including duplicate-key rejection. Enforce current-user
  ownership, owner-only permissions, regular files, and bounded reads.
- Account grants must have the official Platform issuer and are sent only to
  `GET https://platform.deepseek.com/api/v0/users/get_user_summary` through
  `x-dsh-auth-token`. API keys go only to `GET https://api.deepseek.com/user/balance`
  as Bearer credentials. Do not query profile, log in/out, acknowledge bonuses,
  or delete/rewrite grants. Account failures never silently switch identities.
  Reject redirects, sanitize errors, bound request duration, and preserve exact decimal amounts.
- Keep currency balances separate. Missing or malformed amounts are errors.
  A total balance is an amount; do not fabricate a quota percentage.
- Refresh every 10 seconds while the popover is open, every 60 seconds in the
  background, at least 10 seconds between attempts. Failures back off, preserve
  the previous successful balance as stale, and display the next retry time.
- Read credentials on each refresh. Clear the previous balance when the account
  grant, API key, or DSH home changes. A delayed request must never overwrite another source.
- Credentials and balances remain in memory; preferences contain presentation
  settings and the DSH home path. Application identity stays independent.
- README onboarding must explain DSH account login and optional API Key fallback,
  automatic reading, custom home, missing credentials, and permission errors.
  Put the critical first-use requirement in a GitHub IMPORTANT callout.
- Use `bash Scripts/test.sh` and `bash Scripts/build_local.sh`. XCTest is
  available through `swift test` with full Xcode; CLI checks also work with CLT.
- `bash Scripts/test.sh --live` makes one real read-only balance request.
  Fixture checks must never contact a real API or read personal credentials.
- Check the actual app when desktop tools permit it, and distinguish fixture,
  authenticated API, rendering, and live desktop verification in reports.
- Commit completed changes and push to the project's origin. Keep credentials,
  local data, `.build`, and `dist` out of Git. Release archives are ad-hoc signed;
  describe signing and notarization accurately.
