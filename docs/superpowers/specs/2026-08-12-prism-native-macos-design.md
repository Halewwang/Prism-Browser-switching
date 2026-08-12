# Prism Native macOS 1.0 Design

Date: 2026-08-12

Status: Approved design, pending implementation plan

Target: macOS 15 and later

Distribution: Direct signed and notarized Universal DMG

Visual direction: Native Clarity

## 1. Objective

Rebuild Prism as a native macOS application using SwiftUI and AppKit. The native edition replaces the Electron application rather than embedding or gradually converting its runtime.

The first native release is a stable public edition. It prioritizes:

- Every HTTP or HTTPS request is received and processed exactly once.
- Multiple requests remain ordered and cannot overwrite one another.
- Source applications are never guessed.
- Browser launches are recorded as successful only after macOS confirms the launch request.
- Failures preserve the affected link and give the user a recovery action.
- The interface behaves as a native macOS utility.
- The release is signed, notarized, updateable, and accurately documented.

The existing Electron application and its data remain untouched. Native Prism starts with a new data store and does not import Electron rules, settings, custom browsers, or history.

## 2. Confirmed Product Decisions

| Area | Decision |
|---|---|
| Release scope | Stable public edition |
| Minimum system | macOS 15+ |
| Unmatched links | Always show the browser selector by default |
| Source rules | Enable only for source applications that pass the validation matrix |
| Visual direction | Native Clarity |
| Existing Electron data | Start fresh; do not import or delete it |
| Distribution | Website or GitHub direct download |
| Application structure | SwiftUI features + AppKit system control + independent Swift core |
| Selector design | Figma node `4:395` is the single visual source of truth |
| More than three browsers | Horizontal scrolling with three full items and half of the fourth visible |

## 3. Release Scope

### 3.1 Included

- Native first-run onboarding.
- Explicit HTTP and HTTPS default-handler setup and status.
- FIFO link intake queue with unique request IDs and deduplication.
- Browser discovery through macOS.
- Custom browser selection.
- Browser ordering for the selector.
- Native browser icons.
- URL rules.
- Validated source-application rules.
- Explicit rule priority and user-controlled order.
- Browser selector panel.
- Success, failure, cancelled, and recovered history states.
- Local storage using SwiftData.
- Menu bar operation.
- Login item support.
- English and Simplified Chinese.
- Sparkle-based signed update checks and installation.
- Universal distribution for Intel and Apple Silicon devices capable of running macOS 15.
- Developer ID signing, Hardened Runtime, notarization, stapling, and Gatekeeper validation.

### 3.2 Excluded from 1.0

- Browser profile selection.
- Private or incognito windows.
- Regular expressions.
- AI routing.
- Cloud or device sync.
- Rule import and export.
- Team rules.
- Silent background update installation.
- Time, network, location, or workspace routing.
- Browser extension integration.
- Mac App Store distribution.

## 4. Architecture

### 4.1 Boundary Rules

- SwiftUI presents state and receives user intent. It does not call LaunchServices, `NSWorkspace`, or `SMAppService` directly.
- AppKit receives application events and manages windows. It does not decide routing rules.
- The domain core depends on neither SwiftUI nor AppKit.
- System APIs are hidden behind services that return typed states and errors.
- Window creation, positioning, focus, hiding, and restoration go through one coordinator.
- No equivalent of the current global `App.tsx` state container is allowed.

### 4.2 Layers and Responsibilities

#### Application composition

`PrismApp`

- SwiftUI application entry point.
- Creates the shared dependency container.
- Provides the main scene and menu bar surface.
- Adopts `AppDelegate` through `NSApplicationDelegateAdaptor`.

`AppDelegate`

- Receives cold-start and warm-start URL events.
- Copies Apple Event sender evidence synchronously while the event is current.
- Enqueues URL requests immediately.
- Coordinates application activation and termination.

#### Domain core

`LinkIntakeCoordinator`

- Creates one unique request ID for every received URL.
- Maintains FIFO order.
- Deduplicates by request ID, not by URL value.
- Resumes unfinished requests after application restart.
- Runs one request at a time through rule evaluation and browser launch.

`RuleEngine`

- Pure Swift and deterministic.
- Evaluates enabled URL rules first.
- Evaluates validated source-application rules second.
- Uses visible user order within each rule type.
- Produces a routing decision without launching applications or writing history.

`PrivacySanitizer`

