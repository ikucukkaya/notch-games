# Releasing NotchBasket

## One-time setup

1. **Developer ID certificate** — Xcode → Settings → Accounts → your team →
   Manage Certificates → "+" → *Developer ID Application*. (Requires the paid
   Apple Developer Program; the same account used for App Store Connect works.)

2. **Notary credentials** — create an app-specific password at
   appleid.apple.com, then store it once:

   ```
   xcrun notarytool store-credentials notchbasket \
     --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID \
     --password APP_SPECIFIC_PASSWORD
   ```

## Every release

```
Tools/release.sh
```

Produces `dist/NotchBasket-<version>.dmg`: archived, Developer ID signed,
notarized by Apple, stapled, Gatekeeper-clean. Users download, open, drag to
Applications — no warnings.

Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the project before
tagging a new release.

## Publishing

```
git tag v<version> && git push origin main --tags
gh release create v<version> dist/NotchBasket-<version>.dmg \
  --title "NotchBasket <version>" --notes "..."
```

Optional reach: submit a Homebrew cask (`brew create --cask`) pointing at the
GitHub release asset.
