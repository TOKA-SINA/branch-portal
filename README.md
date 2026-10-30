# ფილიალების პორტალი

Live portal: https://toka-sina.github.io/branch-portal/

Georgian issue portal with a dedicated Supabase backend. Independent of branch-check. Static frontend, no build dependencies.

## Run and validate

Node.js 22+: npm start (http://127.0.0.1:4173), npm run check, npm test.

## Roles

- Admin: all issues, analytics, users, branches, categories, original description editing, recoverable deletion/restoration.
- Supervisor: allocated branches only; category correction, severity, assignment, contractor work and final closure.
- Executor: assigned internal issues only; comments and completion submission; personal analytics.
- Branch: its own issues; initial detailed description and read-only follow-up discussion. No analytics or completion approval.

## Three statuses

Only pending (ვაიზერის დასადასტურებელი), current (მიმდინარე), closed (დახურული).

A branch submits an issue. The supervisor verifies its category and, for task categories, selects mandatory severity and a target in one review form. Internal work is assigned to an active executor; external work uses the anonymous გარე კონტრაქტორი flag, with no account or contractor name.

Executors submit completion while the issue remains current. The supervisor approves by closing it or returns it with a required reason, optionally reassigning it. Branch confirmation is not required. Contractor issues have a separate supervisor/admin register and can be closed directly by their supervisor or an administrator.

Ideas and customer requests remain in separate registers. Supervisor classification approval closes them directly, without severity or an executor.

Unreviewed issues have a separate queue. Other rows sort critical → important → minor regardless of creation date; equal severities use oldest first. Existing historical assigned issues without severity keep their data and can have severity set in the review form.

## Multiple users in one browser

Each tab stores its own session. სხვა მომხმარებელი opens a fresh sign-in tab. Reload preserves the account; sign-out affects only that session. Tab titles identify the account and role. Existing shared logins migrate once. npm test includes tab isolation and refresh checks.

## Backend

- Supabase project fdftbvsgjclrnzvxholo, organization SINATRA, Frankfurt.
- supabase/schema/portal.sql is the current consolidated fresh-project schema. Do not reapply it to the configured project.
- admin-users is an authenticated administrator-only Edge Function, using pinned @supabase/supabase-js@2.118.0. Service credentials stay server-side.
- Username sign-in uses internal synthetic email identifiers; users do not need email. Minimum password length is six characters. Public Auth signup is disabled.
- Every exposed table uses RLS. Database triggers validate all issue edits and transitions, required severity and assignment, executor submissions, and manager-only closure. The bootstrap is consumed.
- Notifications are in-site only. There are no attachments.
- Dates and monthly grouping use Asia/Tbilisi. Analytics date filters use creation dates; monthly closed task totals use closure dates. Branches have no analytics UI or route.
- All changes are audited. Older audit status codes are displayed through the current three-status vocabulary without rewriting history.

## Hosting

Production: GitHub Pages, root of gh-pages. Public repository with owner approval. main retains sources; synchronize dist files into gh-pages (including .nojekyll) for publication. .openai/hosting.json belongs to the initial private Sites preview and does not control Pages.

## Tests

npm test verifies ordering, the three-status vocabulary, branch analytics visibility and independent tab sessions. tests/workflow-access.sql checks live RLS/transition behavior in a transaction that rolls back every fixture. tests/VERIFICATION.md records browser checks. Temporary browser-test accounts and issues are removed before delivery.
