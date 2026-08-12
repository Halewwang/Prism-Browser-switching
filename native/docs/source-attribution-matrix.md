# Source Attribution Evidence Matrix

## Purpose and evidence contract

This is a blank physical-evidence template for the Task 9 Debug probe. It does not certify any source application and must not be used to edit `SupportedSources.json`. Record a row only after a manual probe on an installed application; leave unavailable applications as **not installed / not measured**. Do not infer a pass from activation history, a visible application list, or a prior row.

A source is eligible only after committed evidence establishes all of the following for one exact bundle ID and an inclusive macOS version range:

- At least 20 cold-state samples and 20 warm-state samples.
- Every one of those samples is attributed with `confirmed` confidence, for at least 40 confirmed samples.
- Zero false attributions.
- A real `validatedAt` date and exact observed macOS boundaries.
- The evidence is reviewed and the matching manifest entry is committed in Task 18.

A `low` result is an activation-based inference, not proof; it is never a passing source-rule sample. An `Unknown` result is also not a passing sample.

## Required probe fields

| Field | Required recording |
| --- | --- |
| Timestamp | ISO 8601 time at which the probe result was observed. |
| App name | Display name reported by the operating system. |
| Bundle ID | Bundle identifier reported by the operating system. |
| Sender PID present | `yes` only if the Apple Event supplied `keySenderPIDAttr`; otherwise `no`. |
| Confidence | `confirmed`, `low`, or `unknown`. |
| Expected source | The application intentionally used for this sample. |
| State | `cold` after a fresh launch, or `warm` after the application is already running. |
| Pass/fail | `pass` only for a confirmed result matching the expected source and bundle ID; otherwise `fail`. |
| Notes | Installation state, observed OS version, mismatch details, or why the probe could not run. |

## Probe matrices

All rows below are intentionally blank. Do not replace blanks with assumed names, bundle IDs, PIDs, confidence, or passing results.

### DingTalk

Installation status: **not measured — complete only if DingTalk is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | DingTalk | cold |  |  |
| 2 |  |  |  |  |  | DingTalk | cold |  |  |
| 3 |  |  |  |  |  | DingTalk | cold |  |  |
| 4 |  |  |  |  |  | DingTalk | cold |  |  |
| 5 |  |  |  |  |  | DingTalk | cold |  |  |
| 6 |  |  |  |  |  | DingTalk | cold |  |  |
| 7 |  |  |  |  |  | DingTalk | cold |  |  |
| 8 |  |  |  |  |  | DingTalk | cold |  |  |
| 9 |  |  |  |  |  | DingTalk | cold |  |  |
| 10 |  |  |  |  |  | DingTalk | cold |  |  |
| 11 |  |  |  |  |  | DingTalk | cold |  |  |
| 12 |  |  |  |  |  | DingTalk | cold |  |  |
| 13 |  |  |  |  |  | DingTalk | cold |  |  |
| 14 |  |  |  |  |  | DingTalk | cold |  |  |
| 15 |  |  |  |  |  | DingTalk | cold |  |  |
| 16 |  |  |  |  |  | DingTalk | cold |  |  |
| 17 |  |  |  |  |  | DingTalk | cold |  |  |
| 18 |  |  |  |  |  | DingTalk | cold |  |  |
| 19 |  |  |  |  |  | DingTalk | cold |  |  |
| 20 |  |  |  |  |  | DingTalk | cold |  |  |
| 1 |  |  |  |  |  | DingTalk | warm |  |  |
| 2 |  |  |  |  |  | DingTalk | warm |  |  |
| 3 |  |  |  |  |  | DingTalk | warm |  |  |
| 4 |  |  |  |  |  | DingTalk | warm |  |  |
| 5 |  |  |  |  |  | DingTalk | warm |  |  |
| 6 |  |  |  |  |  | DingTalk | warm |  |  |
| 7 |  |  |  |  |  | DingTalk | warm |  |  |
| 8 |  |  |  |  |  | DingTalk | warm |  |  |
| 9 |  |  |  |  |  | DingTalk | warm |  |  |
| 10 |  |  |  |  |  | DingTalk | warm |  |  |
| 11 |  |  |  |  |  | DingTalk | warm |  |  |
| 12 |  |  |  |  |  | DingTalk | warm |  |  |
| 13 |  |  |  |  |  | DingTalk | warm |  |  |
| 14 |  |  |  |  |  | DingTalk | warm |  |  |
| 15 |  |  |  |  |  | DingTalk | warm |  |  |
| 16 |  |  |  |  |  | DingTalk | warm |  |  |
| 17 |  |  |  |  |  | DingTalk | warm |  |  |
| 18 |  |  |  |  |  | DingTalk | warm |  |  |
| 19 |  |  |  |  |  | DingTalk | warm |  |  |
| 20 |  |  |  |  |  | DingTalk | warm |  |  |

