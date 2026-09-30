# Native release acceptance

Status: **physical acceptance not performed for this iteration**. Automated tests exercise constructed inputs and injected failures. They do not certify sender attribution from real application clicks, browser login state, or OS recovery behavior.

## Candidate environment inventory

The release coordinator inspected this machine's macOS version/architecture and installed application `CFBundleShortVersionString` values. This inventory establishes availability only; it is not a click test, profile-handoff result, or supported-source certification.

| Component | Observed metadata | Physical acceptance |
| --- | --- | --- |
| macOS / architecture | 27.2 / arm64 | Not performed |
| Chrome | 154.0.8037.59 | Not performed |
| Safari | 27.2 | Not performed |
| Arc | 1.153.1 | Not performed |
| WeChat | 4.1.13 | Not performed |
| DingTalk | 9.0.1 | Not performed |
| Lark | 147.0.7727.149 | Not performed; this bundle metadata may identify the Electron runtime rather than the displayed application version |
| Edge | Not installed | Not measured |
| Slack | Not installed | Not measured |

An exact `major.minor.patch` OS value must be independently recorded before running the evidence summary. Do not infer a patch component or manifest OS range from the inventory above.

## Source rules and evidence

A link with a nonempty `confirmed` source can open a prefilled rule editor. The source support manifest controls the displayed verification status for the current macOS version; it does not grant source confidence. An empty, missing, malformed, or out-of-range manifest leaves the source **pending verification**. Saved source rules run only when macOS confirms the source for that individual link. `low` and `unknown` sources cannot use the source-rule shortcut and cannot trigger source routing.

Do not populate `SupportedSources.json` from mocks, name matching, activation history, or this checklist. The Debug source probe records only capture ID, fractional ISO timestamp, app name, bundle ID, sender-PID presence, confidence, expected source, cold/warm state, and the operator's pass/fail result. Do not copy link URLs, message content, credentials, or private conversations into evidence.

For each installed source application (DingTalk, Lark/Feishu, WeChat, Slack, Finder, Terminal, Safari, Chrome, Arc), use a dedicated test link and manually record 20 independent cold clicks and 20 independent warm clicks. Quit/relaunch the source before each cold sample; warm samples use an already running source. New records assign a fresh capture UUID to each diagnostic, so two actual captures within one second remain independent and repeat saves of one capture do not increase counts. Legacy rows without capture IDs still deduplicate by timestamp; legacy evidence clicks must be at least one second apart. Rapid multi-link behavior is also a separate acceptance case. Record the exact app version and macOS version separately in the evidence matrix. Mark unavailable applications **not installed / not measured**. If a source cannot produce independent cold samples, leave that requirement unmet rather than relabel warm samples.

Before capture, independently inspect the installed application's bundle ID and enter it in the probe's **Expected bundle ID** field. This field starts empty and clears when the expected application changes; do not use the captured result as the expected identity. The recorder requires operator pass, confirmed confidence, sender PID, and an exact match against that independent expected bundle ID. Display names may be Chinese or another language and do not decide pass/fail. The summary checks a separately supplied exact bundle ID again; it never infers an expected identity from capture contents. The recorder has no OS field, so use one homogeneous OS session per input file; do not combine files from different macOS versions.

Run the summary against the tester's chosen JSONL file, substituting the independently observed identity and OS:

```sh
python3 native/scripts/summarize-source-probe.py /path/to/session.jsonl \
  --macos 26.0.1 --expected-bundle Slack=com.tinyspeck.slackmacgap
```

Supply one `--expected-bundle` for every expected application in the file. This example is a command format, not measured evidence. The command emits acceptance counts and exits 0 only when every listed app has at least 20 cold plus 20 warm unique captures, all samples are confirmed correct with sender PID and operator pass, and there are zero false attributions and zero invalid rows. New rows deduplicate by capture UUID; conflicting copies of the same UUID count as invalid evidence, even when their timestamps differ. Legacy eight-field rows deduplicate by strict UTC ISO timestamp. Combining an ID-based row and a legacy row within the same second is ambiguous and fails closed; summarize old and new sessions separately. A missing optional bundle ID from Swift's JSON encoder is a failed unknown sample, not a successful sample. Unexpected fields, malformed rows, invalid UUIDs, or sources missing from the independent identity mapping fail closed without echoing row contents. The command never writes the manifest. A reviewer must inspect real evidence, confirm observed OS bounds and validation date, and approve any later manifest change.

