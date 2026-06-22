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

import CoreLocation
import Defaults
import Foundation

/// Fetches weather snapshots from Open-Meteo (free, no key) with a wttr.in
/// fallback. Pure data layer, decoupled from any UI.
actor WeatherProvider {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder()
    }

    func fetchSnapshot(location: CLLocation?, source: WeatherProviderSource, placeName: String? = nil) async throws -> WeatherSnapshot {
        switch source {
        case .wttr:
            return try await fetchWttrSnapshot(location: location, placeName: placeName)
        case .openMeteo:
            guard let location else {
                return try await fetchWttrSnapshot(location: nil, placeName: placeName)
            }
            return try await fetchOpenMeteoSnapshot(location: location, placeName: placeName)
        }
    }

    private func fetchWttrSnapshot(location: CLLocation?, placeName: String? = nil) async throws -> WeatherSnapshot {
        let locationSuffix: String
        if let coordinate = location?.coordinate {
            locationSuffix = "\(String(format: "%.4f", coordinate.latitude)),\(String(format: "%.4f", coordinate.longitude))"
        } else {
            locationSuffix = ""
        }

        let query = "?format=j1&aqi=yes"
        let urlString = locationSuffix.isEmpty ? "https://wttr.in/\(query)" : "https://wttr.in/\(locationSuffix)\(query)"
        guard let url = URL(string: urlString) else { throw WeatherProviderError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherProviderError.invalidResponse
        }

        let payload = try decoder.decode(WTTRResponse.self, from: data)
        guard let condition = payload.currentCondition.first else { throw WeatherProviderError.noData }

        let unit = Defaults[.weatherTemperatureUnit]
        let usesMetric = unit.usesMetricSystem
        let temperatureValue = Double(usesMetric ? condition.tempC : condition.tempF) ?? 0
        let temperatureText = "\(Int(round(temperatureValue)))°"

        let forecast = payload.dailyWeather.first
        let minTempValue = forecast.flatMap { Double(usesMetric ? ($0.mintempC ?? "") : ($0.mintempF ?? "")) }
        let maxTempValue = forecast.flatMap { Double(usesMetric ? ($0.maxtempC ?? "") : ($0.maxtempF ?? "")) }

        let temperatureInfo = WeatherSnapshot.TemperatureInfo(
            current: temperatureValue, minimum: minTempValue, maximum: maxTempValue, unitSymbol: unit.symbol
        )

        let code = Int(condition.weatherCode) ?? 113
        let symbol = symbolAdjustedForDaylight(WeatherSymbolMapper.symbol(for: code), isDaytime: condition.isDaytime ?? true)

        let airQualityInfo: WeatherSnapshot.AirQualityInfo?
        if let index = condition.airQuality?.usIndexValue {
            airQualityInfo = WeatherSnapshot.AirQualityInfo(index: index, category: .init(index: index, scale: .us), scale: .us)
        } else {
            airQualityInfo = nil
        }

        return WeatherSnapshot(
            temperatureText: temperatureText,
            symbolName: symbol,
            description: condition.localizedDescription,
            locationName: payload.nearestArea.first?.preferredName ?? placeName,
            airQuality: airQualityInfo,
            temperatureInfo: temperatureInfo,
            sunCycle: nil,
            daily: []
        )
    }

    private func fetchOpenMeteoSnapshot(location: CLLocation, placeName: String? = nil) async throws -> WeatherSnapshot {
        let latitude = String(format: "%.4f", location.coordinate.latitude)
        let longitude = String(format: "%.4f", location.coordinate.longitude)
        let unit = Defaults[.weatherTemperatureUnit]

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: latitude),
            URLQueryItem(name: "longitude", value: longitude),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,pressure_msl"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        if let parameter = unit.openMeteoTemperatureParameter {
            queryItems.append(URLQueryItem(name: "temperature_unit", value: parameter))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw WeatherProviderError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherProviderError.invalidResponse
        }

        let weatherDecoder = JSONDecoder()
        weatherDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try weatherDecoder.decode(OpenMeteoForecastResponse.self, from: data)
        guard let current = payload.current else { throw WeatherProviderError.noData }

        let temperatureValue = current.temperature2M ?? 0
        let temperatureText = "\(Int(round(temperatureValue)))°"
        let mapping = OpenMeteoSymbolMapper.mapping(for: current.weatherCode ?? 0)
        let symbolName = symbolAdjustedForDaylight(mapping.symbol, isDaytime: (current.isDay ?? 1) == 1)

        let sunriseDate = nextSunEvent(from: payload.daily?.sunrise, timezoneIdentifier: payload.timezone, offsetSeconds: payload.utcOffsetSeconds)
        let sunsetDate = nextSunEvent(from: payload.daily?.sunset, timezoneIdentifier: payload.timezone, offsetSeconds: payload.utcOffsetSeconds)
        let sunCycle = (sunriseDate != nil || sunsetDate != nil) ? WeatherSnapshot.SunCycleInfo(sunrise: sunriseDate, sunset: sunsetDate) : nil

        let temperatureInfo = WeatherSnapshot.TemperatureInfo(
            current: temperatureValue,
            minimum: payload.daily?.temperature2MMin?.first,
            maximum: payload.daily?.temperature2MMax?.first,
            unitSymbol: unit.symbol
        )

        var airQualityInfo: WeatherSnapshot.AirQualityInfo?
        if Defaults[.weatherShowsAQI] {
            airQualityInfo = try? await fetchOpenMeteoAirQuality(latitude: latitude, longitude: longitude, scale: Defaults[.weatherAQIScale])
        }

        let daily = buildDailyForecast(from: payload.daily, timezoneIdentifier: payload.timezone, offsetSeconds: payload.utcOffsetSeconds)

        return WeatherSnapshot(
            temperatureText: temperatureText,
            symbolName: symbolName,
            description: mapping.description,
            locationName: placeName,
            airQuality: airQualityInfo,
            temperatureInfo: temperatureInfo,
            sunCycle: sunCycle,
            daily: daily
        )
    }

    private func buildDailyForecast(from daily: OpenMeteoForecastResponse.Daily?, timezoneIdentifier: String?, offsetSeconds: Int?) -> [WeatherSnapshot.DailyForecast] {
        guard let daily, let times = daily.time else { return [] }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        if let identifier = timezoneIdentifier, let timeZone = TimeZone(identifier: identifier) {
            dayFormatter.timeZone = timeZone
        } else if let offset = offsetSeconds, let timeZone = TimeZone(secondsFromGMT: offset) {
            dayFormatter.timeZone = timeZone
        }

        func value<T>(_ array: [T]?, _ index: Int) -> T? {
            guard let array, array.indices.contains(index) else { return nil }
            return array[index]
        }

        return times.enumerated().compactMap { index, dayString in
            guard let date = dayFormatter.date(from: dayString) else { return nil }
            let code = value(daily.weatherCode, index) ?? 0
            return WeatherSnapshot.DailyForecast(
                date: date,
                symbolName: OpenMeteoSymbolMapper.mapping(for: code).symbol,
                high: value(daily.temperature2MMax, index),
                low: value(daily.temperature2MMin, index)
            )
        }
    }

    private func fetchOpenMeteoAirQuality(latitude: String, longitude: String, scale: WeatherAirQualityScale) async throws -> WeatherSnapshot.AirQualityInfo? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: latitude),
            URLQueryItem(name: "longitude", value: longitude),
            URLQueryItem(name: "current", value: scale.queryParameter),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { throw WeatherProviderError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherProviderError.invalidResponse
        }

        let airDecoder = JSONDecoder()
        airDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try airDecoder.decode(OpenMeteoAirQualityResponse.self, from: data)
        guard let airCurrent = payload.current else { return nil }

        let rawValue: Double? = scale == .us ? airCurrent.usAqi : airCurrent.europeanAqi
        guard let indexValue = rawValue else { return nil }

        let index = Int(round(indexValue))
        return WeatherSnapshot.AirQualityInfo(index: index, category: .init(index: index, scale: scale), scale: scale)
    }

    private func nextSunEvent(from values: [String]?, timezoneIdentifier: String?, offsetSeconds: Int?) -> Date? {
        guard let values else { return nil }
        let now = Date()
        for value in values {
            if let date = parseLocalSunTime(value, timezoneIdentifier: timezoneIdentifier, offsetSeconds: offsetSeconds), date >= now {
                return date
            }
        }
        return values.last.flatMap { parseLocalSunTime($0, timezoneIdentifier: timezoneIdentifier, offsetSeconds: offsetSeconds) }
    }

    private func parseLocalSunTime(_ value: String, timezoneIdentifier: String?, offsetSeconds: Int?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let identifier = timezoneIdentifier, let timeZone = TimeZone(identifier: identifier) {
            formatter.timeZone = timeZone
        } else if let offset = offsetSeconds, let timeZone = TimeZone(secondsFromGMT: offset) {
            formatter.timeZone = timeZone
        }
        return formatter.date(from: value)
    }
}

