/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import Foundation

/// The language VibeIsland should use after its next launch.
///
/// `.system` deliberately removes the per-app `AppleLanguages` override. The
/// bundle can therefore continue to use any legacy localization it contains,
/// while English and Simplified Chinese are the two maintained choices exposed
/// directly in Settings.
enum AppLanguagePreference: String, CaseIterable, Defaults.Serializable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "Follow System")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    var appleLanguageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }
}

enum AppLanguageController {
    static let appleLanguagesKey = "AppleLanguages"

    /// Locale used by app-owned date and calendar formatting. `AppleLanguages`
    /// selects bundle resources but does not necessarily change
    /// `Locale.current`, so an explicit Chinese app-language choice must also
    /// drive weekday and month names inside the Notch.
    static var locale: Locale {
        switch Defaults[.appLanguage] {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    static var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        return calendar
    }

    static func abbreviatedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.calendar = calendar
        return formatter.string(from: max(0, seconds))
            ?? String(localized: "0 min")
    }

    static func apply(
        _ preference: AppLanguagePreference,
        defaults: UserDefaults = .standard
    ) {
        if let code = preference.appleLanguageCode {
            defaults.set([code], forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
    }
}
