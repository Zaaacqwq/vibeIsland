/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Defaults
import OpenIslandCore
import SwiftUI

struct AgentProviderUsagePager: View {
    let summary: AgentUsageSummary?
    let claudeUsage: ClaudeUsageSnapshot?
    let codexUsage: CodexUsageSnapshot?
    let providerQuotas: [AgentUsageProviderID: ProviderQuotaSnapshot]
    var isRefreshing = false
    var onRefresh: () -> Void = {}

    @State private var selectedIndex = 0
    @State private var pageDirection: PageDirection = .forward
    @Default(.agentUsageProviderOrder) private var providerOrder
    @Default(.disabledAgentUsageProviders) private var disabledProviders
    @Default(.agentAntigravityCompactQuotaWindows) private var compactAntigravityQuotaWindows
    @Default(.agentOpenCodeCompactQuotaWindows) private var compactOpenCodeQuotaWindows

    private enum PageDirection {
        case forward
        case backward
    }

    /// The Summary card is always first; the provider cards follow in the
    /// user-configured order (`AgentUsageProviderCatalog`). Claude and Codex
    /// always show (they carry rate-limit rings even with no token data); the
    /// remaining providers appear only when token or quota data exists, so
    /// uninstalled agents don't add empty cards.
    private var cards: [AgentProviderUsageCardModel] {
        var result: [AgentProviderUsageCardModel] = [
            .summary(summary?.total)
        ]

        for id in AgentUsageProviderCatalog.normalizedOrder(providerOrder) {
            guard !disabledProviders.contains(id.rawValue) else { continue }
            switch id {
            case .claude:
                result.append(.claude(tokens: summary?.provider(.claude), quota: claudeUsage))
            case .codex:
                result.append(.codex(tokens: summary?.provider(.codex), quota: codexUsage))
            default:
                let contribution = summary?.provider(id)
                let quota = AgentQuotaPresentation.snapshot(
                    providerID: id,
                    quota: providerQuotas[id],
                    compactAntigravity: compactAntigravityQuotaWindows,
                    compactOpenCode: compactOpenCodeQuotaWindows
                )
                guard contribution?.isEmpty == false || quota?.isEmpty == false else { continue }
                let icon = AgentUsageProviderCatalog.icon(for: id)
                result.append(
                    .tokenOnly(
                        id: id,
                        iconAsset: icon.asset,
                        iconSystemName: icon.system,
                        tokens: contribution,
                        quota: quota
                    )
                )
            }
        }

        return result
    }

    var body: some View {
        let safeIndex = min(selectedIndex, max(cards.count - 1, 0))
        let card = cards[safeIndex]

        ZStack(alignment: .topLeading) {
            AgentProviderUsageCard(model: card, isRefreshing: isRefreshing, onRefresh: onRefresh)
                .id(card.id)
                .transition(pageTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    handleVerticalDelta(value.translation.height, predicted: value.predictedEndTranslation.height)
                }
        )
        .background(
            AgentProviderUsageScrollMonitor { deltaY in
                handleScroll(deltaY)
            }
        )
        .onChange(of: cards.count) { _, count in
            selectedIndex = min(selectedIndex, max(count - 1, 0))
        }
        .animation(.smooth(duration: 0.22), value: selectedIndex)
    }

    private var pageTransition: AnyTransition {
        switch pageDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            )
        }
    }

    private func handleVerticalDelta(_ translation: CGFloat, predicted: CGFloat) {
        let dominant = abs(predicted) > abs(translation) ? predicted : translation
        guard abs(dominant) >= 24 else { return }
        if dominant < 0 {
            move(.forward)
        } else {
            move(.backward)
        }
    }

    private func handleScroll(_ deltaY: CGFloat) {
        guard abs(deltaY) >= 0.5 else { return }
        if deltaY < 0 {
            move(.forward)
        } else {
            move(.backward)
        }
    }

    private func move(_ direction: PageDirection) {
        guard !cards.isEmpty else { return }
        pageDirection = direction
        switch direction {
        case .forward:
            selectedIndex = (selectedIndex + 1) % cards.count
        case .backward:
            selectedIndex = (selectedIndex - 1 + cards.count) % cards.count
        }
    }
}