- Removes fragments from persisted history URLs.
- Removes known sensitive query parameters.
- Preserves the complete URL only in the temporary recovery queue.

#### macOS services

`SourceAttributionProvider`

- Reads Apple Event sender PID synchronously.
- Resolves PID to `NSRunningApplication` and bundle identity.
- May use the last activated application only as labelled fallback evidence.
- Returns source identity plus confidence.
- Returns Unknown rather than choosing an arbitrary visible application.

`BrowserCatalog`

- Uses `NSWorkspace.urlsForApplications(toOpen:)` to find applications capable of opening HTTPS URLs.
- Resolves bundle ID, display name, application URL, availability, and native icon.
- Merges user-added custom applications.
- Does not persist icon images.

`BrowserLauncher`

- Uses `NSWorkspace.open(_:withApplicationAt:configuration:)`.
- Returns an explicit success or typed failure.
- Does not hide windows or write history.

`DefaultBrowserService`

- Queries HTTP and HTTPS handlers separately.
- Changes handlers only after explicit user action.
- Never changes the default browser during normal application startup.

`LoginItemService`

- Uses `SMAppService.mainApp`.
- Exposes not registered, enabled, and requires approval states.

`UpdateService`

- Wraps Sparkle 2.
- Uses a signed appcast and EdDSA update signatures.
- Reports checking, current, available, downloading, ready, and failed states.
- Never replaces a working application with an unverified update.

#### Window and menu control

`WindowCoordinator`

- Owns the main window and selector panel.
- Positions the selector inside the visible frame of the screen containing the pointer.
- Restores the main window to History, Rules, Browsers, or Settings.

`SelectorPanelController`

- Owns a separate borderless `NSPanel` hosting SwiftUI content.
- Maintains keyboard focus.
- Binds to exactly one active `LinkRequest`.
- Returns selection, cancellation, retry, or recovery intent to the coordinator.

`StatusItemController`

- Opens the main window.
- Opens History, Rules, Browsers, or Settings.
- Pauses and resumes automatic rules while keeping link selection active.
- Checks for updates.
- Quits Prism.

### 4.3 Data Flow

1. macOS delivers an HTTP or HTTPS URL.
2. `AppDelegate` copies the sender PID evidence and passes the URL to `LinkIntakeCoordinator`.
3. The coordinator creates a unique ID and writes the request to the temporary recovery queue.
4. `RuleEngine` evaluates URL rules in visible order.
5. If none match, it evaluates eligible source rules in visible order.
6. If no automatic decision exists, the default unmatched behavior shows the browser selector.
7. The user selects a browser, cancels, or creates an explicit rule.
8. `BrowserLauncher` asks macOS to open the URL in the selected application.
9. On success, History is updated to successful and the temporary full URL is deleted.
10. On failure, the current request remains recoverable and the selector offers retry or another browser.
11. The queue advances only when the current request succeeds or the user cancels it.

## 5. Data Model

### 5.1 BrowserDescriptor

- Stable ID based on bundle identifier when available.
- Bundle identifier.
- Display name.
- Application URL or security-scoped bookmark for a custom application.
- System or custom source.
- Availability state.
- Selector order.

Browser icons are loaded dynamically from macOS and are never persisted as Base64 data.

### 5.2 RoutingRule

- UUID.
- Enabled state.
- Rule type.
- Matcher.
- Target browser reference.
- User-visible priority.
- Creation and modification timestamps.
- Optional user label.
- Validation state.

Supported matchers:

- Exact host.
- Host and subdomains.
- Full URL contains text.
- Validated source bundle identifier.

URL rules always precede source rules. Within a type, the first visible enabled match wins.

### 5.3 LinkRequest

- UUID.
- Complete URL.
- Received time.
- Source identity, if known.
- Source confidence.
- Queue position.
- Current processing state.
- Launch attempt details.

The complete URL is stored only while recovery is still possible. It is removed from temporary storage after success or explicit cancellation.

### 5.4 HistoryEntry

- UUID.
- Sanitized URL or no URL when history URL storage is disabled.
- Source bundle ID and source name snapshot.
- Target bundle ID and target name snapshot.
- Method: URL rule, source rule, manual, preferred browser, or last used.
- Result: processing, success, failure, or cancelled.
- Matching rule reference when applicable.
- Failure reason when applicable.
- Attempt count.
- Created and completed timestamps.

