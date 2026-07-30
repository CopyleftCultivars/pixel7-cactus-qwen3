# =============================================================================
# Flutter Android APK Builder with ADB Deploy Support
# =============================================================================
# Build:  docker build -t nfc-builder .
# Run:    docker run --rm --privileged -v /dev/bus/usb:/dev/bus/usb nfc-builder
# Shell:  docker run --rm -it --privileged -v /dev/bus/usb:/dev/bus/usb nfc-builder bash
# APK:    docker run --rm -v $(pwd)/out:/out nfc-builder \
#           cp build/app/outputs/flutter-apk/app-release.apk /out/
# =============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ---- System dependencies ----
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        git \
        unzip \
        xz-utils \
        zip \
        libglu1-mesa \
        openjdk-17-jdk-headless \
        clang \
        cmake \
        ninja-build \
        pkg-config \
        libgtk-3-dev \
        liblzma-dev \
        libstdc++-14-dev \
        usbutils \
    && rm -rf /var/lib/apt/lists/*

# ---- Environment variables ----
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# ---- Android SDK: command-line tools ----
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
        -o /tmp/cmdline-tools.zip && \
    unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools && \
    mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && \
    rm /tmp/cmdline-tools.zip

# ---- Accept Android SDK licenses ----
RUN yes | sdkmanager --licenses

# ---- Android SDK components ----
# platform-tools:       ADB for device deployment
# build-tools;36.0.0:   matches compileSdk 36
# platforms;android-36:  compile target
# ndk;28.2.13676358:    Flutter 3.41.1 default NDK (r28c, 16KB page size support)
RUN sdkmanager --install \
        "platform-tools" \
        "build-tools;36.0.0" \
        "platforms;android-36" \
        "ndk;28.2.13676358"

# ---- Flutter SDK ----
RUN git clone --depth 1 --branch 3.41.1 \
        https://github.com/flutter/flutter.git ${FLUTTER_HOME}

# Pre-cache Flutter Android artifacts and accept licenses
RUN flutter precache --android && \
    yes | flutter doctor --android-licenses && \
    flutter config --no-analytics

# ---- Working directory ----
WORKDIR /app

# ---- Layer caching: dependency manifests first ----
COPY natural_farming_chat/pubspec.yaml natural_farming_chat/pubspec.lock ./

# The app uses the local Cactus plugin, so it must be present before pub get.
COPY natural_farming_chat/packages/cactus/ ./packages/cactus/

# Copy android build files needed for pub get and Gradle resolution
COPY natural_farming_chat/android/ ./android/

# Write local.properties for SDK paths
RUN printf 'sdk.dir=%s\nflutter.sdk=%s\n' \
        "${ANDROID_HOME}" "${FLUTTER_HOME}" > android/local.properties

# Fetch Dart dependencies (cached unless pubspec changes)
RUN flutter pub get

# ---- Copy full source (busts cache only on source changes) ----
COPY natural_farming_chat/ .

# Regenerate local.properties (COPY overwrites android/)
RUN printf 'sdk.dir=%s\nflutter.sdk=%s\n' \
        "${ANDROID_HOME}" "${FLUTTER_HOME}" > android/local.properties

# Override Gradle JVM args for container (project requests 8G, reduce to 4G)
RUN sed -i 's/-Xmx8G/-Xmx4G/' android/gradle.properties

# ---- Build release APK ----
RUN flutter build apk --release

# ---- Default: install to connected device via ADB ----
CMD ["flutter", "install", "--release"]
