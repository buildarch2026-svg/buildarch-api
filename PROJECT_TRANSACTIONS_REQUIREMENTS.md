# Project Transactions — Requirement Understanding

## Purpose of this document

This document records my understanding of the requested feature. It is a
requirements draft for review, not an implementation plan that has already
been approved. No application code has been changed for this request.

## Request in my own words

People should be able to make project-related payments through Build Arch and
see a reliable record of those transactions in the app. For example, a project
member may buy materials for a home from a shop and pay the shop through the
app. The transaction should be associated with the relevant project and be
visible in its transaction history so the project team can track project
spending.

The feature should cover payments made by project members, not only payments
made by the project owner. The shop or other payee should be identifiable as
the recipient of the payment.

## What this implies

There are two related but distinct capabilities:

1. **Payment processing:** collect money from the payer and transfer it to the
   shop or other recipient using a payment provider.
2. **Transaction tracking:** save and show the payment details, its project,
   participants, status, and history.

The wording “pay through this app” suggests that Build Arch should initiate
real payments, not merely let a user type in an amount and mark it as paid.
That requires a payment provider and a supported payment method. A manually
entered or externally completed payment can be recorded, but is not proof that
the app processed or verified it.

## Current application state observed (6 November 2026)

- The project dashboard's **Pay** action opens a project payment history.
- The app can create manual/external payment records and scan a shop's UPI QR
  code to launch Google Pay when it is installed.
- The Laravel API stores project transactions, identifies the authenticated
  payer, returns the payment history, and supports idempotent attempt IDs.
- The app submits the payment-app result to the API to update provider-payment
  status. The reviewed source does not show server-side provider verification
  or a webhook/reconciliation flow, so a client-reported success is not
  authoritative settlement evidence.
- The history shows a total of completed records and a basic list, but lacks
  search/filtering, a transaction detail/receipt view, and payer display.
- Projects, owners, accepted members, files, and chat are already implemented
  and provide the basis for project-scoped transaction visibility.

Transaction tracking and payment-app handoff are partially implemented.
Provider-verified payment processing, settlement/reconciliation, receipts,
and richer transaction-history UX remain to be designed and delivered.

## Proposed user experience

### Start a payment

An authorized project participant starts a payment from the project dashboard
or a project transactions page and enters or confirms:

- The project this payment belongs to.
- The shop, supplier, contractor, or other payee.
- The amount and currency.
- A short purpose or description, such as “cement for foundation”.
- Optionally, a category, invoice/reference number, and receipt.

The payer reviews the recipient and amount, chooses an available payment
method, and explicitly confirms before the app starts the payment.

### Payment result and history

After confirmation, the app displays the provider's result and stores a
transaction record. The project transaction list shows payments from all
participating members, subject to project permissions. Each entry should
identify who paid, who received the money, the amount, what it was for, when it
happened, and whether it is pending, completed, failed, cancelled, or refunded.

Users can open a transaction to see its full details and, where available, a
receipt or payment reference. Failed or cancelled attempts should remain
distinguishable from completed spending and should not be included in completed
spending totals.

## Core functional requirements

1. A transaction belongs to one project.
2. The system identifies the authenticated payer; the payer cannot claim a
   different account as the person who paid.
3. Each transaction has an identifiable payee. For a shop, the app should
   capture enough information to tell that shop from other shops.
4. The amount must be positive, use an explicitly supported currency, and be
   displayed consistently in the transaction history.
5. A transaction has a server-controlled status and a unique payment-provider
   reference when payments are provider-processed.
6. Only a confirmed, verified payment is treated as completed spending.
7. Pending, failed, cancelled, and refunded transactions are represented
   accurately; totals and filters explain which statuses they include.
8. A transaction list can be filtered or searched by project, date, payer,
   payee, status, and (if categories are adopted) category.
9. The app prevents duplicate payment attempts from creating duplicate
   completed transaction records.
10. The transaction record is available after app restart and on other
    authorized devices.
11. The app shows useful feedback if payment processing or transaction loading
    fails. It must not display a success state when the provider has not
    confirmed success.
12. Users can access an itemized transaction detail and a receipt/reference
    where supported.