Retries update the same history entry. They do not create duplicate rows.

History defaults to the earlier of 100 entries or 30 days. Users can disable history, delete an entry, or clear all history.

### 5.5 AppSettings

- Language.
- History enabled.
- History retention.
- Unmatched link behavior.
- Preferred browser, when required by a non-default option.
- Show menu bar item.
- Automatically check for updates.
- Onboarding completion.
- Data schema version.

Default handler, login item, installed browser, and application version states are queried from the system and not duplicated as preference values.

## 6. Rules and Routing Semantics

### 6.1 Priority

1. Enabled URL rules in visible order.
2. Enabled, eligible source rules in visible order.
3. User-selected unmatched behavior.

The first native release defaults unmatched links to Always Ask. Users may later choose Preferred Browser or Last Used Browser in Settings.

### 6.2 URL Matchers

`Exact host`

- `github.com` matches only `github.com`.
- It does not match `notgithub.com` or a query value containing the text.

`Host and subdomains`

- `company.com` matches `company.com`, `docs.company.com`, and deeper subdomains.
- It does not match `othercompany.com`.

`Full URL contains`

- Matches against a normalized absolute URL string.
- The rule editor states that this is text containment, not a regular expression.

### 6.3 Source Rules

- Source rules use stable bundle identity, not display-name similarity.
- A source rule is offered only when the current source has validated high confidence.
- Unknown or low-confidence sources never trigger source rules.
- Applications may become eligible only after passing the source validation matrix.

### 6.4 Invalid Target

- The rule remains visible and is marked Target unavailable.
- Automatic routing does not substitute another browser.
- The selector opens for the affected URL.
- Restoring the browser restores the rule without recreating it.

## 7. User Experience

### 7.1 Visual Direction

Native Clarity is the approved direction:

- System typography and semantic macOS colors.
- Restrained light surfaces and clear state colors.
- No dark command-center dashboard.
- No large decorative glass or gradient treatment.
- Native focus, hover, keyboard, VoiceOver, increased contrast, and reduced-motion behavior.
- Brand accent is applied selectively without replacing system meaning.

### 7.2 Information Architecture

The main window has four top-level destinations:

1. History.
2. Rules.
3. Browsers.
4. Settings.

Browsers are a first-level destination because availability, order, shortcuts, custom applications, and rule references are core product concepts rather than incidental settings.

### 7.3 Onboarding

Step 1: Welcome

- Explain that Prism directs links to the appropriate browser.
- Explain that rules and history stay on the Mac.

Step 2: Link handling

- Show HTTP and HTTPS status separately.
- Ask the user to set Prism as the handler.
- Confirm actual system state before showing success.
- Provide a System Settings recovery route if macOS does not accept the change.

Step 3: Browsers

- Discover available browsers.
- Require at least one usable browser.
- Allow rescanning and adding a custom browser.
- Let the user set browser order.

Step 4: Test

- Confirm the default unmatched behavior is Always Ask.
- Route a test URL through the real selector and browser launch flow.
- Complete onboarding only after the test succeeds or the user explicitly chooses to finish later.

### 7.4 Main Window

History

- Shows source, target, method, result, time, and sanitized URL.
- Allows reopening, copying, creating a rule, deleting, and clearing.
- Empty state explains when entries appear and offers Test Link.

Rules

- Separates URL and Source sections.
- Supports create, edit, enable, disable, delete, reorder, search, and test.
- Displays explicit priority.
- Shows invalid targets and blocked source eligibility.
- Search-empty and rules-empty states are distinct.

Browsers

- Separates detected, custom, and currently unavailable but referenced browsers.
- Shows name, icon, location, availability, selector order, shortcut, and rule count.
- Supports rescan, add custom application, reorder, and remove custom application.

Settings

- HTTP and HTTPS handler status.
- Explicit Set as Default action.
- Unmatched link behavior.
- Preferred browser when that option is selected.
- Login item status including Requires approval.
- Language.
- Menu bar visibility.
- History and privacy settings.
- Update settings and current version.

### 7.5 Menu Bar

- Open Prism.
- Open History, Rules, Browsers, or Settings.
- Pause or resume automatic rules.
- Check for updates.
- Quit Prism.

Pause skips automatic rules but continues to receive links and show the selector. It never silently disables link handling.

### 7.6 Selector Panel

The visual source of truth is:

