# Email cockpit web application

Sources reads email documents through the admin-only `sources` proxy. Configure
`READWISE_READER_TOKEN` and comma-separated `READWISE_READER_OWNER_IDS` on the
server; the latter contains exact authorized Clerk administrator IDs. The token
never reaches Flutter. Lists page 25 documents, bodies load only on selection,
and upstream HTML is displayed as bounded plain text. This first adapter is
read-only; archive/move/import mutations are not exposed as fake successes.

Service client uses `support/*`: personal Gmail OAuth, conversations, persistent
pending/waiting/resolved status, explicit reply confirmation and durable unknown
send locks. Configure the exact server contract in CommandGlows
`shipglows_data/technical/gmail-support-api.md`. Replies require a verified relay
domain and activation; direct Gmail messages currently remain read-only. Sources,
support and campaigns keep separate credentials, provider ownership and states.
Draft replies stay in widget session memory across section changes and responsive
resizing; refreshing or closing the browser does not persist those drafts.

This application calls `/api/admin/email` on its own origin using the existing
CommandGlows Clerk session. It never accepts Postmark tokens or internal service
credentials. The `demo` application is separate and deliberately synthetic.

Build the web application with `flutter build web --release --base-href /email-engine/`.
The CI `email-engine-web` artifact contains the resulting static application.
Install that artifact at the CommandGlows site's `public/email-engine/` before
building the site. `/dashboard/newsletters` is the authenticated operator host.
Do not serve the real application on an unrelated origin or substitute API secrets
for session authentication. No recipient data is baked into the artifact.

The application loads server-configured businesses, audiences and permitted test
recipients. Missing authorization or configuration produces an explicit error;
there is no fallback to example data. Every mutation has an idempotency key. A lost
response is not automatically retried. Reload campaign status before a new intent.

The backend and frontend must use the campaign API contract documented in
CommandGlows `shipglows_data/technical/newsletter-campaign-api.md`. The email
ledger and transport retain their existing pilot activation and allowlist gates.

Validation: `flutter analyze` and `flutter test`. CI also checks the web artifact.
These checks are not a hosted login, real delivery, or inbox-rendering proof.
