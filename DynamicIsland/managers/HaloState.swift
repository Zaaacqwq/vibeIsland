/*
 * VibeIsland
 * Copyright (C) 2026 Zaaacqwq and VibeIsland contributors.
 *
 * The agent status "halo" (states, colors, animations) is inspired by and
 * adapted from Claude Halo (https://github.com/Houyusu/claude-halo), MIT
 * License — Copyright (C) Houyu. See NOTICE.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version. See the GNU General Public License
 * for more details.
 */

import SwiftUI

/// The six Claude activity states surfaced by the halo, mirroring Claude Halo's
/// model. Derived from the hook events VibeIsland already receives over the
/// bridge (SessionStart → idle, UserPromptSubmit → thinking, PreToolUse →
/// executing, permission/question → inputNeeded, Stop → completed, PreCompact
/// → compacting).
enum HaloState: Equatable {
    case idle
    case thinking
    case executing
    case inputNeeded
    case completed
    case compacting

    /// Halo's state color palette.
    var color: Color {
        switch self {
        case .idle:        return Color(red: 0.667, green: 0.667, blue: 0.667) // #aaaaaa
        case .thinking:    return Color(red: 1.0,   green: 0.533, blue: 0.188) // #ff8830
        case .executing:   return Color(red: 0.2,   green: 0.6,   blue: 1.0)   // #3399ff
        case .inputNeeded: return Color(red: 0.933, green: 0.2,   blue: 0.2)   // #ee3333
        case .completed:   return Color(red: 0.2,   green: 0.8,   blue: 0.333) // #33cc55
        case .compacting:  return Color(red: 0.6,   green: 0.267, blue: 1.0)   // #9944ff
        }
    }

    var label: String {
        switch self {
        case .idle:        return "Idle"
        case .thinking:    return "Thinking"
        case .executing:   return "Executing"
        case .inputNeeded: return "Needs input"
        case .completed:   return "Completed"
        case .compacting:  return "Compacting"
        }
    }

    /// Continuous rotation speed in radians/second (0 = no rotation).
    var rotationSpeed: Double {
        switch self {
        case .idle:        return 0.55
        case .thinking:    return 0.9
        case .executing:   return 3.2
        case .inputNeeded: return 0.0
        case .completed:   return 0.4
        case .compacting:  return 1.6
        }
    }

    /// Animation family driving the ring's secondary motion.
    enum Motion { case steady, breathe, pulse, radiusPulse }

    var motion: Motion {
        switch self {
        case .idle:        return .steady
        case .thinking:    return .breathe
        case .executing:   return .steady
        case .inputNeeded: return .pulse
        case .completed:   return .breathe
        case .compacting:  return .radiusPulse
        }
    }

    /// Priority for collapsing multiple sessions into one closed-pill halo.
    /// Higher wins. Attention must always surface.
    var aggregatePriority: Int {
        switch self {
        case .inputNeeded: return 6
        case .executing:   return 5
        case .compacting:  return 4
        case .thinking:    return 3
        case .completed:   return 2
        case .idle:        return 1
        }
    }
}
