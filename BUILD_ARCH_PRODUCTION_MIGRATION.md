# Build Arch Production Migration

## Status: Flutter configuration implemented; production release prerequisites remain

**Audit date:** 23 November 2026  
**Repository branch:** `develop`  
**Scope:** Flutter application and build configuration. No Laravel, AWS, Nginx,
DNS, production environment file, database, or production data was changed.

This document records client-side implementation and remaining validation.
It is not a claim that the full app has been tested end-to-end in production.

## Executive summary

- `api.buildarchsolutions.com` resolved to `3.25.85.44`; a GET to
  `https://api.buildarchsolutions.com/api/public/ping` returned HTTP 200 with
  TLS verification enabled during the earlier audit.
- `ws.buildarchsolutions.com` now resolves to `3.25.85.44`. An HTTPS HEAD
  request received HTTP 404 with TLS verification enabled. The user reports
  that a WebSocket handshake returned HTTP 101 and Reverb sent
  `pusher:connection_established`; that handshake was not independently
  repeated by this client-only change.
- Flutter's API URL is a compile-time `API_BASE_URL` setting. Project chat
  reads separate Reverb settings. Release builds now reject insecure,
  private/loopback, or non-443 WebSocket endpoints.
- [`run_on_phone.ps1`](./buid_arch/run_on_phone.ps1) is restored to the local
  API/Reverb configuration and retains its local service startup and ADB
  reverse behavior. [`build_production.ps1`](./buid_arch/build_production.ps1)
  creates a separate Android App Bundle configuration without local services,
  `.env` reads, or ADB reverse.
- No production AAB was created: production OAuth/Reverb/Firebase project
  confirmation and a separate release signing key are not available in this
  workspace.
- The AWS deployment document is historical. It records an HTTP/IP-based
  Nginx configuration and marks HTTPS, external reachability, migration
  review, and backups as pending at the time it was written. It is not proof
  of current server state.
- No production Nginx, Supervisor, systemd, or deployment configuration files
  were found in the repository. This task did not inspect or modify them.

## Flutter changes in this worktree

- Restored the development API URL in `run_on_phone.ps1`.
- Added `build_production.ps1`. It uses the fixed production API and WSS
  endpoints, takes the Android Firebase client configuration from the
  existing `google-services.json`, and requires an explicit expected Firebase
  project ID, Google Web OAuth client ID, and Reverb app key from the build
  environment. It does not read the Laravel `.env`.
- Tightened release URL validation so API endpoints must use HTTPS and public
  hosts, and Reverb must use WSS on port 443 with a public host. Local debug
  API and Reverb settings remain supported.
- Added a separate, ignored Android release signing properties file and
  configured release tasks to fail clearly until that signing configuration
  exists. Local debug signing remains separate.
- Updated the Flutter README and added focused API/Reverb configuration
  tests.

The Android `applicationId` and namespace are
`com.buildarchsolutions.buildarch`. The existing Firebase package entry is
still `com.example.buid_arch` and was intentionally not modified; refresh
`google-services.json` from Firebase before building with the new ID. The
repository has no iOS `GoogleService-Info.plist`; the production builder only
supports Android.

## Findings

### Flutter API and WebSocket configuration

- [`api_configuration.dart`](./buid_arch/lib/services/api_configuration.dart)
  reads `API_BASE_URL`; release mode requires a public HTTPS API base ending
  in `/api` and rejects loopback/private hosts. This configuration is used
  to resolve backend API requests.
- [`project_chat_realtime_service.dart`](./buid_arch/lib/services/project_chat_realtime_service.dart)
  opens the Reverb socket and authenticates private channels through the API.
  The client reads `REVERB_APP_KEY`, `REVERB_HOST`, `REVERB_PORT`, and
  `REVERB_SCHEME`. Production build settings select
  `ws.buildarchsolutions.com:443`; `https` is converted to WSS by the existing
  configuration. Release builds now reject insecure/local overrides.
- [`run_on_phone.ps1`](./buid_arch/run_on_phone.ps1) is documented as the
  local development launcher. It reads the local Laravel `.env`, starts
  local services as needed, uses ADB reverse, and passes loopback API/Reverb
  settings to Flutter.
- The repository search found no other hardcoded local API or WebSocket URL
  in Flutter source. The local checks in `api_configuration.dart` and the
  development launcher are intentional and should remain available for local
  development.

### Android, iOS, Google Sign-In, and Firebase

- Android's debug manifest permits cleartext HTTP for development;
  production must use HTTPS/WSS and must not add a release cleartext
  exception.
- Android now uses application ID and namespace
  `com.buildarchsolutions.buildarch` for debug and release. The tracked
  `google-services.json` still contains `com.example.buid_arch`, as requested;
  Android Firebase Gradle validation requires a matching Firebase Android app
  configuration before building. iOS uses `com.buidarch.buidArch`.
