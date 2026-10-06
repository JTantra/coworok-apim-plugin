# OEN domain reference

Source: CUA_Agent_Skills_Specification.md, version 1.0, dated 22 September 2026, section 5. These are supplied domain definitions and mappings, not live-verified configuration. Operational values must come from the OEN connector or the visible OEN UI.

## Vocabulary

| Term | Source definition |
|---|---|
| Network Savings | Sum of APT savings across all nodes on a voyage. Negative indicates voyage risk |
| APT Savings | Baseline APT minus achieved or projected APT for one node; positive is time recovered, negative is time lost |
| APT — Assured Port Time | Contracted port time for a vessel call; Baseline / Revised / Achieved triplet |
| Recovery Node | Node with most-positive APT savings |
| Worst Node | Node with most-negative APT savings |
| GBP — Gross Berth Productivity | Boxes handled per hour at berth; Baseline / Revised / Achieved triplet |
| OCI — Operational Container Intensity | Moves per container handled |
| PCI | Planning Container Intensity |
| ABT — Agreed Berth Time | Confirmed berthing window |
| BTR — Berth Time Requested | Requested berthing window |
| ETB / ATB | Estimated / Actual Time of Berthing |

Source berth status progression: PENDING → INCOMING → BTR → ABT → ETB → ATB → DEPARTED; SKIPPED represents a cancelled call. Preserve actual displayed statuses; do not infer a transition occurred.

Source risk rule: any node status indicating DELAYED, LATE, MISSED or AT_RISK, OR negative voyage Network Savings. The main skill specifies how incomplete UI evidence limits conclusions.

## PSA-operated node codes

Source list, preserved verbatim:

```text
PSAH, PENN, PPIT, SPIA, EXO, PSAA, SCT, BHCT, VECON, MIP,
SGPDM, PMUMB, PCHNN, NPCT1, PSASG, PSGGP, ESCO, BPCT, GCT,
FCT, FQCT, LPCT, TACT, DCT, ICT, PNIT
```

"PSA", "MESSAT" and "NEA" are category labels, not literal terminal codes. Use the visible Region/Partner selector for regional categories; the Node selector takes actual terminal options.

## Regional groupings

Source mappings, preserved without silently correcting spellings:

| Region | Node codes |
|---|---|
| AM — Americas | EXO, PPIT, PSAH |
| EU — Europe | BHCT, MPET, PSAA, PSAGP, SCT |
| MESSAT — Middle East, South Asia, Africa, Türkiye | PCHNN, PMUMB, SGPDM, MIP |
| NEA — Northeast Asia | HPNT, PNIT, BPCT, DCT, FCT, TPCT |
| SEA — Southeast Asia | ESCO, NPCT1, PSASG |

## Supplied node directory

| Code | Region | Country | Terminal |
|---|---|---|---|
| PSASG | SEA | Singapore | PSA Singapore |
| BHCT | EU | Poland | Baltic Hub Container Terminal |
| PMUMB | MESSAT | India | PSA Mumbai (BMCT) |
| PSAA | EU | Belgium | PSA Antwerp |
| PCHNN | MESSAT | India | PSA Chennai |
| MIP | MESSAT | Türkiye | Mersin International Port |
| NPCT1 | SEA | Indonesia | New Priok Container Terminal One |
| EXO | AM | Argentina | Exolgan Container Terminal |
| PSAH | AM | Canada | PSA Halifax |
| SCT | EU | Portugal | PSA Sines |

## Known source gaps and use rules

- The directory and regional mappings are incomplete relative to the PSA-operated list. Missing mappings stay unknown; do not invent them.
- The PSA list uses `PSGGP` while the EU mapping uses `PSAGP`. Treat this as an unresolved discrepancy, not an established alias.
- Some codes occur only in regional mappings. Do not automatically add them to the PSA-operated set or assume the sets should be identical.
- Verify selected terminal options against visible labels. If the UI contradicts the supplied reference, report the discrepancy and prefer the UI for the current task's observed values; do not silently overwrite the reference or switch terminals.
- If a requested code is unavailable, disclose the omitted terminal. Do not claim coverage of all PSA nodes.
- Identify future recovery candidates using visible node order, status and projected savings. A source-defined recovery node may describe historical recovery and is not automatically an actionable future node.
