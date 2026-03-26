{
  description = "CopyLeft Cultivars — Flutter/Android dev + NF benchmark environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # ── Android SDK ───────────────────────────────────────────────────────
        # Mirrors the Dockerfile: build-tools 36.0.0, android-36, NDK r28c
        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          platform-tools          # adb, fastboot
          build-tools-36-0-0
          platforms-android-36
          ndk-28-2-13676358       # Flutter 3.41.1 default NDK (r28c)
        ]);

        # ── Shared native libs Flutter needs at build/runtime ─────────────────
        flutterLibs = with pkgs; [
          libx11
          libxcb
          gtk3
          glib
          clang
          cmake
          ninja
          pkg-config
        ];

      in {
        devShells.default = pkgs.mkShell {
          name = "copyleft-cultivars";

          packages = [
            pkgs.flutter
            androidSdk
            pkgs.dart
            pkgs.jdk17
            pkgs.android-tools   # standalone adb if SDK path not on PATH
            pkgs.git
            pkgs.curl
            pkgs.unzip
            pkgs.python312       # 3.12: pre-built wheels for opencompass/scikit-learn/torch
          ] ++ flutterLibs;

          ANDROID_HOME = "${androidSdk}/share/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/share/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";
          PUB_CACHE = "$HOME/.pub-cache";
          FLUTTER_CLI_ANALYTICS = "false";

          shellHook = ''
            # ── Benchmark venv ────────────────────────────────────────────────
            # benchmark/requirements.txt is the source of truth.
            # The venv is gitignored and created once on first `nix develop`.
            VENV_DIR="$PWD/benchmark/.venv"
            if [ ! -f "$VENV_DIR/bin/activate" ]; then
              echo "Creating benchmark venv..."
              python3.12 -m venv "$VENV_DIR"
              "$VENV_DIR/bin/pip" install -q --upgrade pip
              "$VENV_DIR/bin/pip" install -q numpy  # must precede opencompass (scikit-learn build dep)
              "$VENV_DIR/bin/pip" install -q -r "$PWD/benchmark/requirements.txt"
              echo "Done."
            fi
            source "$VENV_DIR/bin/activate"

            echo "─────────────────────────────────────────────────────────"
            echo " CopyLeft Cultivars dev environment"
            echo ""
            echo " Flutter:  $(flutter --version 2>&1 | head -1)"
            echo " ADB:      $(adb version 2>&1 | head -1)"
            echo " Python:   $(python3.12 --version) [benchmark/.venv]"
            echo ""
            echo " Benchmark workflow (Pixel 7 → localhost:11435):"
            echo "   1. adb devices"
            echo "   2. adb forward tcp:11435 tcp:11435"
            echo "   3. curl http://localhost:11435/api/tags   # verify model ready"
            echo "   4. cd benchmark && python evaluate.py \\"
            echo "        --ollama-url http://localhost:11435 \\"
            echo "        --ollama-model cactus-pixel7-qwen3-0.6"
            echo ""
            echo " Flutter APK build:"
            echo "   cd natural_farming_chat && flutter pub get && flutter build apk --release"
            echo "─────────────────────────────────────────────────────────"
          '';
        };
      }
    );
}
