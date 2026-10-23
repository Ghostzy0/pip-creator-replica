# Creator Baseline

A community-built, offline macOS research app with navigation informed by vidIQ's public Help Center. It uses original code, product names, copy and styling; it is not affiliated with or endorsed by vidIQ. The project name `pip-creator-replica` describes the independent implementation goal, not a claim of 1:1 fidelity.

## Scope and evidence

The app provides a Neutral Core shell for documented creator workflows, local research notes, CSV/JSON import, search, provenance and raw values. Pages whose live data or service behavior is unavailable are labeled clearly. No signed-in visual comparison has been recorded. Public documentation does not expose exact product layout, hidden ranking, paid-plan behavior or proprietary scores.

No network calls, AI provider, YouTube analytics, search-volume estimates, competition scores, performance predictions, competitor monitoring or proprietary outlier ranking are implemented. This is a workflow baseline, not a faithful visual or algorithmic recreation.

## Build and test

Requires macOS 14 or newer and Swift 6.4 or a compatible later toolchain.

```sh
swift test --jobs 2
swift build -c release --product CreatorReplica
scripts/package-macos.sh
```

The packaging script creates a local ad-hoc-signed app and ZIP archive with source and SHA-256 receipts. It is not notarized. No public binary release is distributed.

## Public reference documentation

- [Navigating the vidIQ dashboard](https://support.vidiq.com/en/articles/9820526-navigating-your-new-dashboard)
- [Getting started with vidIQ](https://support.vidiq.com/en/articles/16976033-getting-started-with-vidiq)
- [Keyword research](https://support.vidiq.com/en/articles/9421214-keywords-research)

See [workflow parity](PARITY.md), [FAQ](FAQ.md), [test status](TESTING.md), [release state](RELEASES.md), and [acceptance gate](FINAL-GATE.md).
