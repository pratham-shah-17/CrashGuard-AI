#!/usr/bin/env bash
# Cloud-agent base image setup for RoadSOS Flutter development.
#
# Bakes in:
#   - OpenJDK 17 (required by Flutter Android Gradle Plugin + AGP 8.x)
#   - Android command-line tools at /opt/android-sdk
#   - platform-tools, platforms;android-34 (project target) AND android-36
#     (Flutter 3.41+ doctor minimum), build-tools;34.0.0 + 36.0.0,
#     ndk;26.1.10909125, cmake;3.22.1
#   - Linux desktop toolchain: ninja-build, libgtk-3-dev, mesa-utils
#   - Supabase CLI (binary release; `npm i -g supabase` is unsupported upstream)
#
# After this script runs once, future shells started in /workspace pick up
# ANDROID_HOME / ANDROID_SDK_ROOT / JAVA_HOME / PATH from the rc files written
# below, so `flutter doctor` and `flutter build apk --debug` work without
# re-installing anything.
#
# Idempotent: re-running is a no-op if every component is already present.

set -euo pipefail

# ---------------------------------------------------------------------------
# Pinned versions — change here, not inline.
# ---------------------------------------------------------------------------
ANDROID_SDK_ROOT_DIR=/opt/android-sdk
ANDROID_CMDLINE_TOOLS_ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

# pubspec.yaml + android/app/build.gradle.kts target SDK 34, NDK 26.1.x.
# Flutter 3.41+ doctor also requires SDK 36, so we install both.
SDK_PLATFORM_PRIMARY="platforms;android-34"
SDK_PLATFORM_DOCTOR="platforms;android-36"
SDK_BUILD_TOOLS_PRIMARY="build-tools;34.0.0"
SDK_BUILD_TOOLS_DOCTOR="build-tools;36.0.0"
SDK_NDK="ndk;26.1.10909125"
SDK_CMAKE="cmake;3.22.1"

SUPABASE_CLI_VERSION="2.98.2"
SUPABASE_CLI_TARBALL_URL="https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_linux_amd64.tar.gz"

JAVA_HOME_DIR=/usr/lib/jvm/java-17-openjdk-amd64

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '\n\033[1;34m[setup]\033[0m %s\n' "$*"; }

# Use sudo only if not root and sudo is available.
SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

# ---------------------------------------------------------------------------
# 1. APT packages: JDK 17 + Linux desktop toolchain + unzip/wget/curl.
# ---------------------------------------------------------------------------
log "Installing apt packages (openjdk-17 + linux desktop deps)..."
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends \
  openjdk-17-jdk-headless \
  ninja-build \
  libgtk-3-dev \
  mesa-utils \
  unzip \
  wget \
  curl \
  ca-certificates \
  git

# Make JDK 17 the default `java` / `javac` — Android Gradle Plugin 8.x rejects
# JDK 21+ for some Kotlin compile tasks even though it nominally supports it.
if [[ -x "${JAVA_HOME_DIR}/bin/java" ]]; then
  $SUDO update-alternatives --set java "${JAVA_HOME_DIR}/bin/java"  >/dev/null 2>&1 || true
  $SUDO update-alternatives --set javac "${JAVA_HOME_DIR}/bin/javac" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 2. Android command-line tools at /opt/android-sdk/cmdline-tools/latest.
# ---------------------------------------------------------------------------
if [[ ! -x "${ANDROID_SDK_ROOT_DIR}/cmdline-tools/latest/bin/sdkmanager" ]]; then
  log "Downloading Android command-line tools to ${ANDROID_SDK_ROOT_DIR}..."
  $SUDO mkdir -p "${ANDROID_SDK_ROOT_DIR}/cmdline-tools"
  $SUDO chown -R "$(id -u):$(id -g)" "${ANDROID_SDK_ROOT_DIR}"
  tmp_dir="$(mktemp -d)"
  wget -q "${ANDROID_CMDLINE_TOOLS_ZIP_URL}" -O "${tmp_dir}/cmdline-tools.zip"
  unzip -q "${tmp_dir}/cmdline-tools.zip" -d "${tmp_dir}/extracted"
  mv "${tmp_dir}/extracted/cmdline-tools" "${ANDROID_SDK_ROOT_DIR}/cmdline-tools/latest"
  rm -rf "${tmp_dir}"
