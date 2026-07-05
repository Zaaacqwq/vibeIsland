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
import Foundation

/// Resolves an approximate location from the device's public IP address, used as
/// a fallback when CoreLocation is unavailable (no fix, transient failure) so
/// Open-Meteo — which strictly requires coordinates — never has to degrade to a
/// third-party geolocating service. Keyless, HTTPS-only sources.
actor IPGeolocationProvider {
    private let session: URLSession
    /// Approximate coordinates are stable enough to reuse for a while; caching
    /// avoids hammering the IP services during a CoreLocation outage.
    private static let cacheLifetime: TimeInterval = 1800

    private var cached: (location: CLLocation, timestamp: Date)?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        session = URLSession(configuration: configuration)
    }

    /// Returns an IP-derived location, or `nil` if every source fails. Tries
    /// ipwho.is first, then geojs.io as a backup.
    func currentLocation() async -> CLLocation? {
        if let cached, abs(cached.timestamp.timeIntervalSinceNow) < Self.cacheLifetime {
            return cached.location
        }

        if let location = await fetchFromIPWhois() {
            cached = (location, Date())
            return location
        }
        if let location = await fetchFromGeoJS() {
            cached = (location, Date())
            return location
        }
        return nil
    }

    // MARK: - Sources

    private func fetchFromIPWhois() async -> CLLocation? {
        guard let url = URL(string: "https://ipwho.is/") else { return nil }
        guard let payload: IPWhoisResponse = await decode(from: url) else { return nil }
        guard payload.success == true, let latitude = payload.latitude, let longitude = payload.longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private func fetchFromGeoJS() async -> CLLocation? {
        guard let url = URL(string: "https://get.geojs.io/v1/ip/geo.json") else { return nil }
        guard let payload: GeoJSResponse = await decode(from: url) else { return nil }
        // geojs.io encodes coordinates as strings.
        guard let latitude = payload.latitude.flatMap(Double.init),
              let longitude = payload.longitude.flatMap(Double.init) else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private func decode<T: Decodable>(from url: URL) async -> T? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Payloads

private struct IPWhoisResponse: Decodable {
    let success: Bool?
    let latitude: Double?
    let longitude: Double?
}

private struct GeoJSResponse: Decodable {
    let latitude: String?
    let longitude: String?
}