- [`android/app/build.gradle.kts`](./buid_arch/android/app/build.gradle.kts)
  now supports a separate `release-key.properties`; the file and production
  keystore are absent, so release builds fail closed. Local signing files are
  ignored and were not read.
- [`push_notification_service.dart`](./buid_arch/lib/services/push_notification_service.dart)
  initializes Firebase from Flutter compile-time client settings. If required
  settings are absent, it returns without initializing push; production
  packaging should validate these settings rather than treating push as
  implicitly available.
- The backend uses Firebase HTTP v1. Its service-account credential belongs
  only on the server and must never be embedded in the Flutter app or
  committed.
- Google Sign-In requires the Web OAuth client ID and matching Android
  package/signing configuration. The production SHA-1/SHA-256 fingerprints
  and iOS OAuth configuration remain to be verified.

### Laravel services and data

- Reverb and broadcasting are present in Laravel configuration. Broadcast
  authentication uses the protected API; chat events use private channels.
  [`config/reverb.php`](./buid_arch_api/config/reverb.php) currently allows
  all origins. Production origins and authentication behavior must be
  reviewed before restricting or exposing the service.
- Laravel Reverb's configured server port defaults to 8080. The backend
  `.env.example` distinguishes the server listener (`REVERB_SERVER_HOST`,
  `REVERB_SERVER_PORT`) from the public application connection
  (`REVERB_HOST`, `REVERB_PORT`, `REVERB_SCHEME`). The actual production
  values were not inspected.
- Queue jobs include Firebase notifications and other application work.
  The Laravel queue config defaults to the database driver, but the
  production environment's driver is unknown. The worker must include the
  `notifications,default` queues. A daily construction-job expiry command
  is scheduled in [`routes/console.php`](./buid_arch_api/routes/console.php);
  production needs Laravel's scheduler running every minute.
- The filesystem config defaults to local storage and offers an S3 disk.
  Project document uploads use private local storage. The production disk,
  persistence, backups, and image/chat upload paths must be verified before
  any storage migration; do not switch to S3 without an impact and retention
  review.
- WhatsApp OTP delivery is implemented. In a non-local environment, OTP
  requests return 503 when the WhatsApp provider is not configured or
  delivery fails. Provider credentials, template, delivery, rate limits, and
  expiry must be tested with approved test numbers.
- A local `buid_arch_api/.env` exists and is ignored by Git. Its contents
  were not read. `.env.example` contains the relevant variable names;
  production settings remain unknown.

### AWS/Nginx and DNS evidence

- The repository contains no live Nginx configuration or service unit files.
- [`BUILD_ARCH_AWS_DEPLOYMENT_DOCUMENTATION.md`](./BUILD_ARCH_AWS_DEPLOYMENT_DOCUMENTATION.md)
  records a historical Nginx server block listening on port 80 for an IP
  address. Its readiness checklist says HTTPS/SSL and external API access
  needed verification at that time. A current API health GET returned HTTP
  200. DNS now resolves `ws.buildarchsolutions.com` to `3.25.85.44`, and an
  HTTPS HEAD request received HTTP 404 with successful TLS verification.
- The user reports a successful WSS handshake (HTTP 101) and Reverb
  `pusher:connection_established`. This audit did not independently test an
  authenticated Reverb connection. No AWS/Nginx change is part of the current
  Flutter-only request.
- No production OTP, authenticated API, uploads, chat, or push workflows were
  triggered by this implementation.

## Remaining production readiness steps

1. Register `com.buildarchsolutions.buildarch` as an Android app in the
   production Firebase project and Google OAuth. Download its matching
   `google-services.json` when authorized; it was not changed in this task.
2. Set the required process environment values listed below from the
   production client configuration. The build script validates that the
   supplied Firebase project ID matches `google-services.json`; it does not
   infer or substitute a Firebase project.
3. Configure the separate production Android keystore and ignored
   `android/release-key.properties` securely.
4. Register the production application ID and release-key SHA-1/SHA-256
   fingerprints with the Google OAuth and Firebase projects. Confirm the
   supplied Google Web OAuth client ID matches the Laravel backend.
5. Run `.\build_production.ps1` after the production settings, matching
   Firebase configuration, and release signing file are in place.
6. Install the signed bundle on two test devices and verify API auth, private
   channel auth, chat/reconnect, FCM registration/refresh/taps, uploads, and
   downloads. Do not claim end-to-end success until performed.
7. iOS requires a separately verified Firebase app configuration and
   release-signing setup; the current production script builds Android only.

The user reports the AWS API and Reverb infrastructure are deployed and
tested. This task makes no AWS, Laravel, DNS, Nginx, or backend changes.

## Configuration inventory

Variable names below are sourced from code/configuration and `.env.example`;
this document intentionally contains no secret values.

### Flutter build-time client settings

- `API_BASE_URL`
- `REVERB_APP_KEY`
- `REVERB_HOST`
- `REVERB_PORT`
- `REVERB_SCHEME`
- `GOOGLE_WEB_CLIENT_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_API_KEY`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_ANDROID_APP_ID`
- `FIREBASE_IOS_APP_ID`
- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_IOS_BUNDLE_ID`

