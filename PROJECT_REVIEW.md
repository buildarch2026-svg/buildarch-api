# BUID ARCh — Full Project Review

**Review date:** 26 October 2026  
**Scope:** Flutter client, Android app configuration, Laravel API, database migrations, project documentation, and current automated checks.  
**Purpose:** Document current capabilities and recommend improvements. This review makes no application or API behavior changes.

## Executive summary

BUID ARCh is a Flutter Android client backed by a Laravel 12 API. The app now covers the core project-sharing workflow: authenticated projects, invitations and team membership, shared project files, designer drawings, and private owner/member chat. The API includes authorization checks for project membership and conversation participants, private file storage for project documents and chat attachments, and feature tests for the principal collaboration flows.

The code is suitable for continued local development and staging work, but the project is **not yet ready for production users**. Phone OTP delivery is local-development-only; OTP values are logged in local mode; the Android release build still uses the example application ID and debug signing; the default API address is emulator-specific HTTP; project photos are served from public storage; and API tokens have no configured expiry. Resolve these items and validate against the intended production database, storage, and hosting setup before release.

## Current features

### Authentication and account

- Phone-number OTP flow for local development and Google sign-in verified by the API.
- Profile setup and profile phone-number verification.
- Authenticated API sessions stored using Flutter secure storage; logout attempts to revoke the current server token.
- Optional device-level app lock.
- Invitation links can be retained through sign-in and app startup using secure local storage.

### Projects and teams

- Create and list owned and joined projects, with project type, location, optional coordinates, and optional photo.
- User-initiated location lookup for project/profile forms and sharing of Google Maps directions.
- Separate project tabs clarify ownership: **My Projects** contains projects
  the user created and owns, while **Joined Projects** contains projects owned
  by someone else that the user joined by invitation.
- **My Projects** creation and management are shown as **Coming soon** for
  Contractor and Designer accounts; their accepted invitations remain
  accessible from **Joined Projects**.
- Owner-created Contractor and Designer invitations with QR/link sharing, seven-day expiry, accept/decline/revoke, and project-scoped membership.
- Project team list and private one-to-one chat between the owner and a specific member. The signed-in user is omitted from their own team list.
- Dashboard includes project team and document navigation. The former read-only notice and Activity section have been removed.

### Shared project files

- Project owners and accepted team members can upload and view project files.
- Photos and PDFs are supported; general project-file uploads are limited to 100 MB.
- Files are stored privately on Laravel's local filesystem disk and downloaded through authenticated, project-authorized endpoints.
- Designer uploads are categorized as **Drawings** and are visible in the dashboard's Drawings view and the All Files view.
- Android download uses a system save-location dialog.

### Private chat and media

- Text messages, images, PDFs, camera-captured photos, and recorded voice notes.
- Chat attachments are limited to 25 MB per file. The app stops voice recording after five minutes.
- Attachments are stored privately and can be downloaded only by the owner and the member in that conversation.
- Chat refreshes by polling the API every five seconds; it is not push/real-time messaging.

## Architecture overview

- **Flutter:** screens and widgets under `buid_arch/lib/screens` and `buid_arch/lib/widgets`; data models under `lib/models`; HTTP and session services under `lib/services`.
- **API:** Laravel routes in `buid_arch_api/routes/api.php`, request handling in `app/Http/Controllers/Api`, Eloquent models in `app/Models`, and schema evolution through additive migrations.
- **Authentication:** Laravel Sanctum bearer tokens protect project, profile, document, and chat routes. Google ID tokens are verified server-side.
- **Development:** `buid_arch/run_on_phone.ps1` starts/checks the local API, uses ADB reverse forwarding for the emulator/phone, and launches Flutter with development configuration.

## Recommendations

### Release blockers — address before production

1. **Implement production OTP delivery and remove OTP secrets from logs.** `OtpController::createOtpChallenge` returns HTTP 503 outside the `local` environment, while local mode logs the phone number and plaintext OTP. Configure a delivery provider, delivery failure handling, abuse monitoring, and provider secrets before launch. Ensure production environment/debug settings cannot accidentally enable development OTP behavior. See [OtpController.php](./buid_arch_api/app/Http/Controllers/Api/Auth/OtpController.php) and [.env.example](./buid_arch_api/.env.example).
2. **Define production API transport and endpoint configuration.** The Flutter fallback URL is `http://10.0.2.2:8000/api`, which is appropriate for the Android emulator, not a deployed phone app. Require an HTTPS production URL and keep loopback/ADB forwarding in development-only launch configuration. See [auth_api_service.dart](./buid_arch/lib/services/auth_api_service.dart) and [run_on_phone.ps1](./buid_arch/run_on_phone.ps1).
3. **Set a permanent Android app identity and protected release signing.** Android currently declares `com.example.buid_arch` and uses the debug signing configuration for release. Choose the permanent application ID and configure release signing in protected CI/secret storage. See [build.gradle.kts](./buid_arch/android/app/build.gradle.kts).
4. **Decide whether project photos are public.** Project photos are written to the public disk and returned as `/storage/...` URLs. If photos or plans are private, move them to private storage and serve them through authorized endpoints or short-lived signed URLs. Project documents and chat attachments already use private storage. See [ProjectController.php](./buid_arch_api/app/Http/Controllers/Api/ProjectController.php) and [ProjectDocumentController.php](./buid_arch_api/app/Http/Controllers/Api/ProjectDocumentController.php).
5. **Set a token lifetime and lost-device revocation policy.** Sanctum expiration is currently `null`. Define expiry, re-authentication/renewal, and user-visible revocation behavior. See [sanctum.php](./buid_arch_api/config/sanctum.php).
6. **Keep authentication response validation covered.** OTP and Google sign-in now reject a nominally verified response unless it includes a non-blank token, a user with a positive integer ID, and a boolean `profile_complete` value. Malformed responses cannot be saved as sessions or proceed to onboarding. Regression tests cover malformed OTP and Google responses. See [auth_api_service.dart](./buid_arch/lib/services/auth_api_service.dart), [otp_screen.dart](./buid_arch/lib/screens/otp_screen.dart), and [login_screen.dart](./buid_arch/lib/screens/login_screen.dart).
7. **Choose and test the production database and storage.** The sample environment is configured for local/debug use, including SQLite defaults. Select the production database and private object-storage strategy, run migrations against that engine, and test backups and restores before real data is stored. The actual local `.env` and any cloud environment were not inspected.

