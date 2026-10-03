#!/usr/bin/env bash
# Source this file before running Flutter or Android SDK commands.
TASK_APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TASK_APP_ROOT
export ANDROID_HOME="$TASK_APP_ROOT/.tools/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
export PUB_CACHE="$TASK_APP_ROOT/.cache/pub"
export GRADLE_USER_HOME="$TASK_APP_ROOT/.cache/gradle"
export XDG_CONFIG_HOME="$TASK_APP_ROOT/.cache/config"
export XDG_CACHE_HOME="$TASK_APP_ROOT/.cache/xdg"
export XDG_DATA_HOME="$TASK_APP_ROOT/.cache/share"
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
export PATH="$TASK_APP_ROOT/.tools/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"
