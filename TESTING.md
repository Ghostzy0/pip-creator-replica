# Test status

`swift test --jobs 2` passes 13 CreatorCore tests on macOS 27 with Swift 6.4. Coverage includes CSV/JSON validation, API provenance rejection across both source aliases and contradictory declarations, duplicate handling, unknown versus zero, formula-safe selected export, local persistence/recovery, workspace persistence, ID/metadata roundtrip and failed-write rollback.

For public candidate commit `2edca9e1a260595105379a0f434fcfa76e1a49e0`, the Neutral Core target compiled and a local ad-hoc-signed package passed strict signature and ZIP integrity checks. A synthetic-only native walkthrough saved CSV and JSON from an earlier package source; this candidate source has not yet been walked through natively or restored from a fresh GitHub clone. No visual/accessibility review or direct comparison with vidIQ has been completed.
