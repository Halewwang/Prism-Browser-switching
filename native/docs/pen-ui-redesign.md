# Pen UI implementation

The management interface follows the approved Pen document at
`/Users/adler/.pencil/documents/61f6641f-e47d-4d76-877e-d82a12ec5b44/pencil-new.pen`.

- The native SwiftUI application is the implementation target. The existing browser selector remains unchanged.
- The shell uses a 218-point sidebar, 36-point content insets, 27-point page titles, neutral surfaces, and actual app icons. Light and dark appearances are supported.
- History offers search over safe URLs, sources, and browsers; result filtering; chronological date groups; and a scrollable detail sheet. Existing recovery and privacy safeguards remain enforced.
- Rules retain their ordering and persistence behavior. Group headers explain precedence; menus expose priority, edit, and delete actions. The editor supports application search and preserves the draft when saving fails.
- Settings group link handling, general preferences, history and privacy, and software updates. Browser management uses the existing catalog and custom-browser repository, including unavailable saved paths. About and version information use the running app's metadata.
- Onboarding follows the individual 668 × 554 Pen windows with 28-point padding, a compact step number, left-aligned content, and a 37-point footer. Entering the management shell expands the window to 1120 × 800. Completion remains dependent on the actual browser handoff.
- Management pages share 37-point buttons, 36-point inputs and dropdowns, and compact 34 × 18 switches. Dropdowns expose their selected value to accessibility; switches retain native Toggle semantics through accessibility representation.

Native dialogs continue to handle deletion, clearing, language restarts, and update results. Browser management removal deletes only the saved custom entry, never the application.

Validation includes the native unit suite and UI flows for history, rules, settings, and onboarding. UI-test products are copied without extended attributes to a temporary directory and signed ad hoc before execution, because generated app bundles in the workspace can inherit Finder metadata that prevents signing.

Verified on 2026-09-29: 384 unit tests passed, and all 17 distinct management/onboarding UI cases passed across the full run and targeted reruns. Coverage includes light/dark appearances, the exact onboarding window dimensions, Chinese layouts, keyboard dropdown selection, real setting updates, rule-editor cancellation, safe History details, and queue-owned recovery actions. Universal Release builds include arm64 and x86_64.

The History action fixture uses a deferred presentation relay so automatic selector restoration cannot cancel its seeded failed request. Production routing remains connected to the real selector. History rows use a separate details button beside their action menu, and the detail sheet contains its accessibility children to preserve individual button identifiers.

The subsequent interface review improves secondary-text contrast, search/input/picker focus and keyboard behavior, English filter labels, longer rule-editor forms, settings action-row hit areas, Chinese onboarding error copy, and accessible action context. After these changes, 384 unit tests and 10 distinct related UI interaction cases passed across targeted runs. Native XCTest screenshot metrics were not run in this pass because its image API failed in the current multi-display/screen-sharing environment; rendered pages were checked through direct computer-use screenshots instead. See `interface-review-2026-09-29.md` for the findings and verification limits. The earlier 17-case UI total above predates these subsequent changes.
