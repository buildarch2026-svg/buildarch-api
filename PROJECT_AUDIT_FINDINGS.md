# Project Audit Findings

**Audit date:** 2026-11-05  
**Scope:** Flutter application and Laravel API  
**Audit type:** Read-only code and test review

## Executive summary

The project has broad automated coverage for its main API and Flutter model/configuration flows. The most important follow-ups are production OTP delivery, iOS permission declarations, coordinate-pair validation, and correcting one failing push-service test.

## Findings

### High priority

#### Production phone verification is not implemented

**Location:** [`OtpController.php`](./buid_arch_api/app/Http/Controllers/Api/Auth/OtpController.php)

The OTP sender is explicitly local-development-only. Requests outside the `local` environment return HTTP 503 with a message that WhatsApp delivery is not configured. Production sign-in by phone therefore cannot complete until an SMS or WhatsApp provider is integrated and configured.

**Recommended update:** Add a production OTP delivery provider, configure credentials outside source control, and test delivery, rate limits, expiry, and verification.

#### iOS permission descriptions are missing

**Locations:** [`Info.plist`](./buid_arch/ios/Runner/Info.plist), [`project_location_picker_screen.dart`](./buid_arch/lib/screens/project_location_picker_screen.dart)

The location picker requests the device's current location on screen initialization, but the iOS plist has no location usage-description key. Camera and microphone features are also present in the app, but their iOS permission descriptions are absent. iOS can terminate the app when it requests a protected capability without the corresponding usage description.

**Recommended update:** Add clear `NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`, and `NSMicrophoneUsageDescription` strings, and verify those flows on a physical iOS device.

### Medium priority

#### Project coordinates can become inconsistent

**Location:** [`ProjectController.php`](./buid_arch_api/app/Http/Controllers/Api/ProjectController.php)

The project update endpoint validates latitude and longitude independently with `required_with`. A partial update that sets only one coordinate to `null` can leave the other coordinate populated.

**Recommended update:** Treat latitude and longitude as a pair: require both when either is provided, or clear both when either is explicitly cleared. Add tests for partial updates and null values.

#### Duplicate transaction attempts return the existing record

**Locations:** [`ProjectTransactionController.php`](./buid_arch_api/app/Http/Controllers/Api/ProjectTransactionController.php), [`2026_10_28_000004_add_upi_fields_to_project_transactions_table.php`](./buid_arch_api/database/migrations/2026_10_28_000004_add_upi_fields_to_project_transactions_table.php)

The API now checks an existing `attempt_id` before inserting and handles a
concurrent uniqueness conflict. A retry with matching transaction details
returns the existing transaction; reuse for different details returns HTTP 409.
`ProjectTransactionApiTest` covers repeated attempt IDs.

**Status:** Resolved in the current code.

#### A push-service test fails because no device token is registered

**Location:** [`FirebasePushServiceTest.php`](./buid_arch_api/tests/Feature/FirebasePushServiceTest.php)

The full Laravel suite has one failing assertion in `chat push is queued only when server credentials are configured`. The test expects a push job for a user with no registered device token, while the push service intentionally skips users without tokens.

**Recommended update:** Register a test device token before asserting that a job is queued, or change the assertion to verify that no job is queued without a token.

### Improvement opportunities

#### Reduce chat-list query growth

**Location:** [`ProjectChatController.php`](./buid_arch_api/app/Http/Controllers/Api/ProjectChatController.php)

Read state and unread-message counts are looked up for each conversation. As users participate in more chats, the number of database queries grows with the number of conversations.

**Recommended update:** Batch read states and aggregate unread counts for the listed conversations.

#### Add chat UI and realtime regression coverage

**Locations:** [`project_direct_chat_screen.dart`](./buid_arch/lib/screens/project_direct_chat_screen.dart), [`project_group_voice_chat_screen.dart`](./buid_arch/lib/screens/project_group_voice_chat_screen.dart)

Existing Flutter tests cover message parsing and API behavior but do not exercise chat-screen and realtime state transitions such as paging, reconnects, and media failures.

**Recommended update:** Add focused tests for message paging, send/edit/delete flows, reconnect behavior, and attachment download/playback failures.

#### Clear analyzer findings

`flutter analyze` reported four existing items: one unused helper and three deprecated Firebase Messaging API uses.

**Recommended update:** Remove the unused declaration and migrate to the current Firebase Messaging registration/token event APIs.

## Validation results

- Flutter tests: **47 passed**.
- Laravel tests: **96 passed, 1 failed** (the push-service test described above).
- Flutter analyzer: **4 warnings/info items**; no analyzer errors were reported.

## Areas reviewed with positive results

- Startup preserves a saved session when validation is temporarily unavailable and offers a retry path.
- API URL configuration is centralized and validates release URLs.
- API routes use Sanctum authentication; project operations check project participation.
- Invitation acceptance and member removal use transactions and row locks.
- Chat attachment downloads use private storage and participant checks.
- Feature tests cover major project, invitation, chat, notification, OTP, and transaction flows.
