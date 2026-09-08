# Newsletter operator web application

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
