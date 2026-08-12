# Selector visual validation

## Reference

- Figma file: `c1PRx6G3c4z9O9jnerReHW`
- Node: `4:395`
- Preserved full reference: `.superpowers/sdd/2026-08-12-prism-native-macos-implementation/task-11-figma-4-395.png`
- Reference SHA-256: `21315ed2b06cc867da4bf15e99ac268f8779f122c78349a1ed5b79d3d0815033`
- The full 456 × 231 PNG contains the rendered shadow. Geometry comparison uses the 425 × 200 content crop `[15:440, 12:212]`.

## Normal three-browser comparison

| Element | Figma | Native implementation | Deviation |
| --- | ---: | ---: | ---: |
| Panel content | 425 × 200 | 425 × 200 | 0 |
| Root radius | 15 | 15 | 0 |
| Header origin / height | x 7, y 7 / 40 | x 7, y 7 / 40 | 0 |
| Source field | 75 × 40 | 75 × 40 | 0 |
| Header gaps | 5 | 5 | 0 |
| URL field | 248 × 40 | flexible result 248 × 40 | 0 |
| Cancel field | 79 × 40 | 79 × 40 | 0 |
| Browser viewport | x 7, y 52, 412 × 142 | x 7, y 52, 412 × 142 | 0 |
| Viewport/card radius | 10 | 10 | 0 |
| Cards | 130 × 130 | 130 × 130 | 0 |
| Card gap / insets | 5 / 6 + 6 | 5 / 6 + 6 | 0 |
| Card centers, viewport-relative | 71, 206, 341 | 71, 206, 341 | 0 |
| Browser icons | 45 × 45 | 45 × 45 | 0 |
| Label | SF Pro Semibold 12 | system Semibold 12 | 0 |
| Shortcut badge | 20 × 20, r 5, 0.5 border | 20 × 20, r 5, 0.5 border | 0 |

## Five-browser scrolling comparison

Five browsers are the user-confirmed geometry extension; node `4:395` itself contains the three-browser state.

| Element | Confirmed rule | Native implementation | Deviation |
| --- | ---: | ---: | ---: |
| Scrolling card width | `(412 - 6 - 3 × 8) / 3.5` = 109.142857 | 109.142857 | < 0.000001 |
| Gap | 8 | 8 | 0 |
| Leading/trailing inset | 6 / 6 | 6 / 6 | 0 |
| Initial reveal | 3 full + 1/2 fourth | 3 full + 1/2 fourth | 0 |
| Final reveal | final card fully visible | clamped final offset | 0 |

The narrow scrolling cards use 40-point live application icons so the label and shortcut remain legible without changing the confirmed card geometry. This is the only intentional browser-card size adjustment from the normal three-browser node.

## Color, contrast, motion, and assets

- Aqua preserves the Figma values: neutral field `#F8F8F8`, selected card `#EEEEEE`, and normal/selection border `#E1E1E1`.
- Dark Aqua resolves every selector role independently: surface, field, selected card, borders, primary/secondary text, shortcut badges, pending badge, and error state. The panel and its existing hosting view repaint when the effective system appearance changes; production does not force either appearance.
- Small text and badges meet a minimum 4.5:1 computed contrast ratio in Aqua and Dark Aqua. Error and high-contrast borders meet at least 3:1. The selected Dark Aqua card keeps a distinct non-text border in addition to its accessibility selected state.
- The window uses the native `NSPanel` shadow. SwiftUI adds no second shadow; this intentionally differs from Figma's painted black 25%, y 3, blur 18.5, spread -3 shadow.
- Browser and confirmed source icons come from `NSWorkspace`. Figma's sample Chrome and Lark raster assets are not shipped.
- Increased Contrast raises the border from 0.5 to 1 point and uses a stronger appearance-aware border without moving geometry.
- Reduce Motion removes animated programmatic reveal while preserving the same final offset and direct scroll input.
- Selected and failed states also expose text/traits/icons, so color is not the only signal.
- Reduce Transparency does not change this selector because it uses opaque surfaces rather than material or translucent backgrounds.

## Reproduction and captures

The DEBUG-only selector harness accepts `--ui-testing --selector-harness <variant> --selector-appearance <light|dark>`. Variants cover `three`, `five`, `failed`, `empty`, and `recovery`; all use synthetic URLs, browser descriptors, and non-branded generated icons. It never launches a browser, reads a personal URL, restores the production queue, or changes the default handler.

The harness captures the existing 425 × 200 `SelectorPanel` content view directly after SwiftUI layout. This deliberately avoids system-wide screen capture so macOS privacy overlays or the desktop cannot contaminate the evidence. Every capture is written to a unique `/tmp/prism-selector-*` path, deleted before launch and after the test, size-checked, inspected for visible structure, and attached to the test result.

Fresh selector UI verification completed 8/8 tests with no failures. The saved evidence is:

- `selector-three`: Aqua three-browser Figma geometry.
- `selector-five`: Aqua initial 3 full + 1/2 fourth browser geometry.
- `selector-three-dark`: Dark Aqua normal state.
- `selector-failed-dark`: Dark Aqua launch-failure state.
- `selector-empty-dark`: Dark Aqua no-browser state.
- `selector-recovery-dark`: Dark Aqua outcome-unknown recovery state.

The same UI run also verified the browser context-menu item by its real AppKit accessibility element, plus keyboard reveal, card drag without activation, horizontal swipe, Escape, and Cancel. Context-menu appearance is not claimed as a saved bitmap because the menu is outside the panel content view.

Earlier screen-wide attachments affected by the macOS privacy overlay were rejected and are not evidence for this validation.

Physical trackpad, mouse, VoiceOver, Increased Contrast, Differentiate Without Color, and multi-display acceptance remain part of Task 18. Task 11 verifies the corresponding implementation branches, computed color contrast, deterministic input geometry, and the normal selected-state accessibility trait; it does not claim real-mode rendering or assistive-technology acceptance for the deferred system settings.
