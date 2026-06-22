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

import Defaults
import SwiftUI

/// Settings pane for the notch weather feature: master switch, units, data
/// source, air quality, live activity, and location status.
struct WeatherSettings: View {
    @ObservedObject var weather = WeatherManager.shared
    @Default(.enableWeather) var enableWeather
    @Default(.weatherShowsAQI) var weatherShowsAQI
    @Default(.weatherProviderSource) var weatherProviderSource

    var body: some View {
        GeistSettingsPage(title: "Weather", subtitle: "Local conditions in the notch, from Open-Meteo (free) with a wttr.in fallback.") {
            GeistSection {
                GeistToggleRow(
                    title: "Enable weather",
                    description: "Adds a Weather tab and a live activity to the notch. Uses your location.",
                    isOn: $enableWeather,
                    divider: false
                )
            }

            if enableWeather {
                GeistSection(
                    title: "Display",
                    footer: weatherProviderSource.supportsAirQuality ? nil : "Air quality requires the Open-Meteo data source."
                ) {
                    GeistPickerRow(title: "Units", selection: Binding(
                        get: { Defaults[.weatherTemperatureUnit] }, set: { Defaults[.weatherTemperatureUnit] = $0 }
                    )) {
                        ForEach(WeatherTemperatureUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    GeistPickerRow(title: "Data source", selection: Binding(
                        get: { Defaults[.weatherProviderSource] }, set: { Defaults[.weatherProviderSource] = $0 }
                    )) {
                        ForEach(WeatherProviderSource.allCases) { Text($0.displayName).tag($0) }
                    }
                    GeistToggleRow(
                        title: "Show air quality",
                        isOn: $weatherShowsAQI,
                        divider: weatherShowsAQI && weatherProviderSource.supportsAirQuality
                    )
                    if weatherShowsAQI && weatherProviderSource.supportsAirQuality {
                        GeistPickerRow(title: "AQI scale", selection: Binding(
                            get: { Defaults[.weatherAQIScale] }, set: { Defaults[.weatherAQIScale] = $0 }
                        ), divider: false) {
                            ForEach(WeatherAirQualityScale.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                }

                GeistSection(
                    title: "Location",
                    footer: "VibeIsland uses your approximate location to fetch local weather. Without it, a fallback location is used."
                ) {
                    GeistLabeledRow(title: "Location") {
                        if weather.locationDenied {
                            Label("Denied", systemImage: "xmark.circle")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.warning).labelStyle(.titleAndIcon)
                        } else if let name = weather.snapshot?.locationName, !name.isEmpty {
                            Label(name, systemImage: "location.fill")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.body).labelStyle(.titleAndIcon)
                                .lineLimit(1).truncationMode(.tail)
                        } else {
                            Label("OK", systemImage: "checkmark.circle.fill")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.success).labelStyle(.titleAndIcon)
                        }
                    }
                    GeistRow(divider: weather.lastError != nil) {
                        HStack(spacing: Geist.Spacing.xs) {
                            if weather.locationDenied {
                                Button("Open Location Settings…") { weather.openLocationSettings() }
                                    .buttonStyle(.geist)
                            }
                            Button("Refresh now") { Task { await weather.refresh(force: true) } }
                                .buttonStyle(.geist)
                        }
                    }
                    if let error = weather.lastError {
                        GeistRow(divider: false) {
                            Text(error).font(Geist.Typography.caption).foregroundStyle(Geist.Colors.error)
                        }
                    }
                }
            }
        }
    }
}