`https://www.figma.com/design/c1PRx6G3c4z9O9jnerReHW/Prism-App?node-id=4-395&m=dev`

Figma node specifications:

- Content size: 425 × 200 points.
- Outer corner radius: 15 points.
- Drop shadow: black at 25%, y offset 3, blur radius 18.5, spread -3.
- Top row inset: 7 points.
- Source area: 75 × 40, corner radius 10.
- URL area: 248 × 40 in the three-browser composition, corner radius 10.
- Cancel area: 79 × 40, corner radius 10.
- Browser viewport: 412 × 142, corner radius 10.
- Browser icon: 45 × 45 in the original three-column design.
- SF Pro text and semantic system equivalents.
- Keyboard shortcut badges remain part of each browser item.

Dynamic browser layout:

- Up to three browsers: preserve the original three-column composition.
- More than three browsers: use a horizontal scroll view inside the same 412 × 142 viewport.
- The viewport shows three complete browser items and half of the fourth item.
- The partial item is the only required scroll affordance; do not add arrows or a visible scroll bar.
- Trackpad horizontal scrolling, mouse horizontal wheel input, and dragging are supported.
- Left and right arrows move selection and automatically reveal the selected item.
- Enter confirms and Escape or Cancel cancels.
- Number shortcuts follow the complete browser order, not the visible page.
- Selecting a number automatically scrolls the target into view.
- The panel remains 425 × 200 regardless of browser count.
- Browser and source icons come from macOS, not static Figma placeholder images.

The Figma design controls visual composition. Product states such as Unknown source, pending-count status, launch failure, and recovery must be presented without changing the 425 × 200 panel size. Short inline state, tooltips, accessibility descriptions, and the main History screen may carry supporting detail where the fixed panel cannot.

## 8. Error Recovery

### 8.1 Unknown Source

- Display Unknown source.
- Continue evaluating URL rules.
- Skip source rules.
- Never replace Unknown with a guessed visible application.

### 8.2 Missing or Moved Target Browser

- Mark the rule target unavailable.
- Keep the request in the recovery queue.
- Show the selector.
- Offer rescan and browser management.
- Do not record success and do not silently choose another browser.

### 8.3 Browser Launch Failure

- Keep the selector visible.
- Mark the failed browser attempt.
- Offer retry or a different browser.
- Keep one History entry and update its attempt count and result.

### 8.4 No Browsers Found

- Keep the request queued.
- Show Rescan and Open Browser Management actions.
- Do not dismiss the selector as if the link was handled.

### 8.5 User Cancellation

- Mark the existing History entry cancelled.
- Delete the temporary complete URL only after the sanitized history state is stored.
- Allow the user to reopen the cancelled link from History when URL history is enabled.

### 8.6 Application Termination

- Persist active and waiting requests to temporary recovery storage.
- Restore them on next launch.
- Remove each temporary complete URL after success or explicit cancellation.

### 8.7 Corrupt Persistent Data

- Preserve a backup of the damaged store.
- Disable automatic rules.
- Start in safe Always Ask mode.
- Explain that settings could not be loaded and offer retry or reset.
- Never silently erase user rules.

### 8.8 History Write Failure

- Do not block the current browser launch.
- Show a local storage warning.
- Do not claim the History entry was saved.

### 8.9 Default Handler and Login Item Drift

- Show persistent warnings in the main window.
- Never reclaim default status automatically.
- Show Requires approval when `SMAppService` reports it and provide the appropriate System Settings route.

### 8.10 Update Failure

- Retain the current working version.
- Distinguish check, download, signature, and installation failures.
- Offer retry and the official download page.

## 9. Privacy

- No application data is uploaded by Prism.
- History storage can be disabled.
- Persisted URLs remove fragments and known sensitive query parameters.
- Full URLs are temporarily persisted only for recovery and are deleted after success or explicit cancellation.
- Application icons are never duplicated into the data store.
- Old Electron data is neither read nor deleted.

## 10. Source Attribution Release Gate

Validate DingTalk, Lark, WeChat, Slack, Finder, Terminal, and common browsers in cold-start and already-running conditions.

Each source must be tested at least 20 times per required state.

A source application is eligible for source rules only when:

- It is never incorrectly identified as another application.
- At least 95% of attempts provide a confirmed real source.
- All unconfirmed attempts return Unknown.
- The validation is rerun after material macOS changes.

Applications that do not pass still support URL rules and manual selection. Prism must not advertise universal precise source detection.

