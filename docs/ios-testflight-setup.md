# iOS TestFlight CI setup — one-time, no Mac required

This is the checklist for getting `.github/workflows/build-ios-testflight.yml`
able to actually run. Every step below happens in a web browser (Apple
Developer portal, App Store Connect, GitHub) or via `openssl` on any OS —
nothing here needs Xcode or a physical Mac. The GitHub-hosted `macos-latest`
runner is the only Mac involved, and it only runs at CI time.

Blocked on: an active Apple Developer Program membership (Individual,
$99/yr, ~24-48h to clear after enrolling at
developer.apple.com/programs/enroll).

## 1. Distribution certificate (`IOS_DIST_CERTIFICATE_BASE64` + `IOS_DIST_CERTIFICATE_PASSWORD`)

Generate a Certificate Signing Request with plain `openssl` (works on
Windows/Linux/Mac alike — this is the one step people assume needs Keychain
Access, but it doesn't):

```bash
openssl genrsa -out ios_distribution.key 2048
openssl req -new -key ios_distribution.key -out ios_distribution.csr -subj "/emailAddress=<your Apple ID email>, CN=<Your Name>, C=AU"
```

1. Apple Developer portal → **Certificates, Identifiers & Profiles** →
   Certificates → **+** → **Apple Distribution** → upload
   `ios_distribution.csr` → download the resulting `.cer` file.
2. Convert the downloaded cert + your private key into one `.p12` (still
   plain `openssl`, no Mac):
   ```bash
   openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
   openssl pkcs12 -export -inkey ios_distribution.key -in distribution.pem -out ios_distribution.p12 -password pass:<choose a password>
   ```
3. Base64-encode it for GitHub Secrets:
   ```bash
   base64 -i ios_distribution.p12 -o ios_distribution.p12.base64   # macOS/Linux
   certutil -encode ios_distribution.p12 ios_distribution.p12.base64   # Windows
   ```
4. GitHub repo → Settings → Secrets and variables → Actions → New secret:
   - `IOS_DIST_CERTIFICATE_BASE64` = contents of the base64 file
   - `IOS_DIST_CERTIFICATE_PASSWORD` = the password you chose in step 2

## 2. App ID + provisioning profile (`IOS_PROVISIONING_PROFILE_BASE64` + `IOS_PROVISIONING_PROFILE_NAME`)

1. Developer portal → **Identifiers** → **+** → register App ID
   `com.nbawatchability.app` (same bundle ID `ios/project.yml` already
   declares — must match exactly).
2. **Profiles** → **+** → **App Store** distribution type → select the App ID
   above and the distribution certificate from step 1 → name it something
   memorable (e.g. `Big4Watchability AppStore`) → download the
   `.mobileprovision` file.
3. Base64-encode it the same way as step 1.3 above →
   `IOS_PROVISIONING_PROFILE_BASE64` secret.
4. `IOS_PROVISIONING_PROFILE_NAME` secret = the exact name you gave the
   profile in step 2 (must match precisely, it's used as
   `PROVISIONING_PROFILE_SPECIFIER` in the workflow).

## 3. Keychain password (`IOS_CI_KEYCHAIN_PASSWORD`)

Any string — this only protects a throwaway keychain that exists for the
lifetime of one CI run. Generate one and store it as a secret; the value
itself doesn't matter beyond "not empty."

## 4. Team ID (`IOS_APPLE_TEAM_ID`)

Developer portal → **Membership details** (or the top-right of any
Certificates/Identifiers/Profiles page) → **Team ID**, a 10-character
alphanumeric string.

## 5. App Store Connect API key (`ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_BASE64`)

This is what lets the upload step authenticate without an interactive
Apple ID login (no 2FA prompt possible in CI).

1. App Store Connect → **Users and Access** → **Integrations** tab → **App
   Store Connect API** → **+** to generate a key. Access level: **App
   Manager** is enough (don't need Admin).
2. Download the `.p8` key file **immediately** — Apple only lets you
   download it once.
3. Base64-encode it (same method as above) → `ASC_API_KEY_BASE64`.
4. `ASC_API_KEY_ID` = the Key ID shown next to it in the list.
5. `ASC_API_ISSUER_ID` = the Issuer ID shown at the top of the Integrations
   page (same for every key on the account).

## 6. Register the app in App Store Connect

Before the first upload can succeed, the app itself needs a record in App
Store Connect (separate from the Developer Portal App ID above): **My Apps**
→ **+** → **New App** → iOS, bundle ID `com.nbawatchability.app`, SKU
(any unique string, e.g. `big4watchability001`).

## Once all 7 secrets exist

Run the workflow manually first: GitHub repo → Actions →
"Deploy iOS app to TestFlight" → **Run workflow**. Expect to iterate — the
exact `xcodebuild`/`altool` flags in the workflow file are the current
documented pattern but have never actually been run against a real account,
same as every other piece of this iOS build (see
`project_ios_rewrite_2026_08_14` memory's own "push one thing, confirm
green" practice). Once it's green, the app appears under TestFlight in App
Store Connect within a few minutes, ready to install via the TestFlight app
once you add yourself as an internal tester.
