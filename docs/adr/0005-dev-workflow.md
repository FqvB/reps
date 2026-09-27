# 0005 — Model routing and local-only verification

- Status: Accepted
- Date: 2026-09-27

## Context
Solo developer working with Claude Code. CI minutes cost money, and most changes don't need the full test run.

## Decision
- Every feature: Opus (high) plan → Sonnet (high) implementation. Security or privacy features use a Fable (high) plan instead.
- Review only when warranted: Opus (high) for logic-heavy work, Fable (high) for security-sensitive work. Issue labels (`review:*`, `plan:fable`) record which.
- No CI/CD. Tests run locally and only the suites the change deserves (table in CLAUDE.md).
- Short commits that link issues. Code docs live in `docs/code-reference.md`, not in long comments.

## Consequences
The agents in `.claude/agents/` pin the models. Nothing enforces tests remotely, so discipline is on the local step before each PR.
