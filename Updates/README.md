# Publishing VibeIsland updates

VibeIsland checks this repository's `Updates/appcast.xml` through Sparkle.
The signing private key is stored in the macOS login Keychain under Sparkle's
default `ed25519` account. The matching public key is configured as
`SUPublicEDKey` in `DynamicIsland/Info.plist`.

The GitHub Release workflow now performs the update publishing steps
automatically whenever a `v*` tag is pushed. It builds the app with the tag's
marketing version and a monotonically increasing workflow build number,
creates the GitHub Release, signs the archive with Sparkle, and commits the
updated appcast to `main`.

The workflow requires the `SPARKLE_PRIVATE_KEY` repository Actions secret. To
set or rotate it from the machine whose Keychain contains the matching key,
pipe the key directly to `gh secret set`; never print it or commit it.

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
