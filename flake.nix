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
        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          platform-tools          # adb, fastboot
          build-tools-36-0-0
          build-tools-35-0-0      # required by android_id plugin
          platforms-android-36
          platforms-android-35    # required by cactus plugin
          platforms-android-34    # required by android_id plugin
          ndk-28-2-13676358       # Flutter 3.41.1 default NDK (r28c)
        ]);

        # ── Init script run inside the FHS env ───────────────────────────────
        # buildFHSEnv provides /lib64/ld-linux-x86-64.so.2 so that Gradle's
        # downloaded AAPT2 binary (a pre-built glibc executable) can run.
        initScript = pkgs.writeShellScript "copyleft-cultivars-init" ''
          export ANDROID_HOME="${androidSdk}/share/android-sdk"
          export ANDROID_SDK_ROOT="${androidSdk}/share/android-sdk"
          export JAVA_HOME="${pkgs.jdk17}"
          export PUB_CACHE="$HOME/.pub-cache"
          export FLUTTER_CLI_ANALYTICS="false"
          # Point Gradle at the Nix-provided aapt2 so it never tries to download one
          export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdk}/share/android-sdk/build-tools/36.0.0/aapt2"

          # ── Benchmark venv ────────────────────────────────────────────────
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
          echo " CopyLeft Cultivars dev environment (FHS)"
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
          exec bash
        '';

      in {
        # buildFHSEnv wraps the shell in a fake standard Linux filesystem so
        # that Gradle's pre-built AAPT2 binary can find /lib64/ld-linux-x86-64.so.2.
        devShells.default = (pkgs.buildFHSEnv {
          name = "copyleft-cultivars";

          targetPkgs = pkgs: [
            pkgs.flutter
            androidSdk
            pkgs.dart
            pkgs.jdk17
            pkgs.android-tools
            pkgs.git
            pkgs.curl
            pkgs.unzip
            pkgs.python312
            # Flutter native deps
            pkgs.libx11
            pkgs.libxcb
            pkgs.gtk3
            pkgs.glib
            pkgs.clang
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            # glibc libs needed by AAPT2 and other pre-built Android tooling
            pkgs.glibc
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];

          runScript = initScript;
        }).env;
      }
    );
}
