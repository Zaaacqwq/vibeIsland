# Publishing VibeIsland updates

VibeIsland checks this repository's `Updates/appcast.xml` through Sparkle.
The Sparkle signing private key is stored in the macOS login Keychain under
Sparkle's default `ed25519` account. The matching public key is configured as
`SUPublicEDKey` in `DynamicIsland/Info.plist`.

The GitHub Release workflow performs the update publishing steps whenever a
`v*` tag is pushed. It builds the app with the tag's marketing version and a
monotonically increasing workflow build number, signs with Developer ID,
notarizes and staples the DMG, creates the GitHub Release, signs the archive
with Sparkle, and commits the updated appcast to `main`. A failed signing or
notarization step stops publication.

Use the workflow's **Run workflow** button on `main` to test signing,
notarization, stapling, and Gatekeeper assessment without creating a GitHub
Release or changing the appcast. The test build uses version `0.0.0` and stays
on the GitHub Actions runner.

The signing identity is `Developer ID Application: ZIYUE CHEN (66M8FY87U6)`.
The certificate and its private key must be exported together as a password
protected PKCS#12 file from the maintainer's login Keychain. Keep a secure
backup. Do not use an Apple Development certificate for public releases.
Releases through v1.4.1 used a revoked Apple Development certificate; later
releases used `VibeIsland Self-Signed`. The first update to Developer ID changes
the code signing identity, so users may need to re-grant macOS privacy
permissions once. Keep the Sparkle EdDSA key unchanged and test upgrading an
installed self-signed release before publishing the first Developer ID release.

Release builds intentionally retain the historical
`com.zaaacqwq.VibeIsland.dev` bundle identifier because v1.0.0 shipped with
that identifier. Changing it would make macOS treat the update as a different
application and invalidate existing privacy permissions. The suffix is now a
compatibility identifier and does not indicate a Debug build.

The workflow requires these repository Actions secrets:

- `DEVELOPER_ID_CERTIFICATE_BASE64`: base64 of the exported `.p12` file.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: the `.p12` export password.
- `NOTARY_APPLE_ID`: the Apple Account email enrolled in the Developer Program.
- `NOTARY_APP_PASSWORD`: an app-specific password generated at
  [account.apple.com](https://account.apple.com/) for `notarytool`.
- `SPARKLE_PRIVATE_KEY`: the existing Sparkle EdDSA private key.

Set the secrets in GitHub repository Settings > Secrets and variables > Actions.
The old `MACOS_CERTIFICATE_BASE64` and `MACOS_CERTIFICATE_PASSWORD` secrets
are retained only for historical releases and are no longer used by this
workflow. Never print private keys or passwords, or commit them to the repo.

Manual publishing reference:

1. Increment both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
2. Build `VibeIsland.app` signed with Developer ID (see the
   workflow's build step for the exact settings).
3. Package the signed app in a DMG, submit it with `notarytool`, and staple the
   accepted ticket to the DMG. Verify the stapled ticket before publishing.
4. Put the stapled DMG in a temporary updates directory and generate the
   signed feed using Sparkle's bundled tool:

   ```bash
   generate_appcast \
     --download-url-prefix "https://github.com/Zaaacqwq/vibeIsland/releases/download/<tag>/" \
     --link "https://github.com/Zaaacqwq/vibeIsland/releases/tag/<tag>" \
     -o appcast.xml \
     /path/to/updates-directory
   ```

5. Upload the archive as an asset on the matching GitHub Release.
6. Replace `Updates/appcast.xml` with the generated file and publish it before
   announcing the release.

Do not hand-write enclosure sizes or EdDSA signatures. Keep a secure backup of
the Sparkle private key; published applications cannot migrate silently to a
lost replacement key.
