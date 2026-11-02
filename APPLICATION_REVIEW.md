# BUID ARCh — Historical Application and Cloud-Readiness Review

> This review was written on 24 October 2026 and is retained as a historical
> record. Feature status has changed since then. For the current full-project
> review, implemented features, validation results, and recommendations, see
> [PROJECT_REVIEW.md](./PROJECT_REVIEW.md).

**Review date:** 24 October 2026  
**Scope:** Flutter Android client, Laravel API, relevant configuration and documentation, current automated checks, and a content-free review of the supplied Laravel log.  
**Review type:** Read-only analysis. No application code, environment configuration, database, or deployment was changed. This document is the only intended workspace change.  
**Cloud verification limit:** No cloud account, production host, live database, deployment pipeline, or actual local `.env` values were inspected. Findings describe the checked-in application and local project state, not the state of a server.

## Executive summary

**Do not upload/deploy this application for real users yet.** The implementation has useful foundations—Google identity verification, authenticated project and invitation endpoints, secure local token storage, and good backend test coverage—but there are release-blocking authentication and OTP/privacy issues, plus Android release configuration that is still development-only.

The most urgent confirmed client issue is that authenticated Flutter API calls currently put the literal placeholder `'******'` in the `Authorization` header instead of using the supplied session token. This prevents the client from authenticating protected requests. The API also logs plaintext OTP codes with phone numbers. Production OTP delivery is not implemented, and the environment example enables local/debug settings.

## Current application capabilities

- Flutter Android application with phone/Google sign-in, profile setup, optional local device lock, and server-backed projects.
- Project creation/listing, project dashboards, current-device location lookup and map directions sharing.
- Contractor/Designer project invitations with QR/link sharing, acceptance/decline, project team membership, and Android custom-scheme routing.
- Project list has **My Projects** and **Joined Projects** tabs. Deferred project features are separated into a **Coming soon** section; accepting an invitation routes to **Joined Projects**.
- Laravel API uses Sanctum authentication, Google ID-token verification, validation, and invitation/member authorization.

## Findings — resolve before cloud deployment or real-user access

### Resolved in code — Authenticated Flutter requests used a placeholder Authorization value

**Evidence:** Authenticated methods in `buid_arch/lib/services/auth_api_service.dart` now build `Authorization: Bearer <token>` from the supplied session token. A regression test in `buid_arch/test/auth_api_service_test.dart` asserts the outgoing request header.

**Impact:** The previous literal placeholder prevented authenticated client calls from using the saved session.

**Verification:** Flutter analysis and all three Flutter tests passed after the fix. Full phone/server authentication and invitation flows should still be exercised against staging before release.

### P0 — Plaintext OTP codes and phone numbers are written to logs

**Evidence:** `buid_arch_api/app/Http/Controllers/Api/Auth/OtpController.php:56-65` logs OTP-related information; the supplied `buid_arch_api/storage/logs/laravel.log` contains historical phone/OTP-type entries. OTP validity is five minutes (`OtpController.php:56-59`).

**Impact:** Anyone with access to application logs, support bundles, backups, or a cloud upload may obtain active or recent verification codes and associated personal data. Logs are not an appropriate OTP delivery channel or secret store.

**Recommendation:** Remove OTP and unnecessary phone logging before enabling real delivery. Do not upload or publicly expose the supplied log. Apply restricted access and retention controls, and securely purge or rotate historical sensitive log data according to the applicable retention process.

### P0 — Production phone verification is not implemented

**Evidence:** `buid_arch_api/app/Http/Controllers/Api/Auth/OtpController.php:45-48` refuses OTP creation when the environment is not `local`. `buid_arch_api/.env.example:2-4` uses `APP_ENV=local` and `APP_DEBUG=true`; `buid_arch_api/app/Http/Controllers/Api/WhatsAppTestController.php:14-16` is guarded by the local environment.

**Impact:** Phone sign-in and phone verification return service-unavailable responses in a correctly configured non-local environment. Copying the sample environment settings to a public server would leave debug behavior enabled and can expose development-only functionality.

**Recommendation:** Select and configure a real OTP provider, delivery-failure handling, abuse controls, and secrets outside source control. Explicitly set production environment and disable debug in the deployed environment. Keep the WhatsApp test route unavailable in production. The actual local `.env` was not inspected.

## High-priority deployment/security findings

### Resolved — Android API endpoint configuration

**Root cause:** The Flutter API service defaulted to `http://10.0.2.2:8000/api`, which only routes to the host from an Android emulator. A physical phone needs a reachable server address or an explicit tunnel. The phone launcher used USB ADB reverse forwarding, but launching the app outside that script did not configure the tunnel.

