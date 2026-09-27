# Roadmap

Phases map to the spec milestones (§8) and to GitHub milestones. Each row is one issue and one `feat/<issue>-<slug>` branch.

Routing: **Plan** is the planner agent (high effort). Implementation is always `sonnet-implementer` (high). **Review** is blank when no review is needed.

Status: ☐ todo · ◐ in progress · ☑ done

## Phase 0 — Foundation (M0)

Goal: a project that builds, and a harness that scores detectors against the hitreg-ml footage. Detection code isn't written before this phase is done.

| # | Feature | Spec | Plan | Review | Status |
|---|---|---|---|---|---|
| [#1](https://github.com/FqvB/reps/issues/1) | Xcode project scaffold | §4 | opus | – | ☑ |
| [#3](https://github.com/FqvB/reps/issues/3) | Detector evaluation harness | §4, §7 | opus | opus | ☑ |

## Phase 1 — Manual counter (M1)

Goal: usable on the range with a tap per shot. Install on your phone and start logging real sessions.

| # | Feature | Spec | Plan | Review | Status |
|---|---|---|---|---|---|
| [#4](https://github.com/FqvB/reps/issues/4) | SwiftData model + JSON export | §5.1, §10 | opus | opus | ☑ |
| [#5](https://github.com/FqvB/reps/issues/5) | Onboarding | F19, F20 | opus | fable-security | ☐ |
| [#6](https://github.com/FqvB/reps/issues/6) | Settings | F19, F25 | opus | – | ☐ |
| [#7](https://github.com/FqvB/reps/issues/7) | Plans list + plan editor | F1, F18, F22, F24 | opus | – | ☐ |
| [#8](https://github.com/FqvB/reps/issues/8) | Session engine (SessionController) | F2, F14, F16, F18, F21, F22, §6 | opus | opus | ☐ |
| [#9](https://github.com/FqvB/reps/issues/9) | Session screen (manual counting) | F7, F14, F16 | opus | – | ☐ |
| [#10](https://github.com/FqvB/reps/issues/10) | Voice output | F6, §5.7 | opus | – | ☐ |
| [#11](https://github.com/FqvB/reps/issues/11) | Session summary + accident-proofing | F23, F28 | opus | – | ☐ |
| [#12](https://github.com/FqvB/reps/issues/12) | Session log | F8 | opus | – | ☐ |

Suggested order: #4 → #8 → #9 + #10 → #7 → #11 → #12 → #5 → #6.

## Phase 2 — Camera + putting (M2)

Goal: the simplest vision path (ball presence only) proves the camera pipeline end to end.

| # | Feature | Spec | Plan | Review | Status |
|---|---|---|---|---|---|
| [#2](https://github.com/FqvB/reps/issues/2) | Record putting eval clip (~20 putts, manual) | §7, ADR 0008 | – | – | ☑ |
| [#13](https://github.com/FqvB/reps/issues/13) | Camera pipeline | §5.6, §6 | opus | opus | ☐ |
| [#14](https://github.com/FqvB/reps/issues/14) | Ball locator + presence detector | §5.2, ADR 0011 | opus | opus | ☐ |
| [#15](https://github.com/FqvB/reps/issues/15) | Ball lock box + tap override | §5.2, §6, ADR 0011 | opus | – | ☐ |
| [#16](https://github.com/FqvB/reps/issues/16) | Putting mode | F5, §5.5 | opus | opus | ☐ |

## Phase 3 — Range counter (M3)

Goal: counting full swings hands-free at the accuracy the spec requires.

| # | Feature | Spec | Plan | Review | Status |
|---|---|---|---|---|---|
| [#17](https://github.com/FqvB/reps/issues/17) | Pose extraction + heuristic swing detector | §5.3 | opus | opus | ☐ |
| [#18](https://github.com/FqvB/reps/issues/18) | Integrate existing Create ML swing classifier | §3.2 | opus | opus | ☐ |
| [#19](https://github.com/FqvB/reps/issues/19) | Ball-gated fusion + Range Counter mode | F3, §5.4 | opus | opus | ☐ |
| [#20](https://github.com/FqvB/reps/issues/20) | Camera angle presets + setup overlay | F9 | opus | – | ☐ |
| [#21](https://github.com/FqvB/reps/issues/21) | Accuracy gate (≥95% recall, ≤1 false/50, <1.5 s) | §2 NFR | opus | – | ☐ |

## Phase 4 — Clips + library (M4)

Goal: add the recording layer once counting is trusted.

| # | Feature | Spec | Plan | Review | Status |
|---|---|---|---|---|---|
| [#22](https://github.com/FqvB/reps/issues/22) | Clip writer | F4, §3.3, §5.8 | opus | opus + fable-security | ☐ |
| [#23](https://github.com/FqvB/reps/issues/23) | Thumbnails + storage | §5.3c, F25 | opus | – | ☐ |
| [#24](https://github.com/FqvB/reps/issues/24) | Video library | F15, F16, §5.3b | opus | – | ☐ |
| [#25](https://github.com/FqvB/reps/issues/25) | Clip detail player | F27, §5.3b | opus | – | ☐ |
| [#26](https://github.com/FqvB/reps/issues/26) | Save to Photos + share | §5.8, F25 | **fable** | fable-security | ☐ |

## Phase 5 — Tempo + hardening (M5)

| # | Feature | Spec | Plan | Review | Status |
|---|---|---|---|---|---|
| [#27](https://github.com/FqvB/reps/issues/27) | Swing tempo + event marks | F17, §5.3a | opus | – | ☐ |
| [#28](https://github.com/FqvB/reps/issues/28) | Thermal + battery budget | §5.6, §6 | opus | opus | ☐ |
| [#29](https://github.com/FqvB/reps/issues/29) | Error handling pass | §6 | opus | opus | ☐ |

## Phase 6 — Own model (M6)

Only if it beats Create ML on the event metric.

| # | Feature | Spec | Plan | Review | Status |
|---|---|---|---|---|---|
| [#30](https://github.com/FqvB/reps/issues/30) | Own swing model (PyTorch → Core ML, in hitreg-ml) | §3.2 | opus | opus | ☐ |

## Later (no issues yet)

- F26 voice guidance beyond the count ("last five", "stop")
- F11 voice control ("next drill")
- F12 made-putt detection (second region at the hole)
- CloudKit sync, coach accounts (§10)
