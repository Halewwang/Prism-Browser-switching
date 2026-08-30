import AppKit
import PrismCore
import SwiftUI

struct WorkspacePreviewCard<Content: View>: View {
    var accessibilityIdentifier: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: WorkspaceLayout.previewMinHeight, maxHeight: .infinity)
            .background(WorkspacePalette.sceneFill, in: RoundedRectangle(cornerRadius: WorkspaceLayout.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: WorkspaceLayout.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WorkspaceLayout.cardRadius, style: .continuous)
                    .stroke(WorkspacePalette.cardStroke, lineWidth: 1)
            }
            .modifier(WorkspaceOptionalIdentifier(accessibilityIdentifier))
    }
}

struct WorkspaceBrowserIcon: View {
    let browser: BrowserDescriptor
    var size: CGFloat

    var body: some View {
        if let icon = WorkspaceApplicationIcon.nsImage(for: browser) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

struct WorkspaceScaledSelectorPreview: View {
    let browsers: [BrowserDescriptor]
    var selectedID: BrowserID?
    var sourceName: String
    var sourceIcon: NSImage?
    var urlText: String
    var showsShortcuts = true
    var scale: CGFloat = WorkspaceLayout.selectorPreviewScale

    var body: some View {
        let panel = SelectorMetrics.panelSize
        ZStack {
            selectorChrome
                .frame(width: panel.width, height: panel.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: panel.width * scale, height: panel.height * scale)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private var selectorChrome: some View {
        VStack(spacing: 5) {
            header
                .frame(height: SelectorMetrics.headerHeight)
            viewport
                .frame(width: SelectorMetrics.viewportSize.width, height: SelectorMetrics.viewportSize.height)
                .background(SelectorPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: SelectorMetrics.cardRadius))
        }
        .padding(.top, SelectorMetrics.outerInset)
        .padding(.leading, SelectorMetrics.outerInset)
        .padding(.trailing, SelectorMetrics.outerTrailingInset)
        .padding(.bottom, 6)
        .frame(width: SelectorMetrics.panelSize.width, height: SelectorMetrics.panelSize.height)
        .background(SelectorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SelectorMetrics.outerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SelectorMetrics.outerRadius)
                .stroke(SelectorPalette.border, lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: SelectorMetrics.headerGap) {
            sourceField
                .frame(width: SelectorMetrics.sourceWidth)
            urlField
                .frame(maxWidth: .infinity)
            cancelField
                .frame(width: SelectorMetrics.cancelWidth)
        }
    }

    private var sourceField: some View {
        HStack(spacing: 7) {
            if let sourceIcon {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)
            }
            Text(sourceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SelectorPalette.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .selectorPreviewField()
    }

    private var urlField: some View {
        HStack(spacing: 7) {
            Text(urlText)
                .font(.system(size: 12))
                .foregroundStyle(SelectorPalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .selectorPreviewField()
    }

    private var cancelField: some View {
        Text(String(localized: "selector.cancel", defaultValue: "Cancel"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SelectorPalette.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .selectorPreviewField()
    }

    private var viewport: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SelectorMetrics.itemGap(browserCount: max(browsers.count, 1))) {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                    selectorChoice(browser: browser, index: index)
                }
            }
            .padding(.leading, SelectorMetrics.viewportLeadingInset)
            .padding(.trailing, SelectorMetrics.viewportTrailingInset)
        }
    }

    private func selectorChoice(browser: BrowserDescriptor, index: Int) -> some View {
        let width = SelectorMetrics.itemWidth(browserCount: max(browsers.count, 1))
        let selected = browser.id == selectedID || (selectedID == nil && index == 0)
        return VStack(spacing: 0) {
            Spacer(minLength: 18)
            WorkspaceBrowserIcon(browser: browser, size: width == SelectorMetrics.fixedItemWidth
                ? SelectorMetrics.iconSize
                : SelectorMetrics.compactIconSize)
            Text(browser.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SelectorPalette.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 7)
            if showsShortcuts, index < 9 {
                KeyboardShortcutBadge(number: index + 1)
                    .padding(.top, 11)
                    .padding(.bottom, 10)
            } else {
                Spacer(minLength: 30)
            }
        }
        .frame(width: width, height: SelectorMetrics.itemHeight)
        .background(selected ? SelectorPalette.selected : .clear)
        .clipShape(RoundedRectangle(cornerRadius: SelectorMetrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SelectorMetrics.cardRadius)
                .stroke(selected ? SelectorPalette.selectionBorder : Color.clear, lineWidth: 0.5)
        }
    }
}

struct WorkspaceCornerWidgetScene: View {
    var address: String
    var browser: BrowserDescriptor?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            simplifiedWindow
            if let browser {
                productCard(for: browser)
                    .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private var simplifiedWindow: some View {
        VStack(spacing: 0) {
            titlebar
            pageBody
        }
    }

    private var titlebar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.34, blue: 0.32)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.99, green: 0.76, blue: 0.26)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.40)).frame(width: 8, height: 8)
            }
            addressBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.045))
    }

    private var addressBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(address)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(WorkspacePalette.pillFill, in: Capsule())
        .overlay {
            Capsule().stroke(WorkspacePalette.pillStroke, lineWidth: 0.5)
        }
    }

    private var pageBody: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(index == 0 ? 0.12 : 0.06))
                        .frame(width: index == 0 ? 64 : 52, height: 7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .frame(width: 108)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.03))

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 168, height: 11)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(maxWidth: 280)
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(maxWidth: 220)
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(maxWidth: 240)
                    .frame(height: 64)
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspacePalette.pageFill)
    }

    private func productCard(for browser: BrowserDescriptor) -> some View {
        VStack(spacing: 8) {
            WorkspaceBrowserIcon(browser: browser, size: WorkspaceLayout.productIconSize)
            Text(browser.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(WorkspacePalette.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WorkspacePalette.productAccent, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

private extension View {
    func selectorPreviewField() -> some View {
        background(SelectorPalette.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SelectorPalette.border, lineWidth: 0.5)
            }
    }
}

struct WorkspaceOptionalIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
