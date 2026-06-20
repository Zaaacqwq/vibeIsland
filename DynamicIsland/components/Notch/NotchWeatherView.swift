/*
 * VibeIsland (DynamicIsland)
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

/// Open-notch tab showing current conditions: large icon + temperature,
/// description, location, high/low, air quality and the next sun event.
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear { Task { await weather.refresh(force: false) } }
    }

    // MARK: - Content

    private func content(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 18) {
            // Left: icon + temperature
            VStack(spacing: 4) {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 44))
                Text("\(snapshot.temperatureText)\(snapshot.temperatureInfo?.unitSymbol ?? "")")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            // Right: details
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let location = snapshot.locationName {
                    Label(location, systemImage: "location.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .labelStyle(.titleAndIcon)
                }
                if let temp = snapshot.temperatureInfo, let high = temp.displayMaximum, let low = temp.displayMinimum {
                    detailRow(icon: "thermometer.medium",
                              text: "H:\(high)° L:\(low)°")
                }
                if let aq = snapshot.airQuality {
                    detailRow(icon: "aqi.medium",
                              text: "\(aq.scale.compactLabel) \(aq.index) · \(aq.category.displayName)",
                              tint: aqiColor(aq))
                }
                if let next = nextSunEvent(snapshot.sunCycle) {
                    detailRow(icon: next.isSunrise ? "sunrise.fill" : "sunset.fill",
                              text: next.time)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func nextSunEvent(_ cycle: WeatherSnapshot.SunCycleInfo?) -> (isSunrise: Bool, time: String)? {
        guard let cycle else { return nil }
        let now = Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        if let sunrise = cycle.sunrise, sunrise >= now {
            return (true, formatter.string(from: sunrise))
        }
        if let sunset = cycle.sunset, sunset >= now {
            return (false, formatter.string(from: sunset))
        }
        if let sunrise = cycle.sunrise {
            return (true, formatter.string(from: sunrise))
        }
        return nil
    }
}