else
  log "Android command-line tools already installed."
fi

export JAVA_HOME="${JAVA_HOME_DIR}"
export ANDROID_HOME="${ANDROID_SDK_ROOT_DIR}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT_DIR}"
export PATH="${ANDROID_SDK_ROOT_DIR}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT_DIR}/platform-tools:${PATH}"

# ---------------------------------------------------------------------------
# 3. Accept SDK licenses, then install required packages.
# ---------------------------------------------------------------------------
log "Accepting Android SDK licenses..."
yes | sdkmanager --licenses >/dev/null 2>&1 || true

log "Installing Android SDK packages..."
sdkmanager \
  "platform-tools" \
  "${SDK_PLATFORM_PRIMARY}" \
  "${SDK_PLATFORM_DOCTOR}" \
  "${SDK_BUILD_TOOLS_PRIMARY}" \
  "${SDK_BUILD_TOOLS_DOCTOR}" \
  "${SDK_NDK}" \
  "${SDK_CMAKE}" >/dev/null

# ---------------------------------------------------------------------------
# 4. Configure Flutter to use this SDK + accept Android licenses through it.
# ---------------------------------------------------------------------------
if command -v flutter >/dev/null 2>&1; then
  log "Configuring flutter to use ${ANDROID_SDK_ROOT_DIR}..."
  flutter config --android-sdk "${ANDROID_SDK_ROOT_DIR}" --no-analytics >/dev/null
  yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
else
  log "WARN: 'flutter' not on PATH; skipping flutter config step."
fi

# ---------------------------------------------------------------------------
# 5. Supabase CLI (binary release; upstream blocks `npm i -g supabase`).
# ---------------------------------------------------------------------------
if ! command -v supabase >/dev/null 2>&1 || \
   [[ "$(supabase --version 2>/dev/null)" != "${SUPABASE_CLI_VERSION}" ]]; then
  log "Installing Supabase CLI v${SUPABASE_CLI_VERSION}..."
  tmp_dir="$(mktemp -d)"
  wget -q "${SUPABASE_CLI_TARBALL_URL}" -O "${tmp_dir}/supabase.tgz"
  tar -xzf "${tmp_dir}/supabase.tgz" -C "${tmp_dir}"
  $SUDO install -m 0755 "${tmp_dir}/supabase" /usr/local/bin/supabase
  rm -rf "${tmp_dir}"
else
  log "Supabase CLI v${SUPABASE_CLI_VERSION} already installed."
fi

# ---------------------------------------------------------------------------
# 6. Persist env vars in every interactive shell (bash + zsh).
# ---------------------------------------------------------------------------
ENV_BLOCK_MARKER="# >>> roadsos cloud-agent env >>>"
ENV_BLOCK_END="# <<< roadsos cloud-agent env <<<"
read -r -d '' ENV_BLOCK <<EOF || true
${ENV_BLOCK_MARKER}
export JAVA_HOME=${JAVA_HOME_DIR}
export ANDROID_HOME=${ANDROID_SDK_ROOT_DIR}
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT_DIR}
export PATH="\$JAVA_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$PATH"
${ENV_BLOCK_END}
EOF

for rc in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
  # Create the file if missing (only touch if its parent dir exists).
  parent="$(dirname "$rc")"
  [[ -d "$parent" ]] || continue
  touch "$rc"
  if ! grep -q "${ENV_BLOCK_MARKER}" "$rc"; then
    printf '\n%s\n' "${ENV_BLOCK}" >> "$rc"
    log "Appended env block to $rc"
  fi
done

# ---------------------------------------------------------------------------
# 7. Summary — print versions so logs prove the install succeeded.
# ---------------------------------------------------------------------------
log "Install complete. Versions:"
java -version 2>&1 | sed 's/^/  /'
echo "  ANDROID_HOME=${ANDROID_HOME}"
sdkmanager --list_installed 2>/dev/null | grep -E "platform-tools|platforms;android|build-tools|ndk;|cmake;" | sed 's/^/  /' || true
supabase --version 2>&1 | sed 's/^/  supabase /'
if command -v flutter >/dev/null 2>&1; then
  flutter --version 2>&1 | head -1 | sed 's/^/  /'
fi
