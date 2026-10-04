# T006 Figma/native mapping

Scope: Add 11:194 and Detail 11:243 in
[ReturnQueue Figma](https://www.figma.com/design/SMVZHX6PVpx83cRfqM6S2o/Untitled).
High-fidelity design context and screenshots were obtained before implementation;
root compared the rendered Add and saved Detail screens with those targets on
2026-10-04 and accepted this scope with the native adaptations below.

| Design slot | Native implementation contract |
| --- | --- |
| Navigation/back/Cancel/Save/Edit | NavigationStack, sheet and semantic toolbar actions; system safe areas/chrome |
| Item name/Merchant and Optional details | Form fields with expandable optional section; semantic fonts and labels |
| Add information card | File-owned Tint token, exact downloaded 28pt AddHeroPackage SVG |
| Detail drop-off location card | Exact downloaded 24pt DetailPin SVG; current value or Not set |
| Background/surface/ink/secondary/tint/line | Named asset colors matching custom Figma variables |
| Interactive accent | AccentColor asset #3155cb, inherited by native controls |
| Entered dates and USD amounts | Manual day text and exact decimal inputs; unknown stays Not set, no implicit date/zero |
| Detail title/merchant/status/values/notes | Current committed item by ID; Dynamic Type and truthful state text |

Figma's status/Home indicators and device bezel are template chrome; iOS draws
actual chrome. Native Form/toolbar metrics adapt to device size and text scale.
Figma example purchase values never become default or seeded app data. Detail's
Mark as dropped off, Keep item and Reminder actions await T010/T011/P2; repeated
four-tab bar awaits later navigation scope. They are omitted from this slice so
the visible controls actually work. At the T006 handoff, T008 grouped/sorted Queue
was open; its later acceptance is recorded in [the Queue mapping](t008-native-mapping.md).
T006 used a simple list only to reach Add and details.

The provided design is light; this slice uses that appearance explicitly. Dark
appearance and the broader accessibility acceptance remain part of T015. System
fonts support Dynamic Type; this does not claim those later checks are complete.

Asset provenance: original get_design_context GET assets were downloaded to
`/private/tmp/returnqueue-add-hero-package.svg` and
`/private/tmp/returnqueue-detail-pin.svg`. These exact bytes are copied into their
local image sets; the design screenshots are visual targets, never app assets.
Actual package/pin geometry and colors passed root's rendered review. Stable
screenshots: `/Users/aagataev/.codex/visualizations/2026/10/03/01a1012c-4737-7c71-8587-6600853c8fec/returnqueue-add-return.png`
and adjacent `returnqueue-return-detail.png`. Author and independent simulator
results are recorded in the T006 section of
[verification.md](../../specs/001-free-return-prototype/verification.md).
