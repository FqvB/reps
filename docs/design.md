# Design

- Figma: https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1
- Theme: white/light app. The one exception is the clip detail player, which is dark and full-bleed with floating translucent pills (spec §5.3b, v8).
  - Tokens: `Reps/UI/Theme/Theme.swift` (values read from frames 01, 02, 06, 13). Shared components live in `Reps/UI/Components/`: footer CTA, pill, chip, dashed add button, toggle row, field card, block row, undo toast. Alerts use native `.alert`.
- Session screen: one big number and one chip, large glove-friendly tap targets (spec §2 NFR).

When building a screen, use the `figma:figma-design-to-code` / `figma:figma-swiftui` skills with the frame link for that screen.

## Screen → frame map

The file has a single page for this project, and everything on it is current. Frames are 393×852. No Figma variables or styles: values are raw per layer, so the app keeps its own theme (`Reps/UI/Theme`).

| Screen | Issue | Figma frame |
|---|---|---|
| Onboarding (welcome, bag, permissions) | #5 | [07 Welcome](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=8-2), [08 Your bag](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=8-46), [09 Camera](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=8-134) |
| Plans list | #7 | [01 Plans](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=1-2) |
| Plan editor | #7 | [02 Plan editor](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=2-2), [06 Block editor sheet](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=4-35), [13 Discard alert](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=13-56) |
| Session (live) | #9 | [03 Range + clips](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=3-2), [05 Putting](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=4-2), [14 Next block early](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=13-150) |
| Session summary | #11 | [12 Session summary](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=12-169) |
| Session log | #12 | not designed; follow the Plans list and summary styles |
| Settings | #6 | [10 Settings](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=12-2) |
| Ball lock box + tap override | #15 | no frame; only the preview mock inside 03/05 (node 4:20) |
| Video library | #24 | [04 Library](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=3-55) |
| Clip detail | #25 | [11 Clip detail](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=12-108), [15 Delete alert](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=18-105) |
