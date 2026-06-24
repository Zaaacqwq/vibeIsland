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
import Defaults

/// Open-notch tab showing current conditions: large icon + temperature,
/// description, location, high/low, air quality, sun cycle and (optionally)
/// extra detail metrics.
struct NotchWeatherView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var weather = WeatherManager.shared
    @Default(.weatherShowsDetails) private var showsDetails

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear { Task { await weather.refresh(force: false) } }
    }

    // MARK: - Content

    private func content(_ snapshot: WeatherSnapshot) -> some View {
        VStack(spacing: 8) {
            current(snapshot)
            if !snapshot.daily.isEmpty {
                Divider().overlay(Color.white.opacity(0.12))
                forecastRow(snapshot)
            }
        }
    }

    private func current(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: snapshot.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 28))
                    Text(temperatureDisplay(snapshot))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if let temp = snapshot.temperatureInfo,
                       let hi = temp.displayMaximum, let lo = temp.displayMinimum {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("H:\(hi)°").font(.system(size: 9, weight: .medium))
                            Text("L:\(lo)°").font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                if showsDetails, let feels = snapshot.conditions?.feelsLike {
                    Text("Feels like \(Int(round(feels)))°")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let location = snapshot.locationName {
                    Label(location, systemImage: "location.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                if let aq = snapshot.airQuality {
                    detailRow(icon: "aqi.medium",
                              text: "\(aq.scale.compactLabel) \(aq.index) · \(aq.category.displayName)",
                              tint: aqiColor(aq))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            detailsColumn(snapshot)
        }
    }

    /// Right side: sunrise/sunset, plus humidity/wind/UV/rain when "Show weather
    /// details" is on. Capped at two rows so the row height (and the notch's
    /// rounded bottom corners) match the other tabs.
    @ViewBuilder
    private func detailsColumn(_ snapshot: WeatherSnapshot) -> some View {
        let cycle = snapshot.sunCycle
        let conditions = showsDetails ? snapshot.conditions : nil
        if cycle != nil || conditions != nil {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let sunrise = cycle?.sunrise {
                        detailRow(icon: "sunrise.fill", text: sunTime(sunrise), tint: .orange)
                    }
                    if let sunset = cycle?.sunset {
                        detailRow(icon: "sunset.fill", text: sunTime(sunset), tint: Color(red: 1.0, green: 0.55, blue: 0.3))
                    }
                }
                if let c = conditions {
                    VStack(alignment: .leading, spacing: 3) {
                        if let humidity = c.humidity {
                            detailRow(icon: "humidity.fill", text: "\(humidity)%", tint: .cyan)
                        }
                        if let wind = c.windSpeed {
                            detailRow(icon: "wind", text: "\(Int(round(wind))) \(c.windUnit)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if let uv = c.uvIndex {
                            detailRow(icon: "sun.max.fill", text: "UV \(Int(round(uv)))", tint: .yellow)
                        }
                        if let pop = c.precipitationProbability {
                            detailRow(icon: "umbrella.fill", text: "\(pop)%", tint: .blue)
                        }
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func forecastRow(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.daily.prefix(7).enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 4) {
                    Text(weekdayLabel(day.date, isFirst: index == 0))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: day.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                        .frame(height: 18)
                    Text(tempLabel(day.high))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(tempLabel(day.low))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func detailRow(icon: String, text: String, tint: Color = .white.opacity(0.7)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var loading: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading weather…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var locationPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("Location access needed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Text("Enable Location Services for VibeIsland to show local weather.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open System Settings") { weather.openLocationSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    // MARK: - Helpers

    /// "20°C" — built from the raw value + unit so the degree glyph isn't doubled.
    private func temperatureDisplay(_ snapshot: WeatherSnapshot) -> String {
        guard let temp = snapshot.temperatureInfo else { return snapshot.temperatureText }
        return "\(temp.displayCurrent)\(temp.unitSymbol)"
    }

    private func weekdayLabel(_ date: Date, isFirst: Bool) -> String {
        if isFirst { return String(localized: "Today") }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func tempLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(round(value)))°"
    }

    private func aqiColor(_ aq: WeatherSnapshot.AirQualityInfo) -> Color {
        switch aq.category {
        case .good, .fair: return .green
        case .moderate: return .yellow
        case .unhealthyForSensitive, .poor: return .orange
        case .unhealthy, .veryPoor, .veryUnhealthy: return .red
        case .extremelyPoor, .hazardous: return .purple
        case .unknown: return .gray
        }
    }

    private func sunTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
