# BUID ARCh

Flutter app. Screens are being built from Figma designs.

## Setup
Run once inside this folder to generate android/ios/web platform folders:

    flutter create . --project-name buid_arch --org com.buidarch
    flutter pub get
    flutter run

## Run on an Android phone
Connect and authorize your phone for USB debugging, then run this from the
Flutter app folder:

    .\run_on_phone.ps1

The launcher starts the local Laravel API if it is stopped, waits for it to
respond, forwards the API port over ADB, and passes the configured Google Web
OAuth client ID to Flutter. The API listens only on the computer, and no
computer Wi-Fi address needs to be hardcoded. Use `.\run_on_phone.ps1
-DeviceId <adb-serial>` if more than one Android device is connected.

## Google sign-in
Configure the same Google Web OAuth client ID in the Laravel API's
`GOOGLE_WEB_CLIENT_ID` setting and the Flutter build's
`GOOGLE_WEB_CLIENT_ID` Dart define. For example:

    flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>

The API verifies the Google ID token signature, audience, issuer, and expiry
before creating or linking an account. It uses only identity claims from that
verified token.

## Location

The profile and project forms can read the device location only after you tap
**Use current location** and grant permission. In project creation, you can
also tap **Choose on map**, select a point on the OpenStreetMap map, and confirm
it to fill the location and save its coordinates without using device location.
The map picker can search for a city, area, or address; selecting a result
centers the map on that place. For a precise remote site, the owner can move
and zoom the map, then tap the site or use **Set pin here** to place the pin at
the map center. Search results are approximate until the owner verifies the
pin location. On Android, the owner can also share a Google Maps location link
from WhatsApp or another app to **Build Arch**; the picker opens that location
for review and pin adjustment before saving.
You can edit the address text before saving; editing it clears the selected
coordinates. Location is not requested in the background. If permission is
denied, location services are off, or address lookup fails, the app shows an
explanation and keeps manual entry available.

## Project invitations (Android development links)

Project owners can open a project's dashboard, choose **Invite**, create a
Contractor or Designer invitation, and show/share its QR code. Invitations
expire after seven days. A recipient scans `buildarch://invite/<token>`; the
app preserves the invite while the recipient signs in or completes registration,
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
the recipient retries or signs in. Notifications, project editing/deletion,
and progress or stage updates are marked unavailable until implemented.

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
and preserves existing projects.
