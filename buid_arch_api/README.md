<p align="center"><a href="https://laravel.com" target="_blank"><img src="https://raw.githubusercontent.com/laravel/art/master/logo-lockup/5%20SVG/2%20CMYK/1%20Full%20Color/laravel-logolockup-cmyk-red.svg" width="400" alt="Laravel Logo"></a></p>

<p align="center">
<a href="https://github.com/laravel/framework/actions"><img src="https://github.com/laravel/framework/workflows/tests/badge.svg" alt="Build Status"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/dt/laravel/framework" alt="Total Downloads"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/v/laravel/framework" alt="Latest Stable Version"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://img.shields.io/packagist/l/laravel/framework" alt="License"></a>
</p>

## About Laravel

Laravel is a web application framework with expressive, elegant syntax. We believe development must be an enjoyable and creative experience to be truly fulfilling. Laravel takes the pain out of development by easing common tasks used in many web projects, such as:

- [Simple, fast routing engine](https://laravel.com/docs/routing).
- [Powerful dependency injection container](https://laravel.com/docs/container).
- Multiple back-ends for [session](https://laravel.com/docs/session) and [cache](https://laravel.com/docs/cache) storage.
- Expressive, intuitive [database ORM](https://laravel.com/docs/eloquent).
- Database agnostic [schema migrations](https://laravel.com/docs/migrations).
- [Robust background job processing](https://laravel.com/docs/queues).
- [Real-time event broadcasting](https://laravel.com/docs/broadcasting).

Laravel is accessible, powerful, and provides tools required for large, robust applications.

## Learning Laravel

Laravel has the most extensive and thorough [documentation](https://laravel.com/docs) and video tutorial library of all modern web application frameworks, making it a breeze to get started with the framework.

You may also try the [Laravel Bootcamp](https://bootcamp.laravel.com), where you will be guided through building a modern Laravel application from scratch.

If you don't feel like reading, [Laracasts](https://laracasts.com) can help. Laracasts contains thousands of video tutorials on a range of topics including Laravel, modern PHP, unit testing, and JavaScript. Boost your skills by digging into our comprehensive video library.

## Laravel Sponsors

We would like to extend our thanks to the following sponsors for funding Laravel development. If you are interested in becoming a sponsor, please visit the [Laravel Partners program](https://partners.laravel.com).

### Premium Partners

- **[Vehikl](https://vehikl.com/)**
- **[Tighten Co.](https://tighten.co)**
- **[WebReinvent](https://webreinvent.com/)**
- **[Kirschbaum Development Group](https://kirschbaumdevelopment.com)**
- **[64 Robots](https://64robots.com)**
- **[Curotec](https://www.curotec.com/services/technologies/laravel/)**
- **[Cyber-Duck](https://cyber-duck.co.uk)**
- **[DevSquad](https://devsquad.com/hire-laravel-developers)**
- **[Jump24](https://jump24.co.uk)**
- **[Redberry](https://redberry.international/laravel/)**
- **[Active Logic](https://activelogic.com)**
- **[byte5](https://byte5.de)**
- **[OP.GG](https://op.gg)**

## Contributing

Thank you for considering contributing to the Laravel framework! The contribution guide can be found in the [Laravel documentation](https://laravel.com/docs/contributions).

## Code of Conduct

In order to ensure that the Laravel community is welcoming to all, please review and abide by the [Code of Conduct](https://laravel.com/docs/contributions#code-of-conduct).

## Security Vulnerabilities

If you discover a security vulnerability within Laravel, please send an e-mail to Taylor Otwell via [taylor@laravel.com](mailto:taylor@laravel.com). All security vulnerabilities will be promptly addressed.

## License

## Google sign-in configuration

Set `GOOGLE_WEB_CLIENT_ID` in the API environment to the Google Web OAuth
client ID used by the Flutter app. Pass that same client ID to Flutter with
`--dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>`. The API requires a Google
ID token and verifies its signature, audience, issuer, and expiration before
using its identity claims.

## Mobile sign-out

Authenticated mobile clients can `POST /api/auth/logout` with their bearer
token to revoke that token without signing out the user's other devices.

## Project invitations

Run `php artisan migrate --force` after deploying invitation code to add the
project-membership and invitation tables. The migrations preserve existing
users and projects. Project owners can create/list/revoke Contractor or
Designer invitations; authenticated matching-role users can view, accept, or
decline them. Invitation tokens are hashed for lookup and encrypted for owner
QR re-display. Invitations expire after seven days. The invitee name and
designation are saved on the project membership when accepted, so a member can
have different project-specific details in each team. Older memberships
without those values fall back to the user's profile name and account role.
The owner invitation list returns only pending invitations that have not
expired. Accepted invitations are retained as history and marked removed when
their member is removed from the project.

The authenticated endpoints are `POST/GET /api/projects/{project}/invitations`,
`POST /api/projects/{project}/invitations/{invitation}/revoke`,
`GET /api/invitations/{token}`, and `POST /api/invitations/{token}/accept` or
`decline`. Accepted members can list only projects they own or belong to and
read the authorized project's member names and project-scoped roles.

## Profile phone verification

Authenticated clients request a profile phone verification code with
`POST /api/user/profile/phone/request`, then submit it to
`POST /api/user/profile/phone/verify`. Profile verification requests have a
per-account rate limit separate from the unauthenticated phone sign-in OTP
limit. A phone number already assigned to another account cannot be attached.

## WhatsApp OTP delivery

Configure `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`,
`WHATSAPP_OTP_TEMPLATE`, and `WHATSAPP_OTP_TEMPLATE_LANGUAGE` in the API
environment. Create and get approval for a WhatsApp **Authentication**
template with an OTP copy-code button; the configured template name and
language must exactly match the approved template. The API sends the generated
six-digit code in the body and OTP button parameters. The code expires after
five minutes. WhatsApp credentials must remain server-side and must not be
committed to source control. See Meta's [authentication template guide](https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/authentication-templates/copy-code-button-authentication-templates).

Both `POST /api/auth/otp/request` and the authenticated profile phone request
send codes through WhatsApp when these settings are present. In local
development only, an unconfigured sender falls back to writing a test code to
the Laravel log. A configured delivery failure returns a service-unavailable
response and invalidates the newly created challenge.

## Shared project files

Authenticated project owners and accepted members can list and download files:

- `GET /api/projects/{project}/documents`
- `GET /api/projects/{project}/documents/{document}`

The owner or an accepted member can upload a photo or PDF with a multipart
`file` field:

- `POST /api/projects/{project}/documents`

Project-file uploads are limited to 100 MB. Uploads by a member whose project
role is `designer` are categorized as `drawings`; other uploads are categorized
as `general`. Documents are stored on the configured private `local` disk and
download access is checked against project membership. Configure a durable
private storage disk and matching upload limits before production deployment.

## Owner/member chat

The owner and each accepted project member have a private direct conversation.
Only those two participants can list messages, send messages, or download
attachments:

- `GET /api/projects/{project}/members/{memberUserId}/messages?after_id=0`
- `POST /api/projects/{project}/members/{memberUserId}/messages` with JSON
  `{ "body": "Message text" }` (up to 4,000 characters)
- `POST /api/projects/{project}/members/{memberUserId}/messages/attachments`
  with multipart `file` and `message_type` (`image`, `file`, or `voice`)
- `GET /api/projects/{project}/members/{memberUserId}/messages/{message}/attachment`

Chat attachments are limited to 25 MB and are stored on the private `local`
disk. Images, PDFs, and supported audio formats are checked against their
content signature. The current five-minute voice-note duration limit is
enforced by the Flutter recorder UI; the API currently validates file type and
size, not audio duration.

## Project notifications

Authenticated project participants can list their latest notifications and mark
individual notifications as read:

- `GET /api/notifications`
- `POST /api/notifications/{notificationId}/read`

Project file uploads notify every other project participant. Direct chat
messages and chat attachments notify the other conversation participant.
Notifications are stored per recipient and include unread state; run
`php artisan migrate --force` after deploying this feature. The Flutter app
shows them from the notification bell on the Projects and Project Dashboard
screens.

## Firebase chat push notifications

Authenticated devices register their FCM token with `POST /api/push-tokens`
and remove it with `DELETE /api/push-tokens`. Tokens are encrypted at rest and
uniquely associated with one account; sign-out removes the current device
token. Chat notifications are queued on the `notifications` queue and sent
through Firebase Cloud Messaging HTTP v1. Configure `FIREBASE_PROJECT_ID` and
`FIREBASE_CREDENTIALS` in the API environment, where the latter is an absolute
path to a server-only service-account JSON file. Keep that file outside source
control. Run `php artisan migrate --force` and a queue worker listening on
`notifications,default`. If Firebase credentials are unavailable, chat and
database notifications continue to work and the API logs the push
configuration/delivery failure.

## Project lifecycle and team access

After deploying the project lifecycle API, run
`php artisan migrate --path=database/migrations/2026_10_28_000005_add_project_lifecycle_state.php --force`
to add the nullable archive and soft-delete timestamps. Existing projects are
preserved. Project owners can update project name, location, coordinates, and
type with `PATCH /api/projects/{project}`, archive with
`POST /api/projects/{project}/archive`, and restore an archived or deleted
project with `POST /api/projects/{project}/restore`. `DELETE
/api/projects/{project}` is recoverable: it hides the project from members and
marks it deleted without cascading into its files, messages, memberships, or
transactions. Soft-deleted projects are excluded from `GET /api/projects`;
the owner can restore a deleted project by ID later.

Only the project owner can remove an accepted member with
`DELETE /api/projects/{project}/members/{memberUserId}`. The removed user loses
access to project APIs immediately; historical messages and transactions are
retained for the project. Archived and deleted projects reject project-scoped
requests and do not accept invitations until the owner restores them.

## Project payment transaction retries

`POST /api/projects/{project}/transactions` accepts an optional `attempt_id`.
Callers should reuse the same ID when retrying a request whose outcome is
unknown. Replaying an ID for the same payer, project, and transaction details
returns the existing transaction with HTTP 200 instead of creating a duplicate;
the original current status and provider reference are preserved. Reusing an ID
with different transaction details, payer, or project returns HTTP 409. The
first successful request returns HTTP 201. Requests without an `attempt_id`
are not idempotent.

The Laravel framework is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
