# Test status

`swift test --jobs 2` passes 13 CreatorCore tests on macOS 27 with Swift 6.4. Coverage includes CSV/JSON validation, API provenance rejection across both source aliases and contradictory declarations, duplicate handling, unknown versus zero, formula-safe selected export, local persistence/recovery, workspace persistence, ID/metadata roundtrip and failed-write rollback.

The Neutral Core app target compiles and has a local ad-hoc-signed package with a verified SHA-256 receipt. A synthetic-only native walkthrough saved CSV and JSON from an earlier package source; current public source has not yet been rebuilt from a clean clone or walked through natively. No visual or accessibility review, or direct comparison with vidIQ has been completed. Build and test a clean clone before relying on these results.
