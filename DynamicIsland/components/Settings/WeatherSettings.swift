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
        Form {
            Section {
                Defaults.Toggle(key: .enableWeather) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable weather")
                        Text("Adds a Weather tab and a live activity to the notch. Uses your location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if enableWeather {
                    Defaults.Toggle(key: .showWeatherLiveActivity) {
                        Text("Show temperature in the notch (live activity)")
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Weather data comes from Open-Meteo (free, no account) with a wttr.in fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enableWeather {
                Section {
                    Picker("Units", selection: Binding(
                        get: { Defaults[.weatherTemperatureUnit] },
                        set: { Defaults[.weatherTemperatureUnit] = $0 }
                    )) {
                        ForEach(WeatherTemperatureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }

                    Picker("Data source", selection: Binding(
                        get: { Defaults[.weatherProviderSource] },
                        set: { Defaults[.weatherProviderSource] = $0 }
                    )) {
                        ForEach(WeatherProviderSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }

                    Defaults.Toggle(key: .weatherShowsAQI) {
                        Text("Show air quality")
                    }
                    .disabled(!weatherProviderSource.supportsAirQuality)

                    if weatherShowsAQI && weatherProviderSource.supportsAirQuality {
                        Picker("AQI scale", selection: Binding(
                            get: { Defaults[.weatherAQIScale] },
                            set: { Defaults[.weatherAQIScale] = $0 }
                        )) {
                            ForEach(WeatherAirQualityScale.allCases) { scale in
                                Text(scale.displayName).tag(scale)
                            }
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    if !weatherProviderSource.supportsAirQuality {
                        Text("Air quality requires the Open-Meteo data source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text("Location")
                        Spacer()
                        if weather.locationDenied {
                            Label("Denied", systemImage: "xmark.circle")
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Label("OK", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    if weather.locationDenied {
                        Button("Open Location Settings…") { weather.openLocationSettings() }
                    }
                    Button("Refresh now") {
                        Task { await weather.refresh(force: true) }
                    }
                    if let error = weather.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("VibeIsland uses your approximate location to fetch local weather. Without it, a fallback location is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Weather")
    }
}
