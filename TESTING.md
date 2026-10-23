# Test status

`swift test --jobs 2` passes 12 CreatorCore tests on macOS 27 with Swift 6.4. Coverage includes CSV/JSON validation, API provenance rejection, duplicate handling, unknown versus zero, formula-safe export, local persistence/recovery, metadata roundtrip and failed-write rollback.

The Neutral Core app target compiles and has a local ad-hoc-signed package with a verified SHA-256 receipt. The package was not launched. No runtime walkthrough, visual or accessibility review, or direct comparison with vidIQ has been completed. Build and test a clean clone before relying on these results.
