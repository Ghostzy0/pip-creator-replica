# Creator workflow parity

Updated 23 October 2026. This matrix separates the improved custom app from the documented vidIQ workflow baseline. “Documented” means a public Help Center page describes the capability; it does not establish exact UI, algorithm or runtime behavior.

| Workflow | Publicly documented vidIQ behavior | CreatorReplica baseline | Pip Creator custom app | Evidence gap |
|---|---|---|---|---|
| Home / Feed | Home feed has creator suggestions, insights and activity | Local library counts and saved records; no personalized feed | Local library overview | No direct UI comparison or live feed |
| Optimize | Select a video to improve title, thumbnail and description | Local record review and notes only | Saves source/title and private notes | No optimization model, thumbnail analysis or live account data |
| Chat | AI Coach / Chat is available in dashboard navigation | Explicitly inactive; no provider called | Not implemented | Plan, model behavior and UI unavailable |
| Research / Keywords | Keyword search with estimated volume, competition/overall score, related terms, matching terms and questions | Search local titles/notes only; no estimated values or generated suggestions | Manual titles/seeds and imported notes | Proprietary data and exact algorithm unavailable |
| Research / Outliers | Research can surface outlier videos | Browse only values supplied by the user; no outlier ranking | Searchable user library with raw supplied values | No live tracking or outlier algorithm |
| Daily Ideas | Personalized/custom ideas described in public docs | Store manually researched idea records only | Manual title/source note; workspaces in Plus | Prediction and AI disabled |
| Competitors | Competitor tracking described in product materials | Store manually entered records, no monitoring | Notes and grouping only | No connected channel monitoring |
| Subscriber analytics | Subscriber analysis appears in product materials | Explicitly unavailable offline | No owner analytics connection | No account workflow or API approval |
| Import/export | Not a parity claim | Local CSV/JSON/manual record workflow | Local CSV/JSON/manual library | External integrations not implemented |

## Evidence levels

- **Publicly documented:** official help page text, linked in `REPLICA-PLAN.md`.
- **Directly observed:** none yet for vidIQ’s signed-in UI.
- **Inferred:** local presentation choices that make a desktop workflow navigable; do not represent proprietary components or algorithm behavior.
- **Unavailable:** live scores/volume, generated output, private channel metrics, authenticated account states, and exact hidden algorithms.

CreatorReplica’s current shell is a reconstruction of the documented information architecture, not a completed or runtime-verified faithful recreation. No hands-on vidIQ session or comparison capture has been collected.