// MARK: - API response models

private struct WTTRResponse: Decodable {
    let current_condition: [WTTRCurrentCondition]
    let nearest_area: [WTTRNearestArea]?
    let weather: [WTTRDailyWeather]?

    var currentCondition: [WTTRCurrentCondition] { current_condition }
    var nearestArea: [WTTRNearestArea] { nearest_area ?? [] }
    var dailyWeather: [WTTRDailyWeather] { weather ?? [] }
}

private struct WTTRCurrentCondition: Decodable {
    private enum CodingKeys: String, CodingKey {
        case tempC = "temp_C", tempF = "temp_F", weatherCode, weatherDesc
        case langEn = "lang_en", airQuality = "air_quality", isday
    }

    let tempC: String
    let tempF: String
    let weatherCode: String
    let weatherDesc: [WTTRTextValue]?
    let langEn: [WTTRTextValue]?
    let airQuality: WTTRAirQuality?
    let isday: String?

    var localizedDescription: String {
        if let english = langEn?.first?.value, !english.isEmpty { return english }
        if let desc = weatherDesc?.first?.value, !desc.isEmpty { return desc }
        return ""
    }

    var isDaytime: Bool? {
        guard let isday else { return nil }
        let normalized = isday.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "yes"
    }
}

private struct WTTRTextValue: Decodable { let value: String }

