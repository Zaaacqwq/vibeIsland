/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults
import AtollExtensionKit

struct ExtensionsSettingsView: View {
    @ObservedObject private var authManager = ExtensionAuthorizationManager.shared
    @State private var searchText = ""
    @State private var selectedEntry: ExtensionAuthorizationEntry?
    @State private var showingRemoveConfirmation = false
    
    private var filteredEntries: [ExtensionAuthorizationEntry] {
        guard !searchText.isEmpty else { return authManager.entries }
        let query = searchText.lowercased()
        return authManager.entries.filter {
            $0.bundleIdentifier.lowercased().contains(query) ||
            $0.appName.lowercased().contains(query)
        }
    }

    private var globalFooter: String {
        Defaults[.enableThirdPartyExtensions]
        ? "Third-party apps using AtollExtensionKit can display live activities and dedicated notch experiences. Toggle features above or manage individual app permissions below."
        : "Enable extensions to allow third-party apps to display live activities and notch experiences in VibeIsland."
    }

    private var permissionsHeader: String {
        authManager.entries.isEmpty
        ? "App Permissions"
        : "App Permissions (\(authManager.entries.count) \(authManager.entries.count == 1 ? "app" : "apps"))"
    }

    var body: some View {
        GeistSettingsPage(title: "Extensions") {
            globalTogglesSection
            if authManager.isExtensionsFeatureEnabled {
                authorizedAppsSection
            }
        }
        .alert("Remove Extension", isPresented: $showingRemoveConfirmation, presenting: selectedEntry) { entry in
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                authManager.removeEntry(bundleIdentifier: entry.bundleIdentifier)
                selectedEntry = nil
            }
        } message: { entry in
            Text("Remove \(entry.appName) from the authorized extensions list? This will dismiss all active live activities and notch experiences from this app.")
        }
    }

    private var globalTogglesSection: some View {
        GeistSection(title: "Global Settings", footer: globalFooter) {
            GeistToggleRow(title: String(localized: "Enable third-party extensions"), isOn: geistBinding(.enableThirdPartyExtensions), divider: Defaults[.enableThirdPartyExtensions])
            if Defaults[.enableThirdPartyExtensions] {
                GeistToggleRow(title: String(localized: "Allow extension live activities"), isOn: geistBinding(.enableExtensionLiveActivities))
                GeistToggleRow(title: String(localized: "Allow extension notch experiences"), isOn: geistBinding(.enableExtensionNotchExperiences))
                if Defaults[.enableExtensionNotchExperiences] {
                    GeistToggleRow(title: String(localized: "Show extension tabs"), isOn: geistBinding(.enableExtensionNotchTabs))
                    GeistToggleRow(title: String(localized: "Allow minimalistic overrides"), isOn: geistBinding(.enableExtensionNotchMinimalisticOverrides))
                    GeistToggleRow(title: String(localized: "Allow interactive web content"), isOn: geistBinding(.enableExtensionNotchInteractiveWebViews))
                }
                GeistToggleRow(title: String(localized: "Enable extension diagnostics logging"), isOn: geistBinding(.extensionDiagnosticsLoggingEnabled), divider: false)
            }
        }
    }

    @ViewBuilder
    private var authorizedAppsSection: some View {
        GeistSection(title: permissionsHeader) {
            if authManager.entries.isEmpty {
                GeistRow(divider: false) {
                    VStack(alignment: .center, spacing: Geist.Spacing.sm) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 48))
                            .foregroundStyle(Geist.Colors.mute.opacity(0.6))
                        Text("No extensions yet")
                            .font(Geist.Typography.bodyStrong)
                            .foregroundStyle(Geist.Colors.body)
                        Text("Apps using AtollExtensionKit will appear here once they request permission")
                            .font(Geist.Typography.caption)
                            .foregroundStyle(Geist.Colors.mute)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Geist.Spacing.lg)
                }
            } else {
                if authManager.entries.count > 3 {
                    GeistRow {
                        TextField("Search extensions...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                let entries = filteredEntries
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    GeistRow(divider: index < entries.count - 1) {
                        ExtensionEntryRow(entry: entry, onRemove: {
                            selectedEntry = entry
                            showingRemoveConfirmation = true
                        })
                    }
                }
            }
        }

        if !authManager.entries.isEmpty {
            VStack(alignment: .leading, spacing: Geist.Spacing.xxs) {
                Text("Permission States:")
                    .font(Geist.Typography.captionStrong)
                    .foregroundStyle(Geist.Colors.mute)
                HStack(spacing: Geist.Spacing.md) {
                    Label("Authorized", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Geist.Colors.success)
                    Label("Pending", systemImage: "clock.fill")
                        .foregroundStyle(.orange)
                    Label("Denied/Revoked", systemImage: "xmark.circle.fill")
                        .foregroundStyle(Geist.Colors.error)
                }
                .font(Geist.Typography.caption)
            }
            .padding(.leading, Geist.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
private struct ExtensionEntryRow: View {
    @ObservedObject private var authManager = ExtensionAuthorizationManager.shared
    @ObservedObject private var liveActivityManager = ExtensionLiveActivityManager.shared
    @ObservedObject private var notchExperienceManager = ExtensionNotchExperienceManager.shared
    let entry: ExtensionAuthorizationEntry
    let onRemove: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Status indicator
                statusIndicator
                
                // App info
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.appName)
                        .font(.system(size: 13, weight: .medium))
                    Text(entry.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Expand button
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded details
            if isExpanded {
                expandedDetails
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 32, height: 32)
            
            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
        }
    }
    
    private var statusColor: Color {
        switch entry.status {
        case .authorized: return .green
        case .pending: return .orange
        case .denied, .revoked: return .red
        }
    }
    
    private var statusIcon: String {
        switch entry.status {
        case .authorized: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .denied, .revoked: return "xmark.circle.fill"
        }
    }
    
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Status info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Status:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.status.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())
                }
                
                if let grantedAt = entry.grantedAt {
                    infoRow(label: "Granted", value: formatDate(grantedAt))
                }
                
                if let lastActivity = entry.lastActivityAt {
                    infoRow(label: "Last Activity", value: formatDate(lastActivity))
                }
                
                if let deniedReason = entry.lastDeniedReason {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last Denied Reason:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(deniedReason)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
            }
            
            Divider()
            
            // Scopes section
            if entry.status == .authorized {
                scopeToggles
                Divider()
            }
            
            // Rate limits info
                if let rateLimitRecord = authManager.rateLimitRecords.first(where: { $0.bundleIdentifier == entry.bundleIdentifier }),
                    !rateLimitRecord.activityTimestamps.isEmpty || !rateLimitRecord.notchExperienceTimestamps.isEmpty {
                rateLimitInfo(record: rateLimitRecord)
                Divider()
            }
            
            // Actions
            actionButtons
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private var scopeToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allowed Features")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Toggle("Live Activities", isOn: Binding(
                get: { entry.allowedScopes.contains(.liveActivities) },
                set: { enabled in
                    var newScopes = entry.allowedScopes
                    if enabled {
                        newScopes.insert(.liveActivities)
                    } else {
                        newScopes.remove(.liveActivities)
                    }
                    authManager.updateAllowedScopes(bundleIdentifier: entry.bundleIdentifier, allowedScopes: newScopes)
                }
            ))
            .font(.caption)
            .disabled(!authManager.areLiveActivitiesEnabled)
            
            Toggle("Notch Experiences", isOn: Binding(
                get: { entry.allowedScopes.contains(.notchExperiences) },
                set: { enabled in
                    var newScopes = entry.allowedScopes
                    if enabled {
                        newScopes.insert(.notchExperiences)
                    } else {
                        newScopes.remove(.notchExperiences)
                    }
                    authManager.updateAllowedScopes(bundleIdentifier: entry.bundleIdentifier, allowedScopes: newScopes)
                }
            ))
            .font(.caption)
            .disabled(!authManager.areNotchExperiencesEnabled)
        }
    }
    
    private func rateLimitInfo(record: ExtensionRateLimitRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity (last 5 minutes)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                if !record.activityTimestamps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Activities")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(record.activityTimestamps.count)")
                            .font(.caption.monospacedDigit())
                    }
                }
                
                if !record.notchExperienceTimestamps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notch Experiences")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(record.notchExperienceTimestamps.count)")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            
            Button("Reset Rate Limits") {
                authManager.resetRateLimits(for: entry.bundleIdentifier)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch entry.status {
            case .pending:
                Button("Authorize") {
                    authManager.authorize(bundleIdentifier: entry.bundleIdentifier, appName: entry.appName)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Deny") {
                    authManager.deny(bundleIdentifier: entry.bundleIdentifier, reason: "Denied by user")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
            case .authorized:
                Button("Revoke Access") {
                    authManager.revoke(bundleIdentifier: entry.bundleIdentifier, reason: "Revoked by user")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                
            case .denied, .revoked:
                Button("Re-authorize") {
                    authManager.authorize(bundleIdentifier: entry.bundleIdentifier, appName: entry.appName)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Spacer()
            
            resetMenu

            Button("Remove") {
                onRemove()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
    }

    private var resetMenu: some View {
        Menu {
            Button("Reset Live Activities") {
                liveActivityManager.dismissAll(for: entry.bundleIdentifier)
            }
            .disabled(!hasLiveActivities)

            Button("Reset Notch Experiences") {
                notchExperienceManager.dismissAll(for: entry.bundleIdentifier)
            }
            .disabled(!hasNotchExperiences)
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise.circle")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }

    private var hasLiveActivities: Bool {
        liveActivityManager.activeActivities.contains { $0.bundleIdentifier == entry.bundleIdentifier }
    }

    private var hasNotchExperiences: Bool {
        notchExperienceManager.activeExperiences.contains { $0.bundleIdentifier == entry.bundleIdentifier }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    ExtensionsSettingsView()
}
