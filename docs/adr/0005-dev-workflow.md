# 0005 — Plan-first workflow and local-only verification

- Status: Accepted
- Date: 2026-09-27

## Context
Solo developer. CI minutes cost money, and most changes don't need the full test run.

## Decision
- Every feature gets a written plan in `docs/plans/` before implementation.
- Review only when warranted: a logic review for logic-heavy work, a security review for anything touching permissions, file paths or user data. Issue labels (`review:*`) record which.
- No CI/CD. Tests run locally and only the suites the change deserves (table in `docs/development.md`).
- Short commits that link issues. Code docs live in `docs/code-reference.md`, not in long comments.

## Consequences
Nothing enforces tests remotely, so discipline is on the local step before each PR.
