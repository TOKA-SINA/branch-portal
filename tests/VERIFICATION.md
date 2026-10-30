# Current verification record

The current workflow uses three statuses and supervisor-only closure. The earlier branch-confirmation workflow has been replaced.

Automated frontend checks (npm test):

- Separate sessions across tabs, reload persistence, fresh sign-in links, one-time migration and independent refresh.
- Exactly three statuses and three severity labels.
- Severity precedes creation date in ordering, including contractor rows.
- Pending issues are separated from ranked work.
- Branch analytics route/menu exclusion.
- Historical audit status display normalization.

Database integration checks (workflow-access.sql, all fixtures rolled back):

- Branch insert cannot spoof severity, approval or assignment; branch cannot edit or close.
- Supervisor access remains scoped, including external contractor work.
- Assignment requires severity and an active internal executor or external flag.
- Executor cannot change severity or close issues, and cannot see contractor work.
- Submission preserves current status; rejection requires a reason and clears the submission.
- Supervisor closure works without branch approval; external work closes directly.
- Record-category approval closes with no severity or assignment.
- Admin edit/delete/restore preserves the workflow state.
- Activity and contractor metadata are audited.

Browser verification:

- Branch dashboard has no analytics, charts or statistic cards; report form shows only the branch name, without the automatic-date sentence.
- Branch can submit an idea.
- Review form validates severity and internal/external target.
- Critical task appears before an older minor task.
- Executor completion and manager closure follow the three-status workflow.
- Ideas close directly; contractor work has a separate list and direct closure.
- Temporary fixture branch/accounts/issues are cleaned up after testing.
