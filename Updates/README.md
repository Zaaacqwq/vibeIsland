# Publishing VibeIsland updates

VibeIsland checks this repository's `Updates/appcast.xml` through Sparkle.
The Sparkle signing private key is stored in the macOS login Keychain under
Sparkle's default `ed25519` account. The matching public key is configured as
`SUPublicEDKey` in `DynamicIsland/Info.plist`.

The GitHub Release workflow now performs the update publishing steps
automatically whenever a `v*` tag is pushed. It builds the app with the tag's
marketing version and a monotonically increasing workflow build number,
creates the GitHub Release, signs the application with a stable Apple
Development identity, signs the archive with Sparkle, and commits the updated
appcast to `main`. Keeping the application signing identity stable is required
for macOS privacy permissions to survive an update.

Release builds intentionally retain the historical
`com.zaaacqwq.VibeIsland.dev` bundle identifier because v1.0.0 shipped with
that identifier. Changing it would make macOS treat the update as a different
application and invalidate existing privacy permissions. The suffix is now a
compatibility identifier and does not indicate a Debug build.

The workflow requires `SPARKLE_PRIVATE_KEY`, `MACOS_CERTIFICATE_BASE64`, and
`MACOS_CERTIFICATE_PASSWORD` repository Actions secrets. Set or rotate them
from the machine whose Keychain contains the matching keys. Pipe secret values
directly to `gh secret set`; never print them or commit them.

Manual publishing reference:

1. Increment both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
2. Archive, Developer ID sign, and notarize `VibeIsland.app`.
3. Put the distributable `.dmg`, `.zip`, `.tar.xz`, or `.aar` in a temporary
   updates directory.
4. Generate the signed feed using Sparkle's bundled tool:

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