**Resolution:** All Laravel requests now use the validated `API_BASE_URL` setting. There is no fallback URL; release builds require HTTPS and reject loopback hosts. The phone launcher passes its loopback URL only after setting and verifying ADB reverse forwarding. API requests retain finite timeouts and report configuration, connection, and timeout failures.

**Remaining deployment configuration:** Supply the publicly reachable HTTPS API URL through `--dart-define=API_BASE_URL=...` when producing a release. Configure and verify production TLS, DNS, and reverse-proxy settings on the hosting provider.

### P1 — Release package identity and signing are still debug placeholders

**Evidence:** `buid_arch/android/app/build.gradle.kts:8, 19, 34-36` uses `com.example.buid_arch` and the debug signing configuration for release.

**Impact:** This is not an acceptable Play Store or production signing setup and can prevent publishing/updating the intended application identity.

**Recommendation:** Choose the permanent unique application ID and configure protected production signing credentials outside source control/CI logs. Verify the signed release App Bundle and key backup/rotation process before distribution.

### Resolved in code — OTP challenge verification is transactional and serialized

**Evidence:** Both phone sign-in and profile phone verification now use the shared `verifyChallenge` method in `buid_arch_api/app/Http/Controllers/Api/Auth/OtpController.php`. It runs challenge lookup, attempt counting, code validation, challenge deletion, and the associated success action in a database transaction; the challenge is selected with `lockForUpdate()`.

**Impact:** On databases that support row-level `SELECT ... FOR UPDATE` locking, concurrent verification requests for a challenge serialize; after the first valid request consumes it, another request cannot use it to create another session or attach the phone.

**Verification and remaining check:** The OTP feature suite now includes a regression test proving a consumed code cannot be replayed to create a second session. All 21 OTP tests passed. The local test suite uses SQLite, whose `lockForUpdate()` does not provide production-style row locking; run a concurrent-request test against the intended cloud database engine in staging before release.

### P1 — API access tokens have no configured expiry

**Evidence:** `buid_arch_api/config/sanctum.php:53` sets Sanctum token expiration to `null`.

**Impact:** A token that is lost or stolen can remain usable until explicitly revoked. Logout revokes the current token, but that does not impose a lifetime on abandoned sessions.

**Recommendation:** Define a token lifetime and renewal/re-authentication policy suitable for the app, and document how users can revoke lost-device sessions.

## Medium-priority privacy and release-quality findings

### P2 — Project photos are publicly served

**Evidence:** Uploads use the public disk (`buid_arch_api/app/Http/Controllers/Api/ProjectController.php:46`); `buid_arch_api/config/filesystems.php:41-45` configures public visibility and `/storage` URLs; `ProjectController.php:68-70` returns that URL.

**Impact:** Anyone who obtains a photo URL may be able to view the image without project membership or API authentication. This is a concern if project photos can contain private homes, plans, or identifying details.

**Recommendation:** Decide whether project photos are intended to be public. If not, store them privately and serve them through authenticated/authorized access or short-lived signed URLs. Include photo deletion and retention in the project lifecycle.

### P2 — OTP success responses are not consistently validated by the Flutter client

**Evidence:** `buid_arch/lib/screens/otp_screen.dart:120-149` only saves a session when token/user values have expected types, but can continue into onboarding when those values are missing or malformed. The reviewed Google sign-in flow should also be tested for strict response-shape validation.

**Impact:** A malformed or incompatible authentication response can look like a successful login and fail later on screens that require a valid session.

**Recommendation:** Treat a missing/invalid token or user payload as an authentication error; do not navigate as if login succeeded. Apply the same explicit response validation to phone and Google sign-in.

### P2 — Invitation links use an unverified custom URL scheme

**Evidence:** `buid_arch/android/app/src/main/AndroidManifest.xml:35` configures `buildarch://invite/...`; the Flutter invitation service validates the scheme/host/token and stores the pending token securely. The app README states that verified links and iOS/store-install continuation are not configured.

**Impact:** A custom scheme is not domain-verified and another installed app could claim the same scheme. Links also do not provide install-and-resume behavior on platforms/configurations not implemented here.

**Recommendation:** Before public release, configure verified HTTPS Android App Links and the appropriate iOS Universal Links, validate cold-start and already-running behavior, and design a secure store/install continuation path. Until then, treat custom-scheme invitation links as a development-only convenience.

### P2 — Automated Flutter coverage is too narrow for release confidence

**Evidence:** `buid_arch/test/project_invitation_test.dart` currently contains two model/link tests. There are no reported automated widget or integration tests covering login, API authorization headers, OTP error paths, account switching, invitation deep links, or post-accept tab navigation.

**Impact:** Important client/server contract and navigation regressions can pass the current Flutter checks.

**Recommendation:** Add API-client tests for request headers and error parsing; widget tests for login/profile/project states and the two tabs; and integration coverage for invitation links through sign-in, accept, and Joined Projects refresh.