### Lark

Installation status: **not measured — complete only if Lark is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | Lark | cold |  |  |
| 2 |  |  |  |  |  | Lark | cold |  |  |
| 3 |  |  |  |  |  | Lark | cold |  |  |
| 4 |  |  |  |  |  | Lark | cold |  |  |
| 5 |  |  |  |  |  | Lark | cold |  |  |
| 6 |  |  |  |  |  | Lark | cold |  |  |
| 7 |  |  |  |  |  | Lark | cold |  |  |
| 8 |  |  |  |  |  | Lark | cold |  |  |
| 9 |  |  |  |  |  | Lark | cold |  |  |
| 10 |  |  |  |  |  | Lark | cold |  |  |
| 11 |  |  |  |  |  | Lark | cold |  |  |
| 12 |  |  |  |  |  | Lark | cold |  |  |
| 13 |  |  |  |  |  | Lark | cold |  |  |
| 14 |  |  |  |  |  | Lark | cold |  |  |
| 15 |  |  |  |  |  | Lark | cold |  |  |
| 16 |  |  |  |  |  | Lark | cold |  |  |
| 17 |  |  |  |  |  | Lark | cold |  |  |
| 18 |  |  |  |  |  | Lark | cold |  |  |
| 19 |  |  |  |  |  | Lark | cold |  |  |
| 20 |  |  |  |  |  | Lark | cold |  |  |
| 1 |  |  |  |  |  | Lark | warm |  |  |
| 2 |  |  |  |  |  | Lark | warm |  |  |
| 3 |  |  |  |  |  | Lark | warm |  |  |
| 4 |  |  |  |  |  | Lark | warm |  |  |
| 5 |  |  |  |  |  | Lark | warm |  |  |
| 6 |  |  |  |  |  | Lark | warm |  |  |
| 7 |  |  |  |  |  | Lark | warm |  |  |
| 8 |  |  |  |  |  | Lark | warm |  |  |
| 9 |  |  |  |  |  | Lark | warm |  |  |
| 10 |  |  |  |  |  | Lark | warm |  |  |
| 11 |  |  |  |  |  | Lark | warm |  |  |
| 12 |  |  |  |  |  | Lark | warm |  |  |
| 13 |  |  |  |  |  | Lark | warm |  |  |
| 14 |  |  |  |  |  | Lark | warm |  |  |
| 15 |  |  |  |  |  | Lark | warm |  |  |
| 16 |  |  |  |  |  | Lark | warm |  |  |
| 17 |  |  |  |  |  | Lark | warm |  |  |
| 18 |  |  |  |  |  | Lark | warm |  |  |
| 19 |  |  |  |  |  | Lark | warm |  |  |
| 20 |  |  |  |  |  | Lark | warm |  |  |

### WeChat

