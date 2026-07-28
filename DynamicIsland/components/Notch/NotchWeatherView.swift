/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
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

/// Open-notch tab showing current conditions in the shared notch design system:
/// a monochrome hero glyph + temperature, condition/feels-like, a 2×2 mono
/// detail grid (sunrise/humidity/sunset/wind), and a 7-day mono forecast strip.
/// Temperature is the hero; icons stay monochrome so the forecast never turns
/// into confetti (per the redesign handoff, screen #8).
struct NotchWeatherView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var weather = WeatherManager.shared

    var body: some View {
        Group {
            if weather.locationDenied {
                locationPrompt
            } else if let snapshot = weather.snapshot {
                content(snapshot)
            } else {
                loading
            }
        }
        // Uniform tab insets come from the shared tab container in ContentView.
        // The height is taken exactly (`filledContentHeight`) rather than left
        // to the content: sizing to content left the leftover space as one big
        // gap under the forecast card, so the bottom margin no longer matched
        // the top one. Occupying the region lets the forecast card absorb it.
        .frame(
            maxWidth: .infinity,
            minHeight: contentHeight,
            maxHeight: contentHeight,
            alignment: .top
        )
        .onAppear { Task { await weather.refresh(force: false) } }
    }

    private var contentHeight: CGFloat {
        NotchDesign.TabInset.filledContentHeight(headerHeight: max(24, vm.effectiveClosedNotchHeight))
    }

    // MARK: - Content

    private func content(_ snapshot: WeatherSnapshot) -> some View {
        // Two stacked `#141414` cards (current conditions over the forecast),
        // matching the card grammar every other tab uses, with the gap replacing
        // the old hairline separator.
        VStack(alignment: .leading, spacing: 6) {
            current(snapshot)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .notchCard(radius: NotchDesign.Radius.md)
            if !snapshot.daily.isEmpty {
                forecastRow(snapshot)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    // Takes the leftover height so the gap below the card equals
                    // the one above the first card, instead of pooling at the
                    // bottom. The conditions card stays sized to its content.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .notchCard(radius: NotchDesign.Radius.md)
            }
        }
    }

    private func current(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: snapshot.symbolName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .frame(width: 38, height: 38)

            HStack(alignment: .top, spacing: 8) {
                Text(temperatureDisplay(snapshot))
                    .font(NotchDesign.Typography.voice(34, weight: .semibold))
                    .foregroundStyle(Color(nsColor: NSColor(geistHex: "#fafafa")))
                if let temp = snapshot.temperatureInfo,
                   let hi = temp.displayMaximum, let lo = temp.displayMinimum {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("H \(hi)°")
                            .foregroundStyle(NotchDesign.Colors.textSecondary)
                        Text("L \(lo)°")
                            .foregroundStyle(NotchDesign.Colors.textTertiary)
                    }
                    .font(NotchDesign.Typography.mono(11, weight: .medium))
                    .padding(.top, 3)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: NotchDesign.hairlineWidth, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.description)
                    .font(NotchDesign.Typography.voice(14, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                    .lineLimit(1)
                if let feels = snapshot.conditions?.feelsLike {
                    Text("Feels like \(Int(round(feels)))°")
                        .font(NotchDesign.Typography.voice(12))
                        .foregroundStyle(NotchDesign.Colors.textSecondary)
                }
            }

            Spacer(minLength: 8)

            detailGrid(snapshot)
        }
    }

    /// 3×2 mono detail grid: sunrise/humidity/UV on top, sunset/wind/rain below.
    /// Monochrome dim icons — no per-metric color tints (matches the mockup's
    /// ink-only look).
    @ViewBuilder
    private func detailGrid(_ snapshot: WeatherSnapshot) -> some View {
        let cycle = snapshot.sunCycle
        let conditions = snapshot.conditions
        if cycle != nil || conditions != nil {
            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    detailCell(icon: "sunrise", value: cycle?.sunrise.map(sunTime))
                    detailCell(icon: "drop", value: conditions?.humidity.map { "\($0)%" })
                    detailCell(icon: "sun.max", value: conditions?.uvIndex.map { "UV \(Int(round($0)))" })
                }
                GridRow {
                    detailCell(icon: "sunset", value: cycle?.sunset.map(sunTime))
                    detailCell(icon: "wind",
                               value: conditions?.windSpeed.map { "\(Int(round($0))) \(conditions?.windUnit ?? "")" })
                    detailCell(icon: "umbrella", value: conditions?.precipitationProbability.map { "\($0)%" })
                }
            }
        }
    }

    @ViewBuilder
    private func detailCell(icon: String, value: String?) -> some View {
        if let value {
            detailRow(icon: icon, text: value)
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private func forecastRow(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.daily.prefix(7).enumerated()), id: \.element.id) { index, day in
                let isToday = index == 0
                VStack(spacing: 7) {
                    Text(weekdayLabel(day.date, isFirst: isToday))
                        .font(NotchDesign.Typography.mono(11, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(isToday
                            ? Color(nsColor: NSColor(geistHex: "#cfcfcf"))
                            : NotchDesign.Colors.textSecondary)
                    Image(systemName: day.symbolName)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color(nsColor: NSColor(geistHex: "#c9c9c9")))
                        .frame(height: 20)
                    HStack(spacing: 4) {
                        Text(tempLabel(day.high))
                            .foregroundStyle(NotchDesign.Colors.textPrimary)
                        Text(tempLabel(day.low))
                            .foregroundStyle(NotchDesign.Colors.textTertiary)
                    }
                    .font(NotchDesign.Typography.mono(12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(NotchDesign.Typography.mono(11))
                .foregroundStyle(NotchDesign.Colors.textFaint)
                .frame(width: 14)
            Text(text)
                .font(NotchDesign.Typography.mono(12))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
        }
    }

    private var loading: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading weather…")
                .font(NotchDesign.Typography.body)
                .foregroundStyle(NotchDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
            Text("Location access needed")
                .font(NotchDesign.Typography.bodyStrong)
                .foregroundStyle(NotchDesign.Colors.textPrimary)
            Text("Enable Location Services for VibeIsland to show local weather.")
                .font(NotchDesign.Typography.caption)
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Open System Settings") { weather.openLocationSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// "20°C" — built from the raw value + unit so the degree glyph isn't doubled.
    private func temperatureDisplay(_ snapshot: WeatherSnapshot) -> String {
        guard let temp = snapshot.temperatureInfo else { return snapshot.temperatureText }
        return "\(temp.displayCurrent)\(temp.unitSymbol)"
    }

    private func weekdayLabel(_ date: Date, isFirst: Bool) -> String {
        if isFirst { return String(localized: "Today").uppercased() }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date).uppercased()
    }

    private func tempLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(round(value)))°"
    }

    private func sunTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
