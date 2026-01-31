//
//  CollapsibleSection.swift
//  claude-maestro
//
//  Reusable collapsible section component for sidebar sections
//

import SwiftUI

struct CollapsibleSection<Content: View, HeaderAccessory: View>: View {
    let title: String
    let icon: String?
    let iconColor: Color
    let count: Int?
    let countColor: Color
    @Binding var isExpanded: Bool
    let headerAccessory: () -> HeaderAccessory
    let content: () -> Content

    init(
        title: String,
        icon: String? = nil,
        iconColor: Color = .secondary,
        count: Int? = nil,
        countColor: Color = .accentColor,
        isExpanded: Binding<Bool>,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.count = count
        self.countColor = countColor
        self._isExpanded = isExpanded
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 12)

                        if let icon = icon {
                            Image(systemName: icon)
                                .font(.caption)
                                .foregroundColor(iconColor)
                        }

                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Count badge (always visible even when collapsed)
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(countColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }

                // Header accessory (buttons, etc.)
                headerAccessory()
            }

            // Content (only when expanded)
            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - Convenience initializer without header accessory

extension CollapsibleSection where HeaderAccessory == EmptyView {
    init(
        title: String,
        icon: String? = nil,
        iconColor: Color = .secondary,
        count: Int? = nil,
        countColor: Color = .accentColor,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.count = count
        self.countColor = countColor
        self._isExpanded = isExpanded
        self.headerAccessory = { EmptyView() }
        self.content = content
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        CollapsibleSection(
            title: "Test Section",
            icon: "star.fill",
            iconColor: .yellow,
            count: 5,
            countColor: .purple,
            isExpanded: .constant(true)
        ) {
            HStack {
                Button { } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        } content: {
            VStack {
                Text("Content here")
                Text("More content")
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }

        CollapsibleSection(
            title: "Collapsed Section",
            count: 3,
            isExpanded: .constant(false)
        ) {
            Text("This won't show")
        }
    }
    .padding()
    .frame(width: 250)
}