Installation status: **not measured — complete only if WeChat is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | WeChat | cold |  |  |
| 2 |  |  |  |  |  | WeChat | cold |  |  |
| 3 |  |  |  |  |  | WeChat | cold |  |  |
| 4 |  |  |  |  |  | WeChat | cold |  |  |
| 5 |  |  |  |  |  | WeChat | cold |  |  |
| 6 |  |  |  |  |  | WeChat | cold |  |  |
| 7 |  |  |  |  |  | WeChat | cold |  |  |
| 8 |  |  |  |  |  | WeChat | cold |  |  |
| 9 |  |  |  |  |  | WeChat | cold |  |  |
| 10 |  |  |  |  |  | WeChat | cold |  |  |
| 11 |  |  |  |  |  | WeChat | cold |  |  |
| 12 |  |  |  |  |  | WeChat | cold |  |  |
| 13 |  |  |  |  |  | WeChat | cold |  |  |
| 14 |  |  |  |  |  | WeChat | cold |  |  |
| 15 |  |  |  |  |  | WeChat | cold |  |  |
| 16 |  |  |  |  |  | WeChat | cold |  |  |
| 17 |  |  |  |  |  | WeChat | cold |  |  |
| 18 |  |  |  |  |  | WeChat | cold |  |  |
| 19 |  |  |  |  |  | WeChat | cold |  |  |
| 20 |  |  |  |  |  | WeChat | cold |  |  |
| 1 |  |  |  |  |  | WeChat | warm |  |  |
| 2 |  |  |  |  |  | WeChat | warm |  |  |
| 3 |  |  |  |  |  | WeChat | warm |  |  |
| 4 |  |  |  |  |  | WeChat | warm |  |  |
| 5 |  |  |  |  |  | WeChat | warm |  |  |
| 6 |  |  |  |  |  | WeChat | warm |  |  |
| 7 |  |  |  |  |  | WeChat | warm |  |  |
| 8 |  |  |  |  |  | WeChat | warm |  |  |
| 9 |  |  |  |  |  | WeChat | warm |  |  |
| 10 |  |  |  |  |  | WeChat | warm |  |  |
| 11 |  |  |  |  |  | WeChat | warm |  |  |
| 12 |  |  |  |  |  | WeChat | warm |  |  |
| 13 |  |  |  |  |  | WeChat | warm |  |  |
| 14 |  |  |  |  |  | WeChat | warm |  |  |
| 15 |  |  |  |  |  | WeChat | warm |  |  |
| 16 |  |  |  |  |  | WeChat | warm |  |  |
| 17 |  |  |  |  |  | WeChat | warm |  |  |
| 18 |  |  |  |  |  | WeChat | warm |  |  |
| 19 |  |  |  |  |  | WeChat | warm |  |  |
| 20 |  |  |  |  |  | WeChat | warm |  |  |

### Slack

