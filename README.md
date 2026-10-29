# ფილიალების პორტალი

Live portal: https://toka-sina.github.io/branch-portal/

Georgian branch issue portal, built as a dependency-free static application with a dedicated Supabase backend. This repository is independent of `branch-check`.

## Run locally

Requires Node.js 22 or newer. Run `npm start` and open `http://127.0.0.1:4173`. Run `npm run check` for JavaScript syntax checks. The `dist/` directory is deployable without a build step.

## Roles and workflow

- **Admin:** all issues and analytics; account, branch and category management; original issue editing; recoverable deletion and restoration.
- **Supervisor:** only allocated branches; category correction and confirmation; assignment and reassignment; final approval; scoped branch and executor analytics.
- **Executor:** assigned issues, comments, work submission, personal monthly results.
- **Branch:** one shared account per branch; its own issues, initial detailed comment, read-only follow-up discussion, approval or rejection with a mandatory reason.

Technical issues: new → classification confirmed → assigned → in progress → awaiting branch → awaiting supervisor → completed. Rejection returns the issue to the supervisor for assignment; a fresh branch approval is required in the next cycle.

Ideas and customer requests: new → supervisor validates/corrects category → recorded in their separate registers. They do not create executor tasks.

Categories can be added and deactivated by the administrator. New categories explicitly choose task or record behavior. Deactivation preserves existing records. There are no attachments or email notifications. Public Auth signups are disabled; accounts can only be provisioned by the administrator.

## Backend

- Project: `fdftbvsgjclrnzvxholo`, Frankfurt, organization SINATRA.
- `supabase/schema/portal.sql` is the consolidated fresh-project schema. Do not reapply it to the configured live project.
- `supabase/functions/admin-users/index.ts` provisions Auth accounts, verifies the caller's current administrator profile, and manages supervisor scope. It uses a pinned `@supabase/supabase-js@2.118.0` dependency.
- The browser configuration contains only a publishable key. Service credentials remain in Supabase's Edge Function environment.
- Username sign-in maps the username internally to a synthetic `@branch-portal.internal.invalid` identifier. Users do not need email addresses and no emails are sent.
- The one-time bootstrap has been consumed. There is no public way to create a portal profile. Every exposed table has RLS; original issue edits and all state transitions are checked inside database triggers.
- Date display and monthly grouping use Asia/Tbilisi. Analytics date filters select issue creation dates; monthly completed totals use final approval dates.

## Deployment

Production hosting is GitHub Pages at `https://toka-sina.github.io/branch-portal/`, publishing from the root of the `gh-pages` branch. The repository is public with the owner's explicit approval. The `main` branch retains application and backend sources; `gh-pages` contains only the static files from `dist/` and `.nojekyll`. For future releases, synchronize the updated static files into `gh-pages` before checking the Pages deployment.

The `.openai/hosting.json` manifest identifies the initial private Sites preview; it does not control the GitHub Pages deployment. Runtime application data is held only in this project's Supabase database.

No real branch accounts or example business data are seeded. Start by signing in as the initial administrator, changing the initial password, creating branches, creating the branch/executor/supervisor accounts, and allocating branches to supervisors.

## Validation

See `tests/VERIFICATION.md` for the performed integration checks. Temporary QA users and records are removed before delivery. The database identity sequence may contain gaps from rolled-back and QA inserts; issue numbers are identifiers, not row counts.

