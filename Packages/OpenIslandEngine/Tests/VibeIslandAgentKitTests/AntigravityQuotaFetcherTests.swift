import Foundation
import Testing
@testable import OpenIslandCore

@Test("Antigravity OAuth request uses PKCE, offline access, and the loopback callback")
func antigravityOAuthRequest() throws {
    let request = try AntigravityOAuth.makeAuthorizationRequest()
    let components = try #require(
        URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)
    )
    let query = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )

    #expect(components.host == "accounts.google.com")
    #expect(query["client_id"] == AntigravityOAuth.clientID)
    #expect(query["redirect_uri"] == AntigravityOAuth.redirectURI)
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["code_challenge"]?.isEmpty == false)
    #expect(query["state"] == request.state)
    #expect(query["access_type"] == "offline")
    #expect(query["prompt"] == "consent")
}

@Test("Antigravity quota groups models and takes the most restrictive value")
func antigravityQuotaAggregation() throws {
    let json = """
    {
      "models": {
        "claude-opus-4-6-thinking": {
          "displayName": "Claude Opus",
          "quotaInfo": {
            "remainingFraction": 0.7,
            "resetTime": "2026-07-07T10:00:00Z"
          }
        },
        "claude-sonnet-4-6": {
          "displayName": "Claude Sonnet",
          "quotaInfo": {
            "remainingFraction": 0.4,
            "resetTime": "2026-07-07T09:00:00Z"
          }
        },
        "gemini-3.1-pro-preview": {
          "displayName": "Gemini 3.1 Pro",
          "quotaInfo": {
            "remainingFraction": 0.8,
            "resetTime": "2026-07-08T10:00:00.000Z"
          }
        },
        "gemini-3-flash-preview": {
          "displayName": "Gemini 3 Flash",
          "quotaInfo": {
            "remainingFraction": 0.95
          }
        },
        "gemini-2.5-flash": {
          "displayName": "Gemini 2.5 Flash",
          "quotaInfo": {
            "remainingFraction": 0.1
          }
        }
      }
    }
    """
    let now = Date(timeIntervalSince1970: 123)
    let parsed = try AntigravityQuotaFetcher.quotaSnapshot(
        from: Data(json.utf8),
        fetchedAt: now
    )
    let snapshot = try #require(parsed)

    #expect(snapshot.providerID == .antigravity)
    #expect(snapshot.fetchedAt == now)
    #expect(snapshot.windows.map(\.key) == ["claude", "gemini-pro", "gemini-flash"])
    #expect(snapshot.windows[0].usedPercentage == 60)
    #expect(snapshot.windows[1].usedPercentage < 20.000_001)
    #expect(snapshot.windows[1].usedPercentage > 19.999_999)
    #expect(snapshot.windows[2].usedPercentage < 5.000_001)
    #expect(snapshot.windows[2].usedPercentage > 4.999_999)

    let expectedReset = ISO8601DateFormatter().date(from: "2026-07-07T09:00:00Z")
    #expect(snapshot.windows[0].resetsAt == expectedReset)
}

@Test("Antigravity quota summary exposes Gemini and Claude/GPT weekly and 5h windows")
func antigravityQuotaSummaryAggregation() throws {
    let json = """
    {
      "groups": [
        {
          "buckets": [
            {
              "bucketId": "gemini-weekly",
              "displayName": "Weekly Limit",
              "window": "weekly",
              "resetTime": "2026-07-13T01:25:16Z",
              "remainingFraction": 0.98829967
            },
            {
              "bucketId": "gemini-5h",
              "displayName": "Five Hour Limit",
              "window": "5h",
              "resetTime": "2026-07-07T07:19:27Z",
              "remainingFraction": 1
            }
          ],
          "displayName": "Gemini Models"
        },
        {
          "buckets": [
            {
              "bucketId": "3p-weekly",
              "displayName": "Weekly Limit",
              "window": "weekly",
              "resetTime": "2026-07-13T02:46:41Z",
              "remainingFraction": 0.663878
            },
            {
              "bucketId": "3p-5h",
              "displayName": "Five Hour Limit",
              "window": "5h",
              "resetTime": "2026-07-07T07:19:27Z",
              "remainingFraction": 1
            }
          ],
          "displayName": "Claude and GPT models"
        }
      ]
    }
    """
    let parsed = try AntigravityQuotaFetcher.summaryQuotaSnapshot(
        from: Data(json.utf8),
        fetchedAt: Date(timeIntervalSince1970: 456)
    )
    let snapshot = try #require(parsed)

    #expect(snapshot.providerID == .antigravity)
    #expect(snapshot.windows.map(\.key) == ["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h"])
    #expect(snapshot.windows.map(\.label) == ["Gemini 7d", "Gemini 5h", "Claude/GPT 7d", "Claude/GPT 5h"])
    #expect(snapshot.windows[0].usedPercentage > 1.17)
    #expect(snapshot.windows[0].usedPercentage < 1.18)
    #expect(snapshot.windows[1].usedPercentage == 0)
    #expect(snapshot.windows[2].usedPercentage > 33.61)
    #expect(snapshot.windows[2].usedPercentage < 33.62)
    #expect(snapshot.windows[3].usedPercentage == 0)
}

@Test("Antigravity quota ignores unrelated and missing quota models")
func antigravityQuotaIgnoresIrrelevantModels() throws {
    let json = """
    {
      "models": {
        "gemini-2.5-flash": {
          "quotaInfo": { "remainingFraction": 0.2 }
        },
        "gemini-3-pro-preview": {
          "displayName": "Gemini 3 Pro"
        }
      }
    }
    """
    let snapshot = try AntigravityQuotaFetcher.quotaSnapshot(
        from: Data(json.utf8),
        fetchedAt: .now
    )
    #expect(snapshot == nil)
}
