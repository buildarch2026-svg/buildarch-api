# Build Arch — UI/UX and Product-Gap Review

**Review date:** 6 November 2026  
**Scope:** Flutter screens and widgets, Android/iOS display metadata, and the
Laravel API surfaces used by authentication, projects, files, chat,
notifications, and project payments.  
**Review limits:** This is a source review, not a visual device audit or a
production deployment assessment. No live service, production environment,
user data, or secret values were inspected.

## Executive summary

Build Arch already supports a substantial project-collaboration flow: account
sign-in, owned and joined projects, invitations, team membership, shared files,
chat, notifications, and project payment records. The interface uses shared
colors, text styles, and reusable controls, and several important screens
already provide loading, error, and empty states.

The biggest product gaps are not decorative: payment completion needs
server/provider verification; role-specific project creation and management
are not available to every account type; and the app has no full project
planning, approval, or budget workflow. The most useful UI improvements are
to make payment records easier to review, turn notifications into useful
navigation, and replace static project status with real project activity.

Production-facing placeholder and inaccurate copy was removed in this update.
This does not make the app production-ready. In particular, production OTP
delivery, release signing/identity, and platform permission configuration
remain separate release requirements; see
[`PROJECT_AUDIT_FINDINGS.md`](./PROJECT_AUDIT_FINDINGS.md) and
[`PROJECT_REVIEW.md`](./PROJECT_REVIEW.md).

## Current user-facing capabilities

- **Authentication and onboarding:** Google sign-in, phone-number OTP screens,
  role/profile setup, saved sessions, and optional device lock.
- **Projects and teams:** owned and joined project lists, project creation and
  editing for supported roles, archive/restore/delete actions, invitations,
  team membership, and project dashboards.
- **Files:** project file upload, search, listing, and authenticated download;
  Designer uploads are currently treated as Drawings.
- **Communication:** project chat, group voice chat, notifications, and
  invitation links.
- **Payments:** project-scoped manual/external payment records, a payment
  history, and a UPI QR flow that launches Google Pay when available.

The payment UI and API already exist. The QR flow starts a payment through an
installed payment app, but the client submits the resulting status to the API;
the source reviewed here does not show a server-verified payment-provider
callback/webhook. A client-reported status should not be treated as authoritative
proof of settlement.

## Production-facing copy and label cleanup completed

- Standardized the Android and iOS app display name to **Build Arch**.
- Removed the nonfunctional country-picker affordance. The phone form now
  presents `+91` as the supported prefix rather than implying country
  selection is available.
- Removed unsupported OTP channel, backup-SMS, and security-standard claims
  from the phone, verification, and profile screens. Replaced prototype
  setup/session labels with user-focused copy.
- Replaced the role-restricted **Coming soon** page with a factual explanation
  that project management is unavailable for that account type and directs
  users to **Joined Projects**.
- Removed the hard-coded **Updated 2h ago** project timestamp; the dashboard
  no longer presents a fabricated update time.
- Removed stale **Coming soon** labels and the unused dashboard fallback
  message.
- Removed prototype setup/session codes and coordinates from account setup,
  verification, and unlock screens.

## Recommended improvements

### Priority 0 — before production use

1. **Finish and verify phone sign-in.** Configure an OTP delivery provider,
   delivery-failure handling, abuse controls, and resend/expiry behavior for
   the launch region. Keep login wording consistent with the provider that is
   actually configured. The current backend is not configured for production
   OTP delivery.
2. **Make payment status authoritative.** Verify payment results on the server
   with the selected provider before recording a provider payment as completed.
   Clearly distinguish provider-processed payments from manually recorded or
   externally completed payments. Preserve pending, failed, cancelled, and
   refunded states without counting them as completed spend.
3. **Complete release identity and permission setup.** Replace the Android
   example application ID, configure protected release signing, and add/test
   the iOS usage descriptions for location, camera, and microphone. The product
   name shown to users is now consistent, but these release settings remain.
4. **Review privacy and money-related disclosures.** Explain who can see
   project amounts and receipts, how payment data is retained, and what
   “completed” means. Add a confirmation step that shows project, recipient,
   and amount before handing off to a payment app.

### Priority 1 — improve the main workflows

1. **Make project availability role-aware.** Decide whether Contractors and
   Designers should ever own/create projects. If so, implement those
   permissions and flows; otherwise, avoid presenting an unavailable
   **My Projects** tab to those roles. Keep access to invited work obvious.
2. **Show meaningful project progress.** Replace static status-only
   presentation with project milestones, tasks, due dates, and a dated activity
   feed. Add approval workflows only after defining who can submit, review, and
   approve changes.
3. **Improve payment history.** Show payer, payee, purpose, date, method, and a
   plain-language status. Add search and date/status/category filters, a
   transaction detail screen, and receipt/provider-reference access. The API
   returns payer data, but the current list does not display it.
4. **Make notifications actionable.** Opening a notification should mark it
   read and navigate to the relevant project, message, or file. Provide clear
   unread state and recovery when the target is no longer available.
5. **Improve file collaboration.** Add explicit file categories instead of
   classifying every Designer upload as a drawing. Define delete/retention and
   versioning rules; add preview and pagination as project file counts grow.
6. **Complete account controls.** Provide profile editing, notification and
   security preferences, help/contact support, and clear session/device
   management. The current profile is primarily a read-only summary and logout
   action.

### Priority 2 — quality and scale

- Add screen-reader labels, predictable focus order, large-text and contrast
  checks, and accessible touch targets; test on small phones and tablets.
- Localize user-facing strings, dates, currency, and phone-number entry before
  supporting additional regions. The current phone form is India-only.
- Add explicit offline/retry states for project, file, chat, and payment
  actions, with no success-shaped fallback when a save or payment result is
  unknown.
- Add end-to-end coverage for invitation handoff, project membership,
  file/media failures, notification navigation, and payment status recovery.

## Missing product capabilities to scope

These are roadmap items rather than claims that the current core flows are
broken:

- Project task lists, milestones, schedules, progress reporting, and approvals.
- Estimates/quotes, invoices, budgets, spending limits, and project cost
  summaries.
- A server-verified payment-provider integration, refunds/disputes handling,
  receipts, and reconciliation. The existing UPI launch and transaction
  records are a useful base, not a complete payment-processing service.
- A defined document lifecycle: ownership, deletion, retention, version
  history, and storage quotas.
- Search/filtering across project activity, chat, files, and payments.
- Account support, privacy/data controls, and self-service security settings.

## Related project documents

- [`PROJECT_AUDIT_FINDINGS.md`](./PROJECT_AUDIT_FINDINGS.md) — current
  engineering audit findings and validation snapshot.
- [`PROJECT_REVIEW.md`](./PROJECT_REVIEW.md) — broader historical project
  review dated 26 October 2026; some implementation details have since
  changed.
- [`PROJECT_TRANSACTIONS_REQUIREMENTS.md`](./PROJECT_TRANSACTIONS_REQUIREMENTS.md)
  — payment requirements and open product decisions, updated with the current
  implementation state.

## Validation

- `flutter test` — **49 tests passed**.
- `flutter analyze` — no errors; reports four pre-existing findings (one
  unused declaration and three deprecated Firebase Messaging API uses).
- A live hot restart was requested but could not run because no Flutter app was
  connected to the Dart tooling session.