enum AgentQuotaPresentation {
    static func snapshot(
        providerID: AgentUsageProviderID,
        quota: ProviderQuotaSnapshot?,
        compactAntigravity: Bool,
        compactOpenCode: Bool
    ) -> ProviderQuotaSnapshot? {
        guard let quota else { return nil }
        let displayed = windows(
            providerID: providerID,
            windows: quota.windows,
            compactAntigravity: compactAntigravity,
            compactOpenCode: compactOpenCode
        )
        guard !displayed.isEmpty else { return nil }
        var snapshot = quota
        snapshot.windows = displayed
        return snapshot
    }

    static func windows(
        providerID: AgentUsageProviderID,
        windows: [ProviderQuotaWindow],
        compactAntigravity: Bool,
        compactOpenCode: Bool
    ) -> [ProviderQuotaWindow] {
        switch providerID {
        case .antigravity where compactAntigravity:
            return compactSharedWindows(windows)
        case .opencode where compactOpenCode:
            return windows.compactMap { window in
                switch quotaWindowKind(window) {
                case .short:
                    return relabeled(window, label: "5h")
                case .weekly:
                    return relabeled(window, label: "7d")
                case .monthly, .unknown:
                    return nil
                }
            }
        default:
            return windows
        }
    }

    private static func compactSharedWindows(_ windows: [ProviderQuotaWindow]) -> [ProviderQuotaWindow] {
        [
            mergedWindow(key: "5h", label: "5h", from: windows, matching: .short),
            mergedWindow(key: "7d", label: "7d", from: windows, matching: .weekly),
        ].compactMap { $0 }
    }

    private static func mergedWindow(
        key: String,
        label: String,
        from windows: [ProviderQuotaWindow],
        matching kind: QuotaWindowKind
    ) -> ProviderQuotaWindow? {
        let matches = windows.filter { quotaWindowKind($0) == kind }
        guard !matches.isEmpty else { return nil }
        return ProviderQuotaWindow(
            key: key,
            label: label,
            usedPercentage: matches.map(\.usedPercentage).max() ?? 0,
            resetsAt: matches.compactMap(\.resetsAt).min()
        )
    }

    private static func relabeled(_ window: ProviderQuotaWindow, label: String) -> ProviderQuotaWindow {
        ProviderQuotaWindow(
            key: window.key,
            label: label,
            usedPercentage: window.usedPercentage,
            resetsAt: window.resetsAt
        )
    }

    private static func quotaWindowKind(_ window: ProviderQuotaWindow) -> QuotaWindowKind {
        let text = "\(window.key) \(window.label)".lowercased()
        if text.contains("monthly") || text.contains("30d") {
            return .monthly
        }
        if text.contains("weekly") || text.contains("week") || text.contains("7d") {
            return .weekly
        }
        if text.contains("rolling") || text.contains("5h") || text.contains("five") {
            return .short
        }
        return .unknown
    }

    private enum QuotaWindowKind {
        case short
        case weekly
        case monthly
        case unknown
    }
}

struct AgentProviderUsageCardModel: Identifiable, Equatable {
    let id: AgentUsageProviderID
    let title: String
    let iconAsset: String?
    let iconSystemName: String
    let tokens: ProviderTokenUsageSummary?
    let total: TokenUsageSummary?
    let quotaRows: [QuotaRow]

    struct QuotaRow: Identifiable, Equatable {
        let id: String
        let label: String
        let usedPercentage: Double
        let resetsAt: Date?
    }

    static func summary(_ total: TokenUsageSummary?) -> Self {
        Self(
            id: .summary,
            title: "Summary",
            iconAsset: nil,
            iconSystemName: "sparkles",
            tokens: nil,
            total: total,
            quotaRows: []
        )
    }