private struct WTTRAirQuality: Decodable {
    private enum CodingKeys: String, CodingKey {
        case usEpaIndex = "us-epa-index"
    }
    let usEpaIndex: String?
    var usIndexValue: Int? { usEpaIndex.flatMap(Int.init) }
}

private struct WTTRDailyWeather: Decodable {
    let maxtempC: String?
    let maxtempF: String?
    let mintempC: String?
    let mintempF: String?
}

private struct WTTRNearestArea: Decodable {
    let areaName: [WTTRTextValue]?
    let region: [WTTRTextValue]?
    let country: [WTTRTextValue]?

    var preferredName: String? {
        if let name = areaName?.first?.value, !name.isEmpty { return name }
        if let regionName = region?.first?.value, !regionName.isEmpty { return regionName }
        if let countryName = country?.first?.value, !countryName.isEmpty { return countryName }
        return nil
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature2M: Double?
        let weatherCode: Int?
        let isDay: Int?
    }
    struct Daily: Decodable {
        let time: [String]?
        let weatherCode: [Int]?
        let temperature2MMax: [Double]?
        let temperature2MMin: [Double]?
        let sunrise: [String]?
        let sunset: [String]?
    }
    let current: Current?
    let daily: Daily?
    let timezone: String?
    let utcOffsetSeconds: Int?
}

private struct OpenMeteoAirQualityResponse: Decodable {
    struct Current: Decodable {
        let usAqi: Double?
        let europeanAqi: Double?
    }
    let current: Current?
}

// MARK: - Weather-code → SF Symbol mapping

private enum OpenMeteoSymbolMapper {
    static func mapping(for code: Int) -> (symbol: String, description: String) {
        switch code {
        case 0: return ("sun.max.fill", String(localized: "Clear sky"))
        case 1: return ("cloud.sun.fill", String(localized: "Mainly clear"))
        case 2: return ("cloud.sun.fill", String(localized: "Partly cloudy"))
        case 3: return ("cloud.fill", String(localized: "Overcast"))
        case 45, 48: return ("cloud.fog.fill", String(localized: "Fog"))
        case 51, 53, 55: return ("cloud.drizzle.fill", String(localized: "Drizzle"))
        case 56, 57: return ("cloud.sleet.fill", String(localized: "Freezing drizzle"))
        case 61, 63, 65: return ("cloud.rain.fill", String(localized: "Rain"))
        case 66, 67: return ("cloud.sleet.fill", String(localized: "Freezing rain"))
        case 71, 73, 75, 77: return ("cloud.snow.fill", String(localized: "Snow"))
        case 80, 81, 82: return ("cloud.heavyrain.fill", String(localized: "Rain showers"))
        case 85, 86: return ("cloud.snow.fill", String(localized: "Snow showers"))
        case 95: return ("cloud.bolt.rain.fill", String(localized: "Thunderstorm"))
        case 96, 99: return ("cloud.bolt.rain.fill", String(localized: "Thunderstorm with hail"))
        default: return ("cloud.sun.fill", String(localized: "Cloudy"))
        }
    }
}

private enum WeatherSymbolMapper {
    static func symbol(for code: Int) -> String {
        switch code {
        case 113: return "sun.max.fill"
        case 116: return "cloud.sun.fill"
        case 119, 122: return "cloud.fill"
        case 143, 248, 260: return "cloud.fog.fill"
        case 176, 263, 266, 293, 296, 299, 302, 353, 356, 359: return "cloud.rain.fill"
        case 179, 182, 185, 311, 314, 317, 320, 362, 365: return "cloud.sleet.fill"
        case 227, 230, 281, 284, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377: return "cloud.snow.fill"
        case 200, 386, 389, 392, 395: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

private func symbolAdjustedForDaylight(_ symbol: String, isDaytime: Bool) -> String {
    guard !isDaytime else { return symbol }
    switch symbol {
    case "sun.max.fill": return "moon.stars.fill"
    case "cloud.sun.fill": return "cloud.moon.fill"
    case "cloud.sun.rain.fill": return "cloud.moon.rain.fill"
    case "cloud.sun.bolt.fill": return "cloud.moon.bolt.fill"
    default: return symbol
    }
}

// MARK: - Location

@MainActor
final class WeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var pendingContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var lastLocation: CLLocation?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func prepareAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 1800 {
                return lastLocation
            }
            manager.requestLocation()
            return await withCheckedContinuation { continuation in
                self.pendingContinuations.append(continuation)
            }
        default:
            return nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        flushContinuations(with: lastLocation)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        flushContinuations(with: nil)
    }

    private func flushContinuations(with location: CLLocation?) {
        guard !pendingContinuations.isEmpty else { return }
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume(returning: location) }
    }
}