### Reliability, scale, and product improvements

1. **Broaden client integration coverage.** The Flutter suite now has API-client contract tests and a widget test for OTP request failure, plus an emulator integration flow for phone entry, OTP request, and incorrect-code handling. Continue adding widget/integration coverage for login/session restoration, project loading, upload/download, invitation handoff, and chat media.
2. **Expand and automate backend checks.** The Laravel suite has meaningful feature coverage, but the full Pint check currently reports formatting differences in nine existing API/config/test files. Establish a CI pipeline that runs Flutter analysis/tests, Laravel tests, formatting, and dependency audits on every change.
3. **Plan file lifecycle and operational limits.** Project documents are listed without pagination, and no user-facing delete/retention workflow is present. Define ownership and deletion rules, orphan-file cleanup, storage quotas, backups, and upload limits at PHP, reverse-proxy, API, and storage layers. The development launcher configures PHP limits; a production proxy/storage stack needs equivalent reviewed limits.
4. **Scale chat deliberately.** Five-second polling is simple and suitable for development, but it generates repeated requests when usage grows. Consider push/broadcast updates, unread counts, delivery/read status, message search, and pagination after agreeing on scale and notification requirements.
5. **Enforce media rules consistently on the server.** The API enforces attachment size, type/content signatures, and participant access. The five-minute voice-note cap is currently a client recording timer; enforce duration server-side if it is a product or compliance limit rather than only a UI limit.
6. **Make document categories explicit.** Every upload by a Designer is currently categorized as Drawings, regardless of whether the file is a drawing. If Designers need to upload other material, add a category selector and server-side allowlist; keep All Files as the complete project view.
7. **Finish or clearly defer dashboard tiles.** Approvals, Estimates, Photos, Invoices, Scan, Pay, notifications, progress/stages, and other inert controls should either be implemented end-to-end or remain clearly marked as unavailable.
8. **Improve accessibility and localization.** Test TalkBack labels, large text, contrast, touch-target size, keyboard behavior, and screen-reader feedback. The country selection UI is currently deferred; confirm target countries and international phone-number UX before launch.
9. **Keep documentation and onboarding aligned.** Document deployment configuration, migration order, API authentication, file-size limits, role permissions, recovery/support procedures, and verified-link setup. Android custom-scheme invitation links are configured; verified Android App Links and iOS Universal Links are not.

## API and data-access observations

- Project files require authenticated project access; upload/list/download permission covers the owner and accepted project members.
- Direct chat authorization is restricted to the owner and the selected project member; unrelated members cannot access that conversation.
- Invitation tokens are hashed for lookup and encrypted for owner re-display. Invitations expire after seven days and acceptance checks account role and duplicate membership.
- Routes apply rate limits to OTP, invitations, message sending, and file upload/download.
- Project document and chat files use the local private disk in the current configuration. A production deployment should use a durable, backed-up private disk/object store and preserve authorization checks.
- The project list and document list load all matching rows; pagination/cursor strategies should be considered as user/project data grows.

## Current verification

Checks run for this review:

| Check | Result |
|---|---|
| `flutter analyze` | Passed — no issues found |
| `flutter test` | Passed — 15 unit/widget tests |
| `flutter test integration_test\auth_flow_test.dart -d emulator-5554` | Added, but could not run — emulator/debug connection disappeared during app launch |
| `php artisan test --no-ansi` | Passed — 64 tests, 295 assertions |
| `composer audit --no-ansi` | Passed — no Composer security advisories reported |
| `vendor/bin/pint --test` | Not clean — 9 existing files reported formatting differences; no files were changed by this check |

These checks verify local source/test behavior only. They do not establish production readiness, live service connectivity, cloud configuration, release signing, or compatibility with the eventual production database and storage provider. Flutter package advisory scanning and device-level automated integration tests were not run as part of this review.

## Overall assessment

Continue development and staging; do not treat this review as production approval. Prioritize production OTP delivery/log hygiene, HTTPS and release configuration, project-photo privacy, and token expiry. Keep the new authentication response validation covered by regression tests. Then add integration coverage, production storage/database validation, and operational file/chat lifecycle policies.

## Review boundaries

The workspace root has no Git repository metadata. No cloud account, public production host, actual local `.env` values, user data, or secret values were reviewed. No application or API functionality was changed for this review; the report and related README documentation are the intended changes.
