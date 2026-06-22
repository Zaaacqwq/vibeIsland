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
import Foundation

// MARK: - Configuration enums

enum WeatherProviderSource: String, CaseIterable, Defaults.Serializable, Identifiable {
    case wttr = "wttr.in"
    case openMeteo = "Open Meteo"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var supportsAirQuality: Bool {
        switch self {
        case .wttr: return false
        case .openMeteo: return true
        }
    }
}

enum WeatherTemperatureUnit: String, CaseIterable, Defaults.Serializable, Identifiable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { rawValue }
    var usesMetricSystem: Bool { self == .celsius }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var openMeteoTemperatureParameter: String? {
        switch self {
        case .celsius: return nil
        case .fahrenheit: return "fahrenheit"
        }
    }
}

enum WeatherAirQualityScale: String, CaseIterable, Defaults.Serializable, Identifiable {
    case us = "U.S. AQI"
    case european = "EAQI"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var compactLabel: String {
        switch self {
        case .us: return String(localized: "AQI")
        case .european: return String(localized: "EAQI")
        }
    }

    var queryParameter: String {
        switch self {
        case .us: return "us_aqi"
        case .european: return "european_aqi"
        }
    }

    var gaugeRange: ClosedRange<Double> {
        switch self {
        case .us: return 0...500
        case .european: return 0...120
        }
    }
}

enum WeatherProviderError: Error {
    case invalidURL
    case invalidResponse
    case noData
}

// MARK: - Snapshot

/// Weather-only snapshot (decoupled from the former lock-screen widget, which
/// also carried battery/bluetooth accessories).
struct WeatherSnapshot: Equatable {
    struct SunCycleInfo: Equatable {
        let sunrise: Date?
        let sunset: Date?
    }

    struct TemperatureInfo: Equatable {
        let current: Double
        let minimum: Double?
        let maximum: Double?
        let unitSymbol: String

        var displayCurrent: String { Self.formatted(value: current) }
        var displayMinimum: String? { minimum.map(Self.formatted) }
        var displayMaximum: String? { maximum.map(Self.formatted) }

        private static func formatted(value: Double) -> String { "\(Int(round(value)))" }
    }

    struct AirQualityInfo: Equatable {
        enum Category: String, Equatable {
            case good, fair, moderate, unhealthyForSensitive, unhealthy
            case poor, veryPoor, veryUnhealthy, extremelyPoor, hazardous, unknown

            var displayName: String {
                switch self {
                case .good: return String(localized: "Good")
                case .fair: return String(localized: "Fair")
                case .moderate: return String(localized: "Moderate")
                case .unhealthyForSensitive: return String(localized: "Sensitive")
                case .unhealthy: return String(localized: "Unhealthy")
                case .poor: return String(localized: "Poor")
                case .veryPoor: return String(localized: "Very Poor")
                case .veryUnhealthy: return String(localized: "Very Unhealthy")
                case .extremelyPoor: return String(localized: "Extremely Poor")
                case .hazardous: return String(localized: "Hazardous")
                case .unknown: return String(localized: "Unknown")
                }
            }
        }

        let index: Int
        let category: Category
        let scale: WeatherAirQualityScale
    }

    /// A single day in the multi-day forecast.
    struct DailyForecast: Equatable, Identifiable {
        let date: Date
        let symbolName: String
        let high: Double?
        let low: Double?

        var id: TimeInterval { date.timeIntervalSinceReferenceDate }
    }

    let temperatureText: String
    let symbolName: String
    let description: String
    let locationName: String?
    let airQuality: AirQualityInfo?
    let temperatureInfo: TemperatureInfo?
    let sunCycle: SunCycleInfo?
    let daily: [DailyForecast]
}

extension WeatherSnapshot.AirQualityInfo.Category {
    init(index: Int, scale: WeatherAirQualityScale) {
        switch scale {
        case .us:
            switch index {
            case ..<0: self = .unknown
            case 0...50: self = .good
            case 51...100: self = .moderate
            case 101...150: self = .unhealthyForSensitive
            case 151...200: self = .unhealthy
            case 201...300: self = .veryUnhealthy
            case 301...: self = .hazardous
            default: self = .unknown
            }
        case .european:
            switch index {
            case ..<0: self = .unknown
            case 0...20: self = .good
            case 21...40: self = .fair
            case 41...60: self = .moderate
            case 61...80: self = .poor
            case 81...100: self = .veryPoor
            case 101...: self = .extremelyPoor
            default: self = .unknown
            }
        }
    }
}
