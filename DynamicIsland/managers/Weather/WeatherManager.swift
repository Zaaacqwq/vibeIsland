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

import AppKit
import Combine
import CoreLocation
import Defaults
import Foundation

/// Owns the weather feature's data: resolves location, fetches from the
/// provider (Open-Meteo with a wttr.in fallback), and republishes the current
/// snapshot for the notch tab + live activity. Opt-in, refreshes on a timer.
@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var locationDenied = false

    private let provider = WeatherProvider()
    private let locationProvider = WeatherLocationProvider()
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    private init() {}

    var isEnabled: Bool { Defaults[.enableWeather] }

    // MARK: - Lifecycle

    func startIfNeeded() {
        guard isEnabled, !isRunning else { return }
        isRunning = true
        locationProvider.prepareAuthorization()

        // Refetch when units / source / AQI settings change.
        Publishers.MergeMany(
            Defaults.publisher(.weatherTemperatureUnit).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.weatherProviderSource).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.weatherShowsAQI).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.weatherAQIScale).map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            Task { await self?.refresh(force: true) }
        }
        .store(in: &cancellables)

        startTimer()
        Task { await refresh(force: true) }
    }

    func stop() {
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        let interval = max(60, Defaults[.weatherRefreshInterval])
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh(force: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - Fetch

    func refresh(force: Bool) async {
        guard isEnabled, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        locationProvider.prepareAuthorization()
        let status = locationProvider.authorizationStatus
        locationDenied = (status == .denied || status == .restricted)

        let location = await locationProvider.currentLocation()
        let primary = Defaults[.weatherProviderSource]
        do {
            let result = try await fetchWithFallback(location: location, primary: primary)
            snapshot = result
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchWithFallback(location: CLLocation?, primary: WeatherProviderSource) async throws -> WeatherSnapshot {
        do {
            return try await provider.fetchSnapshot(location: location, source: primary)
        } catch {
            // Open-Meteo can fail without a location; fall back to wttr.in.
            if primary == .openMeteo {
                return try await provider.fetchSnapshot(location: location, source: .wttr)
            }
            throw error
        }
    }

    /// Opens the system Location Services settings (for the denied state).
    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