Installation status: **not measured — complete only if Slack is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | Slack | cold |  |  |
| 2 |  |  |  |  |  | Slack | cold |  |  |
| 3 |  |  |  |  |  | Slack | cold |  |  |
| 4 |  |  |  |  |  | Slack | cold |  |  |
| 5 |  |  |  |  |  | Slack | cold |  |  |
| 6 |  |  |  |  |  | Slack | cold |  |  |
| 7 |  |  |  |  |  | Slack | cold |  |  |
| 8 |  |  |  |  |  | Slack | cold |  |  |
| 9 |  |  |  |  |  | Slack | cold |  |  |
| 10 |  |  |  |  |  | Slack | cold |  |  |
| 11 |  |  |  |  |  | Slack | cold |  |  |
| 12 |  |  |  |  |  | Slack | cold |  |  |
| 13 |  |  |  |  |  | Slack | cold |  |  |
| 14 |  |  |  |  |  | Slack | cold |  |  |
| 15 |  |  |  |  |  | Slack | cold |  |  |
| 16 |  |  |  |  |  | Slack | cold |  |  |
| 17 |  |  |  |  |  | Slack | cold |  |  |
| 18 |  |  |  |  |  | Slack | cold |  |  |
| 19 |  |  |  |  |  | Slack | cold |  |  |
| 20 |  |  |  |  |  | Slack | cold |  |  |
| 1 |  |  |  |  |  | Slack | warm |  |  |
| 2 |  |  |  |  |  | Slack | warm |  |  |
| 3 |  |  |  |  |  | Slack | warm |  |  |
| 4 |  |  |  |  |  | Slack | warm |  |  |
| 5 |  |  |  |  |  | Slack | warm |  |  |
| 6 |  |  |  |  |  | Slack | warm |  |  |
| 7 |  |  |  |  |  | Slack | warm |  |  |
| 8 |  |  |  |  |  | Slack | warm |  |  |
| 9 |  |  |  |  |  | Slack | warm |  |  |
| 10 |  |  |  |  |  | Slack | warm |  |  |
| 11 |  |  |  |  |  | Slack | warm |  |  |
| 12 |  |  |  |  |  | Slack | warm |  |  |
| 13 |  |  |  |  |  | Slack | warm |  |  |
| 14 |  |  |  |  |  | Slack | warm |  |  |
| 15 |  |  |  |  |  | Slack | warm |  |  |
| 16 |  |  |  |  |  | Slack | warm |  |  |
| 17 |  |  |  |  |  | Slack | warm |  |  |
| 18 |  |  |  |  |  | Slack | warm |  |  |
| 19 |  |  |  |  |  | Slack | warm |  |  |
| 20 |  |  |  |  |  | Slack | warm |  |  |

### Finder

Installation status: **not measured — complete only if Finder is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | Finder | cold |  |  |
| 2 |  |  |  |  |  | Finder | cold |  |  |
| 3 |  |  |  |  |  | Finder | cold |  |  |
| 4 |  |  |  |  |  | Finder | cold |  |  |
| 5 |  |  |  |  |  | Finder | cold |  |  |
| 6 |  |  |  |  |  | Finder | cold |  |  |
| 7 |  |  |  |  |  | Finder | cold |  |  |
| 8 |  |  |  |  |  | Finder | cold |  |  |
| 9 |  |  |  |  |  | Finder | cold |  |  |
| 10 |  |  |  |  |  | Finder | cold |  |  |
| 11 |  |  |  |  |  | Finder | cold |  |  |
| 12 |  |  |  |  |  | Finder | cold |  |  |
| 13 |  |  |  |  |  | Finder | cold |  |  |
| 14 |  |  |  |  |  | Finder | cold |  |  |
| 15 |  |  |  |  |  | Finder | cold |  |  |
| 16 |  |  |  |  |  | Finder | cold |  |  |
| 17 |  |  |  |  |  | Finder | cold |  |  |
| 18 |  |  |  |  |  | Finder | cold |  |  |
| 19 |  |  |  |  |  | Finder | cold |  |  |
| 20 |  |  |  |  |  | Finder | cold |  |  |
| 1 |  |  |  |  |  | Finder | warm |  |  |
| 2 |  |  |  |  |  | Finder | warm |  |  |
| 3 |  |  |  |  |  | Finder | warm |  |  |
| 4 |  |  |  |  |  | Finder | warm |  |  |
| 5 |  |  |  |  |  | Finder | warm |  |  |
| 6 |  |  |  |  |  | Finder | warm |  |  |
| 7 |  |  |  |  |  | Finder | warm |  |  |
| 8 |  |  |  |  |  | Finder | warm |  |  |
| 9 |  |  |  |  |  | Finder | warm |  |  |
| 10 |  |  |  |  |  | Finder | warm |  |  |
| 11 |  |  |  |  |  | Finder | warm |  |  |
| 12 |  |  |  |  |  | Finder | warm |  |  |
| 13 |  |  |  |  |  | Finder | warm |  |  |
| 14 |  |  |  |  |  | Finder | warm |  |  |
| 15 |  |  |  |  |  | Finder | warm |  |  |
| 16 |  |  |  |  |  | Finder | warm |  |  |
| 17 |  |  |  |  |  | Finder | warm |  |  |
| 18 |  |  |  |  |  | Finder | warm |  |  |
| 19 |  |  |  |  |  | Finder | warm |  |  |
| 20 |  |  |  |  |  | Finder | warm |  |  |