## Manual end-to-end checklist

Record build/version, exact macOS version, app/browser versions, tester, date, outcome, and evidence reference for each case. Use isolated test messages/pages/accounts. These rows remain unexecuted until a human performs them.

| Case | Action and expected result | Current status |
| --- | --- | --- |
| Source cold/warm matrix | Real clicks for each installed source, 20 cold + 20 warm; record confirmed identity and any mismatch. Summary meets evidence threshold; unmeasured apps remain pending. | Not performed |
| Probe identity and repeat save | Independently enter the correct expected bundle for a source with a localized name. Confirm correct ID passes and a wrong ID fails. Save one capture twice; capture IDs remain the same and summary counts once. Make two real rapid clicks; IDs differ and both count. | Not performed |
| Pending source rule | On a confirmed but unlisted source, open Remember editor; show pending verification, correct source and chosen browser. Save then click again; execute only for confirmed source. | Not performed |
| Verified source rule | With reviewed manifest evidence covering this OS, show verified status in editor and rule row. Outside that OS range show pending verification. | Not performed; no approved source evidence |
| Inferred or unknown source | Force a path with absent/unresolvable sender PID; show inferred/unknown state, hide source shortcut, and keep the picker instead of executing a source rule. | Not performed |
| Multiple links | Send several distinct dedicated test links quickly from one source and from alternating sources. Preserve each URL/source pair, waiting count and order; completing one request does not drop or reroute another. | Not performed |
| Missing/invalid target | Create a rule for a test browser, then remove/rename it in an isolated environment. A new matching link returns to the picker with an actionable reason; selecting another browser completes that request. | Not performed |
| Chrome Profile cold launch | With Chrome quit, choose a dedicated test Profile. Confirm the example link appears once in that Profile and the expected account context. | Not performed |
| Chrome Profile while running | With another Chrome Profile already open, choose the test Profile. Confirm Chromium's process handoff keeps the selected Profile and opens only once. | Not performed |
| Edge Profile cold and warm | Repeat both cases in Edge with two dedicated test Profiles; record browser version and exact macOS version. | Not performed |
| Deleted Profile | Save a rule, preferred target and pending retry using a disposable Profile; remove it. Each route must report unavailable and must not create a new Profile or silently open another. | Not performed |
| All choices hidden | Hide all targets, trigger the chooser and use Manage Browsers to show one again. Hidden targets continue to work for automatic rules and preferred fallback. | Not performed |
| Browser launch failure | Induce an isolated launch failure. Retry the same browser or select another; do not report success before launch result. Preserve a recoverable request if retry fails. | Not performed |
| Login redirect | Use a dedicated signed-out test account and click a login-required page. Choose the intended browser/profile, complete login, and verify redirect returns to that browser/profile without changing attribution or bypassing rules. | Not performed |
| Recovery after interruption | Interrupt an isolated build after a request is persisted but before launch completion. Reopen and inspect pending/uncertain state; explicit retry or Mark Completed resolves only that request. | Not performed |
| Storage unavailable | Make the isolated recovery store unwritable. Keep the request visible, explain storage failure, and require a valid browser for explicit retry. | Not performed |
| Default handler and installation | Tester records the current handler and uses a dedicated environment. Confirm setup/status wording and restore the environment after testing. This iteration does not change the user's default handler. | Not performed |

## Automated checks

Run the Swift core suite and the Xcode native unit scheme; source-status regression cases live in `SelectorViewModelTests`, `SourceAttributionTests`, and `RuleEditorDraftTests`. Run the summary's synthetic tests separately:

```sh
python3 -m unittest discover -s native/scripts -p test_source_probe_summary.py -v
```

Passing these tests verifies the confidence gate, draft/status behavior, manifest OS bounds and JSONL filtering/counting. It does not complete any manual row above. Release notes must keep the distinction visible and must not claim verified support for applications without approved physical evidence.