Production Flutter configuration must not contain `REVERB_APP_SECRET`,
`FIREBASE_CREDENTIALS`, database credentials, or other server secrets.

### Laravel server environment settings to verify

- Runtime/security: `APP_ENV`, `APP_DEBUG`, `APP_URL`, `CORS_ALLOWED_ORIGINS`
- Data/session/cache: `DB_CONNECTION`, `SESSION_DRIVER`, `CACHE_STORE`
- Queue/storage/broadcasting: `QUEUE_CONNECTION`, `FILESYSTEM_DISK`,
  `BROADCAST_CONNECTION`
- Reverb: `REVERB_APP_ID`, `REVERB_APP_KEY`, `REVERB_APP_SECRET`,
  `REVERB_HOST`, `REVERB_PORT`, `REVERB_SCHEME`,
  `REVERB_SERVER_HOST`, `REVERB_SERVER_PORT`
- Firebase: `FIREBASE_PROJECT_ID`, `FIREBASE_CREDENTIALS`
- Google: `GOOGLE_WEB_CLIENT_ID`
- WhatsApp OTP: `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`,
  `WHATSAPP_BUSINESS_ACCOUNT_ID`, `WHATSAPP_GRAPH_API_VERSION`,
  `WHATSAPP_OTP_TEMPLATE`, `WHATSAPP_OTP_TEMPLATE_LANGUAGE`

The Flutter client's `REVERB_SCHEME` should express the secure socket scheme
(`wss`); Laravel's `REVERB_SCHEME` configures the server-side application
connection (`https`). Keep their values scoped to the appropriate process.

## Build configuration and validation

### Production build inputs

Set these process environment variables from the approved client
configuration before running the production build script:

- `BUILDARCH_PROD_FIREBASE_PROJECT_ID`
- `BUILDARCH_PROD_GOOGLE_WEB_CLIENT_ID`
- `BUILDARCH_PROD_REVERB_APP_KEY`

The Android application ID is fixed as
`com.buildarchsolutions.buildarch` in Gradle; it is not overridden by an
environment variable. The script confirms `google-services.json` has a
matching Android package and Firebase project. It reads the client API key,
sender ID, Android app ID, and storage bucket from that file without printing
their values. The currently tracked JSON still names the former package, so
the production build script will reject it until the approved Firebase file
is supplied.

Production signing requires an untracked `buid_arch/android/release-key.properties`
with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. The
corresponding production keystore must be stored securely and kept out of
source control. No production key or credentials were created.

### Commands

Local development remains:

```powershell
Set-Location D:\BUILD_ARCH\buid_arch
.\run_on_phone.ps1
```

For multiple connected Android devices, use
`.\run_on_phone.ps1 -DeviceId <adb-serial>`.

After confirming the application/Firebase/OAuth identifiers, setting the
required environment variables, and configuring release signing, build the
production Android App Bundle with:

```powershell
Set-Location D:\BUILD_ARCH\buid_arch
.\build_production.ps1
```

The expected artifact is
`build\app\outputs\bundle\release\app-release.aab`.

### Checks performed

- Production API DNS resolved to `3.25.85.44`; its read-only
  `/api/public/ping` returned HTTP 200.
- `ws.buildarchsolutions.com` DNS resolved to `3.25.85.44`. HTTPS TLS
  verification succeeded; a HEAD request to `/` returned 404. This is not a
  WebSocket handshake. The user separately reports an HTTP 101 upgrade and a
  Reverb connection-established event.
- `flutter pub get` succeeded.
- `flutter test test/api_configuration_test.dart` passed, including production
  API/WSS and release rejection checks.
- `:app:compileDebugKotlin` passed with only the Google Services processing
  task excluded, validating the new Kotlin package and `MainActivity`.
- A full `flutter build apk --debug --no-pub` was attempted and stopped at
  `processDebugGoogleServices`: the unchanged `google-services.json` has no
  client for `com.buildarchsolutions.buildarch`. Updating that file was
  explicitly out of scope.
- `build_production.ps1` passed PowerShell syntax parsing. The release build
  was not run, as requested.
- `flutter analyze` returned four pre-existing findings: one unused
  `_roleName` and three deprecated Firebase Messaging API uses. No finding
  points to the production configuration changes.
- No debug APK or release artifact was produced for the new ID. A complete
  build requires matching Firebase configuration; release additionally
  requires `android/release-key.properties` and the production build settings.

Firebase delivery, Google sign-in against production, authenticated API flows,
uploads/downloads, and app-level chat/push behavior have not been tested
end-to-end. Register the new Android ID and release signing fingerprints with
Firebase and Google OAuth. iOS production Firebase/signing configuration is
also outstanding.

No Laravel, AWS, Nginx, DNS, backend environment, or production data was
changed.
