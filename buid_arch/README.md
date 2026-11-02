# BUID ARCh

Flutter app. Screens are being built from Figma designs.

## Setup
Run once inside this folder to generate android/ios/web platform folders:

    flutter create . --project-name buid_arch --org com.buidarch
    flutter pub get
    .\run_on_phone.ps1 -DeviceId <emulator-id>

## Run on an Android phone
Connect and authorize your phone for USB debugging, then run this from the
Flutter app folder:

    .\run_on_phone.ps1

The launcher starts the local Laravel API if it is stopped, waits for it to
respond, forwards the API port over ADB, verifies the forwarding, and passes
the API URL and configured Google Web OAuth client ID to Flutter. The API
listens only on the computer, and no computer Wi-Fi address needs to be
hardcoded. Keep the USB/ADB connection active while using the local API; if it
disconnects, rerun the launcher to restore forwarding. Use
`.\run_on_phone.ps1 -DeviceId <adb-serial>` if more than one Android device is
connected.

All backend requests use the single `API_BASE_URL` compile-time setting. It
must be the API root ending in `/api`; there is deliberately no emulator or
localhost fallback, because the correct host depends on the device and network.
Use `.\run_on_phone.ps1 -DeviceId <emulator-id>` for an Android emulator or
`.\run_on_phone.ps1` for the connected physical phone. Both use ADB reverse,
so the local server can stay bound to the computer's loopback interface and
neither target needs a hardcoded computer IP. For another development or
staging server, set its reachable API URL with
`--dart-define=API_BASE_URL=https://<host>/api`. Release builds reject
non-HTTPS and loopback API URLs.

## Google sign-in
Configure the same Google Web OAuth client ID in the Laravel API's
`GOOGLE_WEB_CLIENT_ID` setting and the Flutter build's
`GOOGLE_WEB_CLIENT_ID` Dart define. For example:

    flutter run `
      --dart-define=API_BASE_URL=https://<host>/api `
      --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>

The API verifies the Google ID token signature, audience, issuer, and expiry
before creating or linking an account. It uses only identity claims from that
verified token.

## Location

The profile and project forms open a shared map picker where you can search by
address, place, landmark, or area; choose an autocomplete result; move and zoom
the OpenStreetMap map; or use **Current location** after granting permission.
The picker initially attempts to center on the device's current location; the
current-location control can recenter the map at any time.
The selected pin's address details are shown before you confirm. Profile
locations save to the user's profile; project locations and coordinates save
only to that project. Location is not requested in the background. On Android,
sharing a Google Maps location link from WhatsApp or another app to **Build
Arch** still opens the project picker for review and pin adjustment.

## Project invitations (Android development links)

Project owners can open a project's dashboard, choose **Invite**, create a
Contractor or Designer invitation, and show/share its QR code. Invitations
expire after seven days. The name and designation entered for the invitation
are shown for the accepted member in that project's team list without changing
the member's profile. A recipient scans `buildarch://invite/<token>`; the app
preserves the invite while the recipient signs in or completes registration,
then validates it with the API. After acceptance, the app opens the **Joined
Projects** tab, where accepted projects appear separately from projects the
user owns. The **My Projects** tab contains owner-created projects, with
deferred project features listed in a separate **Coming soon** section. Only
Android custom-scheme links are configured in this development workspace.
Verified web links, iOS links, and store-install continuation need production
domain, signing and store configuration.

The My Projects tab is for Home Owners. For Contractor and Designer accounts,
project creation and management are marked **Coming soon**; accepted invitations
remain available in **Joined Projects**.

Joined-project cards show the member's project role and inviter when available.
If invitation validation fails temporarily, the invitation remains saved while
the recipient retries or signs in. Home Owners can edit active project details
from the project card menu and archive projects, which remain recoverable in the
**Archived** section. Deleted projects are excluded from project listings after
refresh; project records and history remain on the server. Owners can remove
team members from the Project Team page; removed members immediately lose
project access while their existing messages, transaction history, and
invitation history remain.

## Project files and team chat

Project owners and accepted members can upload and download shared project
photos and PDFs from **All Files**. General project-file uploads are limited to
100 MB. Files uploaded by a Designer are also categorized under **Drawings**.
Files are private to authenticated project participants.

The project team page opens a private owner-to-member chat. Messages support
text, images, PDFs, camera-captured photos, and voice notes up to five minutes.
Chat attachments are limited to 25 MB per file. The chat refreshes by polling
the API; push notifications are not implemented.

When creating a project with the device-location or map-selection button, its
coordinates are saved with the project. Map tiles are provided by OpenStreetMap
and credited in the picker. On the project dashboard, use **Share directions**
to share a Google Maps route link through the phone's share sheet. Projects
with manually entered or older saved addresses share a route based on that
address.

After updating the API, apply the additive coordinates migration from
`buid_arch_api` with `php artisan migrate --force`; it adds nullable columns
and preserves existing projects. Apply the project lifecycle migration
specifically with
`php artisan migrate --path=database/migrations/2026_10_28_000005_add_project_lifecycle_state.php --force`;
it adds archive and soft-delete timestamps and retains existing project
history.