    /// A provider that exposes only token/cost totals (no local rate-limit
    /// windows): OpenCode, Gemini, Antigravity, Copilot, Cursor. Rendered like
    /// the Summary card but scoped to one provider's transcripts.
    static func tokenOnly(
        id: AgentUsageProviderID,
        iconAsset: String?,
        iconSystemName: String,
        tokens: ProviderTokenUsageSummary?,
        quota: ProviderQuotaSnapshot? = nil
    ) -> Self {
        Self(
            id: id,
            title: id.displayName,
            iconAsset: iconAsset,
            iconSystemName: iconSystemName,
            tokens: tokens,
            total: nil,
            quotaRows: quota?.windows.map {
                QuotaRow(
                    id: $0.key,
                    label: $0.label,
                    usedPercentage: $0.usedPercentage,
                    resetsAt: $0.resetsAt
                )
            } ?? []
        )
    }

    static func claude(tokens: ProviderTokenUsageSummary?, quota: ClaudeUsageSnapshot?) -> Self {
        var rows: [QuotaRow] = []
        if let five = quota?.fiveHour {
            rows.append(.init(id: "five-hour", label: "5h", usedPercentage: five.usedPercentage, resetsAt: five.resetsAt))
        }
        if let week = quota?.sevenDay {
            rows.append(.init(id: "seven-day", label: "7d", usedPercentage: week.usedPercentage, resetsAt: week.resetsAt))
        }
        return Self(
            id: .claude,
            title: "Claude",
            iconAsset: "claude-icon",
            iconSystemName: "sparkles",
            tokens: tokens,
            total: nil,
            quotaRows: rows
        )
    }

    static func codex(tokens: ProviderTokenUsageSummary?, quota: CodexUsageSnapshot?) -> Self {
        let rows = quota?.windows.map {
            QuotaRow(id: $0.key, label: $0.label, usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt)
        } ?? []
        return Self(
            id: .codex,
            title: "Codex",
            iconAsset: "codex-icon",
            iconSystemName: "terminal",
            tokens: tokens,
            total: nil,
            quotaRows: rows
        )
    }

    var breakdown: TokenBreakdown? {
        if let total { return total.breakdown }
        return tokens?.breakdown
    }

    var costUSD: Double? {
        if let total { return total.costUSD }
        return tokens?.costUSD
    }

    var activeSeconds: TimeInterval? {
        if let total { return total.activeSeconds }
        return tokens?.activeSeconds
    }

    var models: [ModelTokenUsageSummary] {
        tokens?.models ?? []
    }

    var isEmpty: Bool {
        (breakdown?.isEmpty ?? true) && quotaRows.isEmpty
    }
}

private struct AgentProviderUsageCard: View {
    let model: AgentProviderUsageCardModel
    var isRefreshing = false
    var onRefresh: () -> Void = {}

    @State private var refreshRotation = false

    private enum Palette {
        static let input = NotchDesign.Colors.info
        static let output = NotchDesign.Colors.success
        static let reasoning = Color(nsColor: NSColor(geistHex: "#A78BFA"))
        static let cache = Color(nsColor: NSColor(geistHex: "#5FB3B3"))
    }

    private struct Segment: Identifiable {
        var id: String { label }
        let label: String
        let color: Color
        let value: Int
    }

    private var segments: [Segment] {
        guard let breakdown = model.breakdown else { return [] }
        return [
            Segment(label: "In", color: Palette.input, value: breakdown.input),
            Segment(label: "Out", color: Palette.output, value: breakdown.output),
            Segment(label: "Reason", color: Palette.reasoning, value: breakdown.reasoning),
            Segment(label: "Cache", color: Palette.cache, value: breakdown.cacheTokens),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if model.isEmpty {
                emptyState
            } else {
                if model.id == .summary {
                    breakdownBars
                    statTiles
                } else {
                    if !model.quotaRows.isEmpty {
                        quotaSection
                    }
                    statTiles
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            providerIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: notchLocalized(model.title))
                    .font(NotchDesign.Typography.voice(13, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                Text(model.id == .summary
                    ? String(localized: "All providers")
                    : String(localized: "Provider usage"))
                    .font(NotchDesign.Typography.mono(9))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
            }
            Spacer(minLength: 4)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(refreshRotation ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.85).repeatForever(autoreverses: false) : .smooth(duration: 0.15), value: refreshRotation)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isRefreshing ? NotchDesign.Colors.accent : NotchDesign.Colors.textSecondary)
            .disabled(isRefreshing)
            .onAppear { updateRefreshRotation(isRefreshing) }
            .onChange(of: isRefreshing) { _, refreshing in
                updateRefreshRotation(refreshing)
            }
        }
    }