## 11. Verification and Acceptance

### 11.1 Unit Tests with Swift Testing

- One request ID is processed at most once.
- Concurrent requests preserve FIFO order.
- Restart restores pending requests.
- URL rule priority precedes source rule priority.
- Visible order determines the first matching rule within a type.
- Exact-host matching rejects lookalike hosts.
- Host-and-subdomain matching respects label boundaries.
- Contains matching uses the documented normalized URL behavior.
- Unknown and low-confidence sources cannot match source rules.
- Missing browser targets return manual selection rather than automatic fallback.
- Success, failure, retry, and cancellation update one History entry.
- Privacy sanitization removes fragments and sensitive parameters.
- Retention limits work.
- Corrupt data creates a backup and starts safe mode.

### 11.2 AppKit and System Integration

- Receive URL on cold start.
- Receive URL while running.
- Receive URL when the main window is hidden and menu bar is active.
- Receive URL after login launch.
- Twenty sequential links are each handled once.
- Ten rapid different URLs preserve count and order.
- Discover and launch Safari, Chrome, Arc, Firefox, Edge, and other installed handlers.
- Handle browser removal, movement, and reinstall.
- Verify HTTP and HTTPS default status separately.
- Verify login item registered, not registered, and requires approval.
- Recover unfinished requests after forced termination.

### 11.3 Selector Visual and Interaction Acceptance

- Compare the native selector against Figma node `4:395`.
- Confirm 425 × 200 content size and fixed panel dimensions.
- Confirm radii, borders, colors, shadow, typography, and top-row composition.
- Confirm original three-column layout for up to three browsers.
- Confirm 3.5 visible items and horizontal scrolling for more than three.
- Confirm trackpad, mouse, drag, arrow, number, Enter, Escape, and Cancel inputs.
- Confirm real source and browser icons.
- Verify light, dark, increased contrast, Reduce Motion, keyboard-only, and VoiceOver behavior.

### 11.4 Multi-display Acceptance

- Main display.
- Display to the right.
- Display to the left with negative coordinates.
- Display above the main display.
- Mixed display scales.
- Dock on bottom, left, and right.

The selector must remain inside the pointer display's visible frame.

### 11.5 Release Acceptance

- All automated tests pass.
- Release build has no warnings.
- Universal architecture is verified.
- Developer ID signature is verified.
- Hardened Runtime is verified.
- Notarization succeeds.
- Stapling validates.
- Gatekeeper accepts the downloaded application.
- Fresh install, overwrite install, update failure recovery, uninstall, and reinstall are verified.
- Sparkle appcast, signature, download, installation, and relaunch are verified.
- Release metadata becomes public only after the downloadable artifact is uploaded and validated.

## 12. Development Environment Requirements

The current machine has Swift 6.4, Command Line Tools, and the macOS SDK, but does not have full Xcode or a valid Developer ID signing identity.

Current capability:

- Create and test the independent Swift core with Swift Package Manager.

Blocked until full Xcode is installed:

- Create and archive the production macOS application normally.
- Run XCUITest.
- Execute complete AppKit application and UI verification.

Blocked until Apple Developer credentials and certificates are available:

- Developer ID signing.
- Full login-item distribution verification.
- Notarization and stapling.
- Final Gatekeeper and Sparkle release verification.

## 13. Implementation Order

1. Prove source attribution and record the support matrix.
2. Build and test the pure Swift models, rule engine, privacy sanitizer, request queue, and repositories.
3. Add AppKit URL intake and browser services.
4. Build the fixed-size selector from Figma node `4:395` and validate keyboard and scrolling behavior.
5. Build onboarding and the Native Clarity main window.
6. Add menu bar, login item, default-handler state, persistence recovery, and localization.
7. Add Sparkle and the signed update feed.
8. Complete system, multi-display, accessibility, Universal, signing, notarization, and release verification.

## 14. Success Criteria

The native release is complete only when:

- The core flows behave as specified under cold start, warm start, hidden window, login launch, rapid input, failure, cancellation, and restart.
- No verified test produces a duplicate, lost, overwritten, or falsely successful link.
- Unsupported source attribution always returns Unknown.
- The selector matches the approved Figma node and horizontal scrolling behavior.
- The application passes all test, accessibility, signature, notarization, and Gatekeeper acceptance gates.
- Product documentation describes only capabilities confirmed by these tests.