## Code quality and verification

### Passing checks run during this review

- `flutter analyze` — passed, no analyzer issues.
- `flutter test` — passed, 2 tests.
- `php artisan test --no-ansi` — passed, 50 tests and 206 assertions.
- `composer audit --no-ansi` — no Composer security advisories reported.

These checks do **not** verify production credentials/configuration, cloud networking, or end-to-end behavior on a production server. Flutter dependency advisory review was not run.

### Formatting check

- `vendor/bin/pint --test` — failed on nine API files: `UserProfileController.php`, `WhatsAppTestController.php`, `bootstrap/app.php`, `bootstrap/providers.php`, `config/auth.php`, `database/factories/UserFactory.php`, and three existing migrations. The formatter was run in test mode and did not modify files.

Treat this as a code-style/consistency issue rather than evidence of a runtime defect. Apply formatting only after reviewing the affected files and avoiding unrelated behavior changes.

### Positive implementation patterns

- Google ID tokens are checked server-side for signature, issuer, audience, expiry, and verified email.
- Invitation endpoints require authentication and enforce owner/member access. Invitation lookup tokens are hashed; encrypted token copies support owner QR re-display.
- Invitation acceptance is covered by backend tests for authorization, role mismatch, expiry, revocation, duplicates, and accepted membership.
- Local session and pending invitation data use secure storage; local sign-out clears local state if server revocation cannot complete.
- Location is user-initiated and foreground-only, with a manual-entry fallback documented.

## UX and product suggestions

1. **Clarify the project tabs.** The owner-project tab is now named **My Projects**, and deferred project features appear in a separate **Coming soon** section within it. **Joined Projects** remains dedicated to accepted invitations.
2. **Make membership status and role visible.** Show the invitee's project role and who invited them, and explain when a project is read-only or an action is owner-only.
3. **Improve invite handoff feedback.** Explain why the invite is invalid/expired/revoked, indicate that it is saved while the recipient signs in, and give a direct retry path for temporary network failures.
4. **Make unfinished features explicit.** Notifications, project editing/deletion, and progress/stage management are not complete end-to-end. Label unavailable controls clearly and avoid presenting inactive controls as working.
5. **Plan core account lifecycle features.** Add profile editing, account deletion/support, and a way to revoke sessions from lost devices.
6. **Plan construction workflow additions.** Consider project milestones, tasks, stage progress, project documents/photos, activity history, and team collaboration after the authorization/data model is ready.
7. **Check accessibility before release.** Test screen-reader names for icon-only actions, large text scaling, contrast, touch target sizes, focus order, and OTP keyboard/input behavior.
8. **Plan localization and phone-number support.** Confirm target countries, country-code selection, translated validation messages, date/number formatting, and time-zone handling.

## Cloud-upload checklist

- [x] Fix the Flutter Bearer-token header and add a request-header regression test; still verify the full flow against staging.
- [ ] Remove OTP secrets from logging; do not upload the provided log. Review logs, backups, CI artifacts, and support bundles for sensitive data.
- [ ] Use a real OTP delivery provider and configure abuse prevention, rate limits, monitoring, and secret rotation.
- [ ] Set production `APP_ENV`, `APP_DEBUG=false`, secure `APP_KEY`, production database credentials, cache/rate-limit backend, storage, and Google client ID through the cloud provider's secret manager. Do not upload `.env`, private keys, local databases, or debug logs.
- [ ] Require HTTPS, set a production Flutter API URL, verify reverse-proxy/trusted-proxy settings, and confirm API reachability from the phone network.
- [ ] Decide project-photo privacy and configure private storage if project files are not meant to be public.
- [ ] Configure Sanctum token expiry/revocation, verify OTP row-lock behavior concurrently on the intended database, and test backups, monitoring, log retention, and restore procedures.
- [ ] Set the permanent Android application ID and protected release signing. Build and inspect a signed release App Bundle with production defines; do not distribute a debug-signed build.
- [ ] Review and stage database migrations with a backup and rollback plan. Confirm migration status on the intended cloud database; never use a destructive fresh/reset migration against production data.
- [ ] Configure verified Android/iOS invitation links and test logged-out, logged-in, locked, cold-start, and expired-invite paths.
- [ ] Add Flutter API/widget/integration coverage, run static analysis and dependency audits, and fix or deliberately baseline formatting violations.

## Overall recommendation

Keep the current project as a development/staging build. The Flutter Bearer-token issue and OTP challenge race have been addressed in code, but staging verification remains. Before cloud deployment for real users, address the remaining P0 findings, implement production OTP delivery, configure a secure HTTPS release build and signing, and agree on photo privacy and session-lifetime policy. Then deploy first to a protected staging environment, run the full authentication/project/invitation flows—including concurrent OTP verification—with test accounts, and only then consider public release.