### Terminal

Installation status: **not measured — complete only if Terminal is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | Terminal | cold |  |  |
| 2 |  |  |  |  |  | Terminal | cold |  |  |
| 3 |  |  |  |  |  | Terminal | cold |  |  |
| 4 |  |  |  |  |  | Terminal | cold |  |  |
| 5 |  |  |  |  |  | Terminal | cold |  |  |
| 6 |  |  |  |  |  | Terminal | cold |  |  |
| 7 |  |  |  |  |  | Terminal | cold |  |  |
| 8 |  |  |  |  |  | Terminal | cold |  |  |
| 9 |  |  |  |  |  | Terminal | cold |  |  |
| 10 |  |  |  |  |  | Terminal | cold |  |  |
| 11 |  |  |  |  |  | Terminal | cold |  |  |
| 12 |  |  |  |  |  | Terminal | cold |  |  |
| 13 |  |  |  |  |  | Terminal | cold |  |  |
| 14 |  |  |  |  |  | Terminal | cold |  |  |
| 15 |  |  |  |  |  | Terminal | cold |  |  |
| 16 |  |  |  |  |  | Terminal | cold |  |  |
| 17 |  |  |  |  |  | Terminal | cold |  |  |
| 18 |  |  |  |  |  | Terminal | cold |  |  |
| 19 |  |  |  |  |  | Terminal | cold |  |  |
| 20 |  |  |  |  |  | Terminal | cold |  |  |
| 1 |  |  |  |  |  | Terminal | warm |  |  |
| 2 |  |  |  |  |  | Terminal | warm |  |  |
| 3 |  |  |  |  |  | Terminal | warm |  |  |
| 4 |  |  |  |  |  | Terminal | warm |  |  |
| 5 |  |  |  |  |  | Terminal | warm |  |  |
| 6 |  |  |  |  |  | Terminal | warm |  |  |
| 7 |  |  |  |  |  | Terminal | warm |  |  |
| 8 |  |  |  |  |  | Terminal | warm |  |  |
| 9 |  |  |  |  |  | Terminal | warm |  |  |
| 10 |  |  |  |  |  | Terminal | warm |  |  |
| 11 |  |  |  |  |  | Terminal | warm |  |  |
| 12 |  |  |  |  |  | Terminal | warm |  |  |
| 13 |  |  |  |  |  | Terminal | warm |  |  |
| 14 |  |  |  |  |  | Terminal | warm |  |  |
| 15 |  |  |  |  |  | Terminal | warm |  |  |
| 16 |  |  |  |  |  | Terminal | warm |  |  |
| 17 |  |  |  |  |  | Terminal | warm |  |  |
| 18 |  |  |  |  |  | Terminal | warm |  |  |
| 19 |  |  |  |  |  | Terminal | warm |  |  |
| 20 |  |  |  |  |  | Terminal | warm |  |  |

### Safari

