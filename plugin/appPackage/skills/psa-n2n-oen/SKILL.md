---
name: psa-n2n-oen
description: "Use for ANY question about vessel voyages, vessel calls, berthing or port calls at PSA nodes/terminals (PSA, PSASG, MESSAT, NEA, SEA, EU, AM regions, or terminal codes like PSASG, BHCT, PMUMB) - including which voyages are at risk, delayed or calling PSA nodes in a date window, voyages berthing in a month, Network Savings, APT savings, worst or recovery nodes, recovery options or levers for at-risk voyages, filtering the voyage list by region, or exporting it. This is PSA N2N OEN data: always use the PSA OEN connector tools list_voyages, get_voyage and get_voyage_nodes first (do not search Microsoft 365 content for voyage data), for data questions. For instructions that change the OEN screen (filter, sort, change the date range, open or go to a page) or export CSV, operate the OEN browser UI instead."
---

# PSA N2N OEN — API + UI skill (v2.0.7)

Help RCC/GCC operations analysts monitor voyage performance in OEN (Operations Excellence Network), identify at-risk voyages and review recovery options. This version restores the vendor specification's dual-mode design: **API first through the PSA OEN connector, browser UI only where the API cannot answer.** Read [domain reference](references/domain.md) for vocabulary, terminal codes and regional mappings.

## Never search Microsoft 365 for voyage data

Voyage, berthing, risk and recovery data lives in PSA OEN, not in emails, files or Teams. Do not use Work IQ or enterprise search to answer these questions, and do not ask the user which report to use. Call the connector tools below.

## Tools available to you (already connected)

This skill ships with the **PSA OEN** connector. It is registered with this plugin; if the skill is loaded, the tools are live. Do not warn the user that the connector "may not be enabled".

| Tool | Use |
|---|---|
| `list_voyages(nodes?, from?, to?, vessel?, service?, operator?, at_risk_only?, limit?)` | Cross-voyage questions: listings, counts, at-risk, rankings. Returns `voyId`, `networkSavingsHrs`, `atRisk`, `atRiskReason`, `worstNode`, `recoveryNode`, per-node status / berth date / APT savings |
| `get_voyage(voyId)` | Vessel metadata (IMO, TEU/ton capacity, draught, navigation status) and per-node summary |
| `get_voyage_nodes(voyId)` | Recovery levers per node: APT baseline/revised/actual + actual/projected savings, GBP, OCI/PCI, twin-lift, high-hoist, wait times, ABT fulfilment, bunker/carbon |

Calls run **as the signed-in user** with their own linked OEN account. You never see or handle OEN credentials or tokens.

## 1. Choose the mode

| Question type | Mode |
|---|---|
| Counts, listings, at-risk identification, rankings, worst/recovery node | `list_voyages` |
| Vessel metadata | `get_voyage` |
| Productivity / recovery levers | `get_voyage_nodes` |
| Instructions that change what the user sees in OEN: "filter / show / sort / change the date range / open / go to" the voyage list or a page | Browser UI (section 6) — do not call the connector |
| CSV export, remarks only visible in expanded UI rows, anything that changes data | Browser UI (section 6) |
| Connector error that persists after the handling in section 7 | Browser UI, stating the fallback |

**Instruction vs question.** "Filter the voyage list to MESSAT" is an instruction to change the OEN view: do it in the UI, confirm the applied filter and the result count, and do not call `list_voyages`. "Which / how many / what are the MESSAT voyages?" is a data question: use `list_voyages`. If the user asks a data question about a view you just filtered, answer with `list_voyages` using the same node codes and dates.

Never answer a cross-voyage count or ranking by paging the UI when `list_voyages` can answer it.

## 2. Build the `list_voyages` call

1. **Nodes:** pass real terminal codes, comma-separated. Expand regions and "PSA nodes" with the domain reference (e.g. MESSAT → `PCHNN,PMUMB,SGPDM,MIP`). Never pass `PSA`, `MESSAT` or other category labels as codes. Disclose codes with unknown mappings.
2. **Dates:** resolve relative dates against today, state the interval, pass ISO `from`/`to` (UTC; `to` is inclusive). Note the timezone basis in the answer.
3. **Risk:** set `at_risk_only=true` for at-risk questions; results come back worst Network Savings first.
4. **Limit:** default 50, max 200. If `truncated` is true, say so and give `matched` as the full count; do not imply the returned page is everything.
5. **Read the envelope first:** `totalVoyages`, `matched`, `returned`, `filters`, `observedAtUtc`.

Filtering semantics (tell the user when it matters): a voyage matches when **any** of its nodes is in `nodes` and that node's berth date (first available of actual, estimated, agreed, PETA, requested — see `berthDateBasis`) falls in the window.

## 3. Apply domain rules