## Roles and project visibility

My initial interpretation is:

- The person who initiates a payment is its payer, whether they are the owner,
  contractor, designer, or another accepted project member.
- The shop/supplier is the payee and may not itself be a project member.
- Authorized project participants can see project transactions so the project
  team can track spending.
- The payer and project owner may need additional actions, such as viewing
  payment details or resolving a failed payment.

This visibility is a product decision, not something to assume silently.
Transactions can expose personal or financial information, so the app should
show only the minimum details needed to the intended project roles.

## Suggested initial scope

For a first usable release, I understand the scope to include:

- Project-scoped transaction history.
- Payments initiated by any authorized project member.
- Named shop/supplier recipients.
- Amount, currency, purpose, payer, recipient, time, status, and provider
  reference.
- Verified payment status and duplicate-safe handling.
- Payment detail/receipt view.
- Basic search and status/date filtering.
- Clear handling of pending, failed, cancelled, and refunded payments.

Possible later additions include budgets, category breakdowns, monthly reports,
exportable statements, approvals before payment, spending limits, recurring
payments, shop accounts/catalogues, and multi-currency reporting.

## Important distinction: in-app payment versus payment record

If Build Arch must actually send money from a member to a shop, the app needs an
integrated payment provider that supports the target country, currencies,
payment methods, and recipient payout model. The provider should handle
sensitive payment credentials; the app should not store card or bank secrets.
The server should verify provider callbacks/webhooks before marking a payment
as completed.

If the first release instead records payments made outside Build Arch (for
example, cash or a separate bank transfer), the UI must label those as
**manually recorded** or **external payments** and should not suggest that the
app collected or verified the money. This is a different product scope from
“pay through this app”.

Before a real-money release, the payment provider, fees, refunds, disputes,
settlement, privacy, audit, and applicable legal/compliance requirements need
to be addressed for the chosen launch region.

## Acceptance criteria for the intended feature

- An accepted member can initiate a payment for a project they belong to.
- The payer can identify the shop/supplier receiving the payment.
- Before confirmation, the payer can review the recipient, project, amount,
  currency, and purpose.
- A successful provider-confirmed payment appears once in that project's
  history as completed and identifies the actual payer and payee.
- Other authorized project members can see the shared project transaction
  according to the agreed visibility rules.
- A failed, cancelled, pending, or refunded payment is not misrepresented as
  completed spending.
- A retry or repeated provider notification does not create duplicate
  completed transactions.
- A transaction detail shows a usable receipt or provider reference when one
  exists.
- A user who is not authorized for the project cannot view its transactions or
  initiate a project payment.

## Decisions to confirm before implementation

1. **Payment processing:** Should Build Arch transfer real money to shops
   through a payment provider, or should the first version only record
   externally completed payments?
2. **Launch region and currency:** Which country/countries and currency should
   the first version support?
3. **Payment methods:** Which payment methods should be available (for example
   cards, bank transfer, or a region-specific method)?
4. **Who can pay:** Can every accepted project member initiate a payment, or
   must the project owner approve payments or enable this permission?
5. **Who can see details:** Can every project member see amounts and receipts,
   or should visibility be restricted by role or to the payer and owner?
6. **Payee onboarding:** Can a payer enter any shop/supplier's name and
   payment details, or must the payee have a verified Build Arch account?
7. **Payment destination:** Does money go directly to each shop, or is Build
   Arch expected to collect/hold money and later pay shops?
8. **Fees and refunds:** Who pays transaction fees, and who can request or
   approve a refund?
9. **Receipts:** Are provider receipts sufficient, or must users be able to
   attach a shop invoice/receipt?
10. **Manual/external transactions:** Should cash and bank payments made
    outside the app also be recordable in the same project history?
11. **Spending totals:** Should project totals include only completed payments,
    and how should refunds and pending payments be shown?
12. **Transaction edits:** After a payment is completed, may its description or
    category be corrected? Financial facts such as payer, payee, and amount
    should generally remain immutable; corrections should be auditable.

## Not included in this document

This document does not select a payment provider, define provider credentials
or API contracts, change database or application code, or enable real payments.
Those decisions should follow confirmation of the open product questions
above.
