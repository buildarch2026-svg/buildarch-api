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
respond, starts Laravel Reverb if it is stopped, forwards both service ports
over ADB, verifies forwarding, and passes the API URL, Reverb app key, and
configured Google Web OAuth client ID to Flutter. The API and Reverb listen
only on the computer, and no computer Wi-Fi address needs to be hardcoded.
Keep the USB/ADB connection active while using the local services; if it
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

## Community and Main App accounts

Sign-in uses one Build Arch account. New users can choose Project Management
(Home Owner, Contractor, or Designer) or Community after verifying their phone
or signing in with Google. Community-only accounts keep a null project role and
are routed to Community on sign-in; selecting a Community profession does not
grant project-management access.

Community members can choose **Explore Main App** to select a project role and
complete the existing profile setup. The API upgrades that same account and
retains its user ID, contact details, Community profile, and posts. Main App
users can open Community from the navigation; first-time access asks them to
complete a Community profile without another sign-in.

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
Images and other attachments shared in the group chat are also listed in
**All Files** for every project participant. Direct-chat attachments appear only
for the owner and the member in that private conversation; opening one returns
to that conversation.

The **Chat** tab shows project group conversations and existing private
owner-to-member conversations. Project team members can also open a private
chat from the Project Team page. Chat supports text, replies, editing and
deleting messages, images, PDFs, camera-captured photos, voice notes up to
five minutes, and confirmed current-location sharing. Chat attachments are
limited to 25 MB per file. Foreground messages are delivered through Laravel
Reverb over private, authenticated project channels, with periodic API refresh
as a fallback. Direct messages show read receipts; group messages show the
reader count. Read state and unread counts are persisted by the API. Push
notifications use Firebase Cloud Messaging on Android and iOS. The app asks for
notification permission after sign-in, registers and refreshes its device
token, displays foreground alerts, and opens the chat inbox when a chat push is
tapped.

Long-press a message to reply or forward it. Swipe right on a message to reply
quickly. Forwarded messages can be sent to the project group and one or more
private project chats; forwarded attachments are copied into the destination
conversation and retain the original sender attribution.

For local chat development, `run_on_phone.ps1` starts the API and Reverb
servers, then forwards ports 8000 and 8080 to the connected phone. Configure
`BROADCAST_CONNECTION=reverb` and the Reverb application key/secret in the API
`.env` file. Generate Reverb credentials with `php artisan reverb:install` if
they are not already present. Apply the chat migration from `buid_arch_api`
with `php artisan migrate --force`. The mobile app uses the Reverb application
key only; do not put the Reverb secret in Flutter or commit it to source.

To enable push, register the Android app (`com.example.buid_arch`) and iOS app
(`com.buidarch.buidArch`) in the Firebase project. Put the client values
(`FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`, `FIREBASE_MESSAGING_SENDER_ID`,
`FIREBASE_ANDROID_APP_ID`, and `FIREBASE_IOS_APP_ID`) in the API `.env`;
`run_on_phone.ps1` passes only these public values to Flutter. For the API,
enable the Firebase Cloud Messaging API, create a service account with FCM send
permission, and set `FIREBASE_CREDENTIALS` to the absolute path of its JSON
key. Never commit or pass that private key to the Flutter app. iOS also needs
an APNs authentication key configured in Firebase and the Push Notifications
capability enabled for the app's signing profile. Run `php artisan migrate
--force` and keep a queue worker running with
`php artisan queue:work --queue=notifications,default --tries=3`; the phone
launcher starts a local worker when the queue connection is not `sync`.

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

## Community

The Community tab is available from the main navigation and the dashboard
preview card. On first entry, sign in with the existing Build Arch account and
complete the separate Community profile and guidelines acceptance. Members
can browse and filter public discussions, publish text posts with up to five
images, like
posts, comment and reply, report content, and view/edit Community profiles.
Community profession is independent of the existing account and project roles.
Community image uploads are private API media, not project files. Private
messaging between Community members is not included. Members request and accept
mutual phone contact before either side can see the other's phone number or call.
Accepted contacts can be reviewed and revoked from **My Contacts**; either
member can block the other, immediately ending phone access. Calls open the
device dialer for the member to confirm.

## Construction Job Portal

The **Construction Jobs** dashboard card is available to every signed-in role.
Every Community member uses their existing Community profile to publish and
manage vacancies, search by category, employment type, text, location, and
distance, save jobs, and apply. Hiring and job-seeking are activities, not
separate profile types or registration flows. Community profiles also hold
trade, skills, experience, job preferences, notification radius, and nearby-job
opt-in. Map-selected coordinates support location matching. Candidate contact
details and resumes remain private.

The Laravel API migration must be applied before using this feature. Job and
resume files are stored on the private `local` disk; configure durable private
storage and keep the API's queue worker active for application and nearby-job
notifications. Apply API migrations with `php artisan migrate`. Configure the
API's Firebase credentials and keep a queue worker running with
`php artisan queue:work --queue=notifications,default --tries=3`. The API's
Laravel scheduler must also run (`php artisan schedule:work`, or a production
scheduler invoking `php artisan schedule:run` each minute) to expire jobs
automatically. Nearby notifications require Community-profile opt-in, a
preferred category, a saved map location and radius, and an active FCM device
token.