Installation status: **not measured — complete only if Safari is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | Safari | cold |  |  |
| 2 |  |  |  |  |  | Safari | cold |  |  |
| 3 |  |  |  |  |  | Safari | cold |  |  |
| 4 |  |  |  |  |  | Safari | cold |  |  |
| 5 |  |  |  |  |  | Safari | cold |  |  |
| 6 |  |  |  |  |  | Safari | cold |  |  |
| 7 |  |  |  |  |  | Safari | cold |  |  |
| 8 |  |  |  |  |  | Safari | cold |  |  |
| 9 |  |  |  |  |  | Safari | cold |  |  |
| 10 |  |  |  |  |  | Safari | cold |  |  |
| 11 |  |  |  |  |  | Safari | cold |  |  |
| 12 |  |  |  |  |  | Safari | cold |  |  |
| 13 |  |  |  |  |  | Safari | cold |  |  |
| 14 |  |  |  |  |  | Safari | cold |  |  |
| 15 |  |  |  |  |  | Safari | cold |  |  |
| 16 |  |  |  |  |  | Safari | cold |  |  |
| 17 |  |  |  |  |  | Safari | cold |  |  |
| 18 |  |  |  |  |  | Safari | cold |  |  |
| 19 |  |  |  |  |  | Safari | cold |  |  |
| 20 |  |  |  |  |  | Safari | cold |  |  |
| 1 |  |  |  |  |  | Safari | warm |  |  |
| 2 |  |  |  |  |  | Safari | warm |  |  |
| 3 |  |  |  |  |  | Safari | warm |  |  |
| 4 |  |  |  |  |  | Safari | warm |  |  |
| 5 |  |  |  |  |  | Safari | warm |  |  |
| 6 |  |  |  |  |  | Safari | warm |  |  |
| 7 |  |  |  |  |  | Safari | warm |  |  |
| 8 |  |  |  |  |  | Safari | warm |  |  |
| 9 |  |  |  |  |  | Safari | warm |  |  |
| 10 |  |  |  |  |  | Safari | warm |  |  |
| 11 |  |  |  |  |  | Safari | warm |  |  |
| 12 |  |  |  |  |  | Safari | warm |  |  |
| 13 |  |  |  |  |  | Safari | warm |  |  |
| 14 |  |  |  |  |  | Safari | warm |  |  |
| 15 |  |  |  |  |  | Safari | warm |  |  |
| 16 |  |  |  |  |  | Safari | warm |  |  |
| 17 |  |  |  |  |  | Safari | warm |  |  |
| 18 |  |  |  |  |  | Safari | warm |  |  |
| 19 |  |  |  |  |  | Safari | warm |  |  |
| 20 |  |  |  |  |  | Safari | warm |  |  |

### Chrome

Installation status: **not measured — complete only if Chrome is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | Chrome | cold |  |  |
| 2 |  |  |  |  |  | Chrome | cold |  |  |
| 3 |  |  |  |  |  | Chrome | cold |  |  |
| 4 |  |  |  |  |  | Chrome | cold |  |  |
| 5 |  |  |  |  |  | Chrome | cold |  |  |
| 6 |  |  |  |  |  | Chrome | cold |  |  |
| 7 |  |  |  |  |  | Chrome | cold |  |  |
| 8 |  |  |  |  |  | Chrome | cold |  |  |
| 9 |  |  |  |  |  | Chrome | cold |  |  |
| 10 |  |  |  |  |  | Chrome | cold |  |  |
| 11 |  |  |  |  |  | Chrome | cold |  |  |
| 12 |  |  |  |  |  | Chrome | cold |  |  |
| 13 |  |  |  |  |  | Chrome | cold |  |  |
| 14 |  |  |  |  |  | Chrome | cold |  |  |
| 15 |  |  |  |  |  | Chrome | cold |  |  |
| 16 |  |  |  |  |  | Chrome | cold |  |  |
| 17 |  |  |  |  |  | Chrome | cold |  |  |
| 18 |  |  |  |  |  | Chrome | cold |  |  |
| 19 |  |  |  |  |  | Chrome | cold |  |  |
| 20 |  |  |  |  |  | Chrome | cold |  |  |
| 1 |  |  |  |  |  | Chrome | warm |  |  |
| 2 |  |  |  |  |  | Chrome | warm |  |  |
| 3 |  |  |  |  |  | Chrome | warm |  |  |
| 4 |  |  |  |  |  | Chrome | warm |  |  |
| 5 |  |  |  |  |  | Chrome | warm |  |  |
| 6 |  |  |  |  |  | Chrome | warm |  |  |
| 7 |  |  |  |  |  | Chrome | warm |  |  |
| 8 |  |  |  |  |  | Chrome | warm |  |  |
| 9 |  |  |  |  |  | Chrome | warm |  |  |
| 10 |  |  |  |  |  | Chrome | warm |  |  |
| 11 |  |  |  |  |  | Chrome | warm |  |  |
| 12 |  |  |  |  |  | Chrome | warm |  |  |
| 13 |  |  |  |  |  | Chrome | warm |  |  |
| 14 |  |  |  |  |  | Chrome | warm |  |  |
| 15 |  |  |  |  |  | Chrome | warm |  |  |
| 16 |  |  |  |  |  | Chrome | warm |  |  |
| 17 |  |  |  |  |  | Chrome | warm |  |  |
| 18 |  |  |  |  |  | Chrome | warm |  |  |
| 19 |  |  |  |  |  | Chrome | warm |  |  |
| 20 |  |  |  |  |  | Chrome | warm |  |  |