    private func updateRefreshRotation(_ refreshing: Bool) {
        if refreshing {
            refreshRotation = false
            DispatchQueue.main.async {
                refreshRotation = true
            }
        } else {
            refreshRotation = false
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let asset = model.iconAsset {
            // No explicit renderingMode: each imageset's template-rendering-intent
            // decides. Monochrome brand marks (claude/codex/gemini/cursor/
            // antigravity) are `template` and pick up the tint below; two-tone
            // marks (opencode) are `original` and keep their own colors.
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(NotchDesign.Colors.textPrimary)
        } else {
            Image(systemName: model.iconSystemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.accent)
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.quotaRows) { row in
                quotaGauge(row)
            }
        }
    }

    private func quotaGauge(_ row: AgentProviderUsageCardModel.QuotaRow) -> some View {
        let effectivePercentage = Defaults[.debugForceUsageMax] ? 100 : row.usedPercentage
        let fraction = min(max(effectivePercentage / 100, 0), 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: notchLocalized(row.label))
                    .font(NotchDesign.Typography.mono(9, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                Text(Int(effectivePercentage.rounded()) >= 100 ? "MAX" : "\(Int(effectivePercentage.rounded()))%")
                    .font(NotchDesign.Typography.mono(10, weight: .bold))
                    .foregroundStyle(fraction >= 0.8 ? NotchDesign.Colors.warning : NotchDesign.Colors.textPrimary)
                Spacer(minLength: 4)
                if let resets = resetsIn(row.resetsAt) {
                    Text(resets)
                        .font(NotchDesign.Typography.mono(8))
                        .foregroundStyle(NotchDesign.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchDesign.Colors.hairline)
                    Capsule()
                        .fill(fraction >= 0.9 ? NotchDesign.Colors.warning : NotchDesign.Colors.accent)
                        .frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }

    private var statTiles: some View {
        let breakdown = model.breakdown ?? .zero
        return HStack(spacing: 6) {
            statTile("Token", TokenUsageFormat.compactCount(breakdown.nonCacheTokens), NotchDesign.Colors.textPrimary)
            statTile("Cost", TokenUsageFormat.cost(model.costUSD ?? 0), NotchDesign.Colors.success)
            statTile("Active", AppLanguageController.abbreviatedDuration(model.activeSeconds ?? 0), NotchDesign.Colors.info)
            statTile("Cache", TokenUsageFormat.compactCount(breakdown.cacheTokens), Palette.cache)
        }
    }

    private func statTile(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: notchLocalized(label))
                .font(NotchDesign.Typography.mono(6.5))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            // Small fixed size so the longest realistic value (e.g. "119.7M",
            // "1d 20h") fits without truncating, and every tile's number renders
            // at the same size instead of each auto-scaling to its own length.
            Text(value)
                .font(NotchDesign.Typography.mono(9.5, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // Equal share of the row width (all four tiles say maxWidth .infinity) and
        // a fixed compact height so they never stretch or size to their content.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
        .frame(height: 34)
        .background(NotchDesign.Colors.cardFillRaised, in: RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous)
                .strokeBorder(NotchDesign.Colors.hairline, lineWidth: 1)
        }
    }

    private var breakdownBars: some View {
        let breakdown = model.breakdown ?? .zero
        let generationSegments = [
            Segment(label: "In", color: Palette.input, value: breakdown.input),
            Segment(label: "Out", color: Palette.output, value: breakdown.output),
            Segment(label: "Reason", color: Palette.reasoning, value: breakdown.reasoning),
        ]
        let cacheSegments = [
            Segment(label: "Cache R", color: Palette.cache, value: breakdown.cacheRead),
            Segment(label: "Cache W", color: NotchDesign.Colors.warning.opacity(0.85), value: breakdown.cacheWrite),
        ]

        return VStack(alignment: .leading, spacing: 6) {
            summaryBreakdownRow(segments: generationSegments)
            summaryBreakdownRow(segments: cacheSegments)
        }
    }

    private func summaryBreakdownRow(segments: [Segment]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ForEach(segments) { segment in
                    Text(verbatim: notchLocalized(segment.label))
                        .font(NotchDesign.Typography.mono(9, weight: .bold))
                        .foregroundStyle(segment.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 14, alignment: .center)

            stackedBar(segments: segments)
        }
        .frame(height: 22, alignment: .topLeading)
    }

    private func stackedBar(segments: [Segment]) -> some View {
        GeometryReader { geo in
            let visible = segments.filter { $0.value > 0 }
            let gap: CGFloat = 2
            let minWidth: CGFloat = 3
            let totalGap = gap * CGFloat(max(0, visible.count - 1))
            let reserved = totalGap + minWidth * CGFloat(visible.count)
            let flexible = max(0, geo.size.width - reserved)
            let sumValues = Double(visible.reduce(0) { $0 + $1.value })
            HStack(spacing: gap) {
                if sumValues > 0 {
                    ForEach(visible) { segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: minWidth + flexible * CGFloat(Double(segment.value) / sumValues))
                    }
                } else {
                    Capsule().fill(NotchDesign.Colors.hairline)
                }
            }
        }
        .frame(height: 5)
    }

    private func topModelRow(_ topModel: ModelTokenUsageSummary) -> some View {
        HStack(spacing: 5) {
            Text("Top model")
                .font(NotchDesign.Typography.mono(8))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
            Text(topModel.model)
                .font(NotchDesign.Typography.mono(9, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(TokenUsageFormat.compactCount(topModel.breakdown.nonCacheTokens))
                .font(NotchDesign.Typography.mono(9, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.textPrimary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No usage yet")
                .font(NotchDesign.Typography.voice(12, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
            Text(model.id == .summary
                ? String(localized: "Run an agent to populate token usage.")
                : String(
                    format: String(localized: "Run %@ to populate this card."),
                    model.title
                ))
                .font(NotchDesign.Typography.voice(10))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 18)
    }

    private func resetsIn(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.calendar = AppLanguageController.calendar
        guard let duration = formatter.string(from: TimeInterval(seconds)) else { return nil }
        return String(format: String(localized: "in %@"), duration)
    }
}

private struct AgentProviderUsageScrollMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onScroll: (CGFloat) -> Void
        private var monitor: Any?
        private weak var observedView: NSView?
        private var accumulatedDeltaY: CGFloat = 0
        private var hasSwitchedThisGesture = false
        private var lastScrollEventAt: TimeInterval = 0
        private let gestureResetInterval: TimeInterval = 0.55
        private let switchThreshold: CGFloat = 5.5

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            observedView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                switch self.scrollDecision(for: event, view: view) {
                case .ignore:
                    return event
                case .consume:
                    return nil
                case .switchPage(let deltaY):
                    self.onScroll(deltaY)
                    return nil
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            observedView = nil
            resetGestureState()
        }

        private enum ScrollDecision {
            case ignore
            case consume
            case switchPage(CGFloat)
        }

        private func scrollDecision(for event: NSEvent, view: NSView) -> ScrollDecision {
            guard isCursorOverView(view) else { return .ignore }

            let now = event.timestamp
            if event.phase.contains(.began) || now - lastScrollEventAt > gestureResetInterval {
                resetGestureState()
            }
            lastScrollEventAt = now

            let deltaY = event.scrollingDeltaY
            guard abs(deltaY) > abs(event.scrollingDeltaX), abs(deltaY) >= 0.15 else { return .ignore }

            if hasSwitchedThisGesture {
                return .consume
            }

            accumulatedDeltaY += deltaY
            guard abs(accumulatedDeltaY) >= switchThreshold else { return .consume }

            hasSwitchedThisGesture = true
            return .switchPage(accumulatedDeltaY)
        }

        private func resetGestureState() {
            accumulatedDeltaY = 0
            hasSwitchedThisGesture = false
            lastScrollEventAt = 0
        }

        private func isCursorOverView(_ view: NSView) -> Bool {
            guard let window = view.window else { return false }
            let location = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: location)
            let viewPoint = view.convert(windowPoint, from: nil)
            return view.bounds.contains(viewPoint)
        }
    }
}
