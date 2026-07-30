{
  description = "LocalLLM — Flutter/Android development environment";

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
          cmake-3-22-1            # required by cactus C++ native build
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

          echo "─────────────────────────────────────────────────────────"
          echo " LocalLLM Cactus dev environment (FHS)"
          echo ""
          echo " Flutter:  $(flutter --version 2>&1 | head -1)"
          echo " ADB:      $(adb version 2>&1 | head -1)"
          echo " Python:   $(python3.12 --version) "
          echo ""
          echo " Flutter Android build:"
          echo "   cd natural_farming_chat && flutter pub get && flutter build apk --release"
          echo ""
          echo " Cactus conversion:"
          echo "   bash conversion/convert_to_cactus.sh --merged-model /path/to/model"
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
            pkgs.git-lfs
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