### Arc

Installation status: **not measured — complete only if Arc is installed.**

| # | Timestamp | App name | Bundle ID | Sender PID present | Confidence | Expected source | State | Pass/fail | Notes |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  | Arc | cold |  |  |
| 2 |  |  |  |  |  | Arc | cold |  |  |
| 3 |  |  |  |  |  | Arc | cold |  |  |
| 4 |  |  |  |  |  | Arc | cold |  |  |
| 5 |  |  |  |  |  | Arc | cold |  |  |
| 6 |  |  |  |  |  | Arc | cold |  |  |
| 7 |  |  |  |  |  | Arc | cold |  |  |
| 8 |  |  |  |  |  | Arc | cold |  |  |
| 9 |  |  |  |  |  | Arc | cold |  |  |
| 10 |  |  |  |  |  | Arc | cold |  |  |
| 11 |  |  |  |  |  | Arc | cold |  |  |
| 12 |  |  |  |  |  | Arc | cold |  |  |
| 13 |  |  |  |  |  | Arc | cold |  |  |
| 14 |  |  |  |  |  | Arc | cold |  |  |
| 15 |  |  |  |  |  | Arc | cold |  |  |
| 16 |  |  |  |  |  | Arc | cold |  |  |
| 17 |  |  |  |  |  | Arc | cold |  |  |
| 18 |  |  |  |  |  | Arc | cold |  |  |
| 19 |  |  |  |  |  | Arc | cold |  |  |
| 20 |  |  |  |  |  | Arc | cold |  |  |
| 1 |  |  |  |  |  | Arc | warm |  |  |
| 2 |  |  |  |  |  | Arc | warm |  |  |
| 3 |  |  |  |  |  | Arc | warm |  |  |
| 4 |  |  |  |  |  | Arc | warm |  |  |
| 5 |  |  |  |  |  | Arc | warm |  |  |
| 6 |  |  |  |  |  | Arc | warm |  |  |
| 7 |  |  |  |  |  | Arc | warm |  |  |
| 8 |  |  |  |  |  | Arc | warm |  |  |
| 9 |  |  |  |  |  | Arc | warm |  |  |
| 10 |  |  |  |  |  | Arc | warm |  |  |
| 11 |  |  |  |  |  | Arc | warm |  |  |
| 12 |  |  |  |  |  | Arc | warm |  |  |
| 13 |  |  |  |  |  | Arc | warm |  |  |
| 14 |  |  |  |  |  | Arc | warm |  |  |
| 15 |  |  |  |  |  | Arc | warm |  |  |
| 16 |  |  |  |  |  | Arc | warm |  |  |
| 17 |  |  |  |  |  | Arc | warm |  |  |
| 18 |  |  |  |  |  | Arc | warm |  |  |
| 19 |  |  |  |  |  | Arc | warm |  |  |
| 20 |  |  |  |  |  | Arc | warm |  |  |
