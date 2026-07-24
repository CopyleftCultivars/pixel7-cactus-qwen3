# Codemagic iOS and iPad release workflow

The repository-level [`codemagic.yaml`](codemagic.yaml) contains a manual
fallback workflow for building the existing `natural_farming_chat` Flutter app
as an Ad Hoc-signed iOS IPA. The Ad Hoc profile is intentional: the target is
a registered local iPad, rather than an App Store submission. The primary
build path is local on the M4 to avoid consuming cloud build minutes. The iOS
deployment target is 16.4 because the current Cactus Apple engine requires
iOS 16.4.

## Codemagic setup

1. Add the repository to Codemagic and select `natural_farming_chat` as the
   project path if Codemagic does not detect it automatically.
2. In Codemagic Team settings, add an App Store Connect API key integration
   named `natural-farming-chat-app-store-connect`. Grant it the Apple access
   needed to manage certificates and provisioning profiles.
3. In the workflow's signing settings, use the bundle identifier
   `com.copyleftcultivars.naturalFarmingChat` and select Ad Hoc distribution.
4. Register the iPad's UDID in the Apple Developer portal. The provisioning
   profile used by the workflow must contain that UDID.
5. Commit `codemagic.yaml`, then start the fallback workflow manually when a
   local M4 build is unavailable. The IPA and Xcode archive are available as
   build artifacts.

No certificates, provisioning profiles, API keys, or other signing secrets are
stored in this repository.

## Build locally on the M4

Install the full Xcode application, select it as the active developer
directory, and install Flutter and CocoaPods before building:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
export PATH="/Users/nanonite/development/flutter/bin:$PATH"
flutter doctor
```

The Flutter SDK is installed at `/Users/nanonite/development/flutter` on the
M4. Add the `export PATH=...` line to the shell profile used for local builds
if you want `flutter` available in every terminal. Flutter 3.44.7 stable and
CocoaPods 1.17.0 are currently installed; the full Xcode application is still
required.

Then build the Ad Hoc IPA from the Flutter project directory:

```sh
cd natural_farming_chat
flutter pub get
pod install
flutter build ipa --release --export-method ad-hoc
```

Flutter writes the archive to `build/ios/archive/` and the IPA to
`build/ios/ipa/`. For a local build, Xcode must be signed into the Apple
Developer account and the Runner target must use the same bundle identifier
and a provisioning profile containing the iPad's UDID.

## Convert the local Cactus model

The model bundle must be produced by the same Cactus revision as the native
Apple engine. The repository helper uses the official `cactus convert` command
and limits the KV cache to 2048 tokens for older iPads:

```sh
bash finetune/convert_to_cactus.sh \
  --merged-model finetune/outputs/merged-model \
  --output finetune/outputs/cact-model \
  --bits 4 \
  --cache-context-length 2048
```

The output must contain `components/manifest.json`; a weights-only directory
is not a runnable bundle for the current Cactus Apple engine.

## Direct USB or Thunderbolt installation

For the first device connection, unlock the iPad, trust the M4, pair it in
Xcode's Devices and Simulators window, and enable Developer Mode on the iPad.
Then use Xcode or Apple Configurator to install the generated IPA. With a
recent Xcode installation, the device can also be inspected and managed with
the `devicectl` command included in Xcode.

Direct installation is the fastest path for the first validation because it
does not require uploading the IPA to a distribution service. The iPad still
must be registered in the Ad Hoc provisioning profile, and iPadOS may require
Developer Mode for an IPA installed from the local machine.

## OTA testing with Firebase App Distribution

Firebase App Distribution is the better repeatable OTA path once the direct
build works. It still requires an Ad Hoc IPA and therefore the iPad UDID must
be registered before rebuilding:

```sh
firebase appdistribution:distribute \
  natural_farming_chat/build/ios/ipa/*.ipa \
  --app "$FIREBASE_IOS_APP_ID" \
  --release-notes "iPad validation build" \
  --testers-file testers.txt
```

Invite the tester, open the invitation on the iPad, register the device when
Firebase requests its UDID, add that UDID to Apple Developer, rebuild, and
redistribute. Firebase returns a tester-install link after upload. The
release remains available in App Distribution for a limited retention period,
so keep important IPA artifacts outside Firebase as well.