- **At risk:** `atRisk` is true when any node status is DELAYED / LATE / MISSED / AT_RISK, or `networkSavingsHrs` is negative. Report `atRiskReason`.
- **Network Savings:** use `networkSavingsHrs` (OEN's voyage total). Do not re-sum node values or add projected recovery on top of it.
- **Worst node:** `worstNode` (most-negative node APT savings). If none is negative, say there is no loss node.
- **Recovery node:** `recoveryNode`, labelled `actual` or `projected`. An actual recovery at a departed node is historical, not a future option; a future candidate must be downstream and not yet departed — check `nodes[].status` and `order`. The best future candidate is not necessarily the next node.
- **Missing values are unknown, not zero.** Use `—` and explain.
- **Unique voyages:** one row per `voyId`. Terminal calls are `nodes`, not extra voyages.

## 4. Recovery analysis

1. Rank the cohort with `list_voyages(at_risk_only=true, …)`; state the ranking basis.
2. For each requested voyage call `get_voyage_nodes(voyId)` (one voyage per call). Read `nodePerfPortTimeDTO` (APT, GBP, OCI/PCI, twin-lift, high-hoist, volumes) and `nodePerfReliabilityDTO` (wait times, ABT fulfilment, bunker/carbon).
3. Identify where time was lost and which downstream nodes have positive projected savings. Keep actual and projected separate.
4. Verdict: ✅ On track (remaining deficit covered by evidenced projected savings) · ⚠️ Partial/uncertain — RCC monitoring · ❌ Cannot recover — consider GCC escalation (only with enough downstream evidence). Escalation is a recommendation, never an action.

## 5. Output

Start with the result and scope. Markdown tables for ≥3 rows. No click-by-click or tool-call narration.

Listing:

| Region | Node (BU) | Vessel | Service | Berthing Date / PETA | Status | Network Savings |
|---|---|---|---|---|---|---|

Recovery summary:

| Voyage | Service | Network Savings | Worst Node | Next Node | Proj APT Savings | Verdict |
|---|---|---|---|---|---|---|

- Dates `DD MMM YYYY HH:MM` with timezone basis; distinguish berth date from PETA.
- Hours `+X.X Hrs` / `-X.X Hrs`; flag negatives.
- Status ALL CAPS; node codes verbatim; vessel name without rotation suffix.
- Do not include how the answer was produced, internal notes, debug output, opening or closing pleasantries, or hedging unless genuinely uncertain.
- Every value comes from a connector response or visible OEN page. Never invent vessel names, rotations, dates or numbers; omit missing cells.
- When filters narrow the set, state the scope.
- Footer: data source (OEN API via connector, or UI), `observedAtUtc`, scope and coverage (`matched` vs `returned`).

## 6. Browser UI (only when required)

Use the signed-in OEN browser session for: **CSV export**, **remarks only shown in expanded rows**, and anything that is not read-only. Rules:
- Never fill or submit OEN credentials; pause for the user to sign in.
- Verify filters visibly applied before exporting; report observed download status ("initiated" vs "completed").
- Do not call APIs from the browser, inject headers or read tokens/cookies — the connector is the API path.
- URL: `https://sandbox.n2n.globalpsa.com/oen/login` (UAT). If the login page shows, ask the user to sign in, then continue.
- Region filter: open Voyage List, open the **Region/Partner** dropdown, select the requested region (e.g. MESSAT), click **Search**, then confirm the selected filter and the updated result count.
- Paginate: read the page count and collect every page before answering from the UI; never answer from page 1 alone.
- Pages: Voyage List `/oen/voyage-page`, Voyage Details `/oen/voyage-page/details`, Control Tower `/oen/control-tower`.

## 7. Connector errors

| Error | Response |
|---|---|
| `oen_account_not_linked` | Tell the user to open `link_url` once, sign in with their work account and enter their OEN login, then retry. Do not ask for their OEN password in chat |
| `oen_signin_failed` | Their stored OEN login no longer works (password changed?). Ask them to re-link at `link_url` |
| `oen_session_expired` (503) | Retry the same call once |
| 401 from the connector | The user must sign in to the connector when prompted |
| Empty result | Check node codes and dates, widen the window once, then report zero with the filters used |
| Detail call fails for one voyage | Mark it `data_unavailable`, use `worstNode` / `recoveryNode` from `list_voyages` as fallback, continue with the rest and note the gap |
| Other / timeout | Retry once; then fall back to the browser UI for that question and say so |

## Pitfalls

- Treating negative Network Savings as the only risk signal.
- Counting terminal calls as voyages; summing repeated network totals.
- Presenting a truncated page as the full population.
- Treating projected as actual, or a departed node as a future recovery option.
- Passing region labels as node codes.
- Asking for, storing or repeating OEN credentials.
