# T008 Queue: Figma/native mapping

Target: Queue `11:105` in the existing
[ReturnQueue Figma file](https://www.figma.com/design/SMVZHX6PVpx83cRfqM6S2o/Untitled?node-id=11-105).
Root obtained high-fidelity context and screenshot before implementation. Current
status: root accepted T007/T008 on 2026-10-04 after distinct review, independent
106 native tests, both unsigned builds and five UI scenarios on a fresh simulator.
Root accepted normal/larger text rendering and the final independent grouped Queue
screenshot. This scoped comparison does not close T015.
The functional grouping/order contract is [queue.md](../../specs/001-free-return-prototype/contracts/queue.md).

| Figma slot | Native mapping |
| --- | --- |
| Return Queue title and Add | Native NavigationStack title/back and working Add toolbar action |
| Location headings and item cards | List sections; location separate from each item's merchant |
| Location pin | Exact downloaded 16pt QueueGroupPin SVG; vector preservation and 16pt frame |
| Card chevron | NavigationLink's native disclosure indicator opens current committed details |
| Entered return date | Existing day formatter includes year; unknown is explicitly Not set |
| Past entered date | Exact neutral text `Past your entered date`, named ColorWarning #9a4c12 |
| Surface/background/ink/secondary/accent/tint/line | Existing named assets; accent #3155cb |
| Typography and spacing | Semantic fonts/Dynamic Type and native List metrics/safe areas |

The illustrative Figma group order is not a sorting rule: named groups follow
the normalized key, unknown last. Cards follow entered day, creation timestamp,
then UUID; merchant names and policy guesses never supply deadlines. Unknown
expected amounts do not become zero. Production records are created by the user.

Figma's device/status/Home indicators are drawn by iOS. Settings, repeated P2 tabs,
and unimplemented state/reminder actions remain outside this slice. Loading,
blocked-read recovery and temporary-copy cleanup keep their accepted T006 guards;
an unready or failed load does not show a successful empty Queue.

Asset provenance: `/private/tmp/returnqueue-t008-group-pin.svg`, exact SHA-256
`dfef988a9fa8ebcbfd26840fe1e50cdb139e1a91f032358de42a47e91c440415`.
The 24pt DetailPin is not reused as a replacement. Context:
`/private/tmp/returnqueue-t008-figma-context.txt`; target screenshot:
`/private/tmp/returnqueue-t008-figma.png`. These screenshots are reference material,
not bundled assets. Actual rendered proof belongs in the feature verification
document: [accepted runtime evidence](../../specs/001-free-return-prototype/verification.md).
The normal screenshot now comes from final independent QA; the larger-text
screenshot comes from the author device. Root's screenshots are in the task
visualization directory as `returnqueue-queue.png`
and `returnqueue-queue-large-text.png`; report
`/private/tmp/returnqueue-t008-root-visual.json`.
