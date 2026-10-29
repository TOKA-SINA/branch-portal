# Verification record

Validated against the new live Supabase project using seven temporary accounts across two branches, two supervisors, two executors and an administrator. All temporary fixtures are removed after browser QA.

Passed checks:

1. Branch A cannot read branch B's issues.
2. A supervisor cannot read an unallocated branch.
3. An executor cannot read an unassigned issue.
4. Supervisors cannot edit original descriptions.
5. Branch accounts cannot change categories.
6. Completion cannot skip the approval stages.
7. Assignment grants the chosen executor access.
8. Branches cannot add follow-up comments; executors can.
9. Supervisors cannot approve before the branch.
10. Rejection requires a nonempty reason.
11. Returned work cannot restart until the supervisor assigns it.
12. Reassignment revokes issue and notification visibility from the previous executor.
13. Rejection clears the previous branch approval.
14. Final completion stores both approval timestamps.
15. Ideas are recorded separately and cannot be assigned as tasks.
16. Supervisors can correct and confirm classifications.
17. Only administrators can soft-delete issues.
18. Deleted issues are hidden from branch users; administrators can restore them.
19. Anonymous access to issues is denied.
20. Users cannot escalate their profile role.
21. The account provisioning endpoint rejects non-administrators.
22. The setup token cannot be reused.
23. Workflow activity is recorded in the audit log.
24. In-site notifications are created and can be marked as read.

Browser QA also verifies sign-in, the administrator panel, scoped supervisor branch selection, issue detail rendering, mobile navigation and the requested colors.
