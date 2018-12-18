#!/usr/bin/env bash
#
# LPM | Author: Ben Marten
# Copyright (c) 2017 Leanplum Inc. All rights reserved.
#
# This will not work standalone. You must call it from `make unitypackage`
#

set -o noglob
set -o nounset
set -o pipefail
set -o errexit

PLAY_SERVICES_VERSION=11.0.1

#######################################
# Gets the latest version of specified repo
# Globals:
#   None
# Arguments:
#   Repo to get from
# Returns:
#   Latest published version
#######################################
get_latest_version() {
    curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

#######################################
# Downloads the iOS SDK from internal repository.
# Globals:
#   None
# Arguments:
#   The version to download, e.g. "1.3.2+55"
# Returns:
#   None
#######################################
download_ios_sdk() {
  local version=$1
  local repo=https://github.com/Leanplum/Leanplum-iOS-SDK

  echo "Downloading AppleSDK ${version} ..."
  if [ -d "/tmp/Leanplum-${version}.framework" ]; then
    rm -rf "/tmp/Leanplum-${version}.framework"
  fi

  # Download from offical git repo.
  local destination="/tmp/Leanplum-${version}.zip"
  wget --show-progress -O "$destination" \
    "${repo}/releases/download/${version}/Leanplum.framework.zip"

  echo "Extracting AppleSDK ..."
  rm -rf "/tmp/Leanplum.framework"
  unzip -q "/tmp/Leanplum-${version}.zip" -d "/tmp/"
  rm -rf "/tmp/Leanplum-${version}.zip"
  mv "/tmp/Leanplum.framework" "/tmp/Leanplum-${version}.framework"

  echo "Finished downloading iOS SDK."
}

#######################################
# Replaces a string in a file and checks for success via git status.
# Globals:
#   None
# Arguments:
#   The path to file.
#   The string to replace.
#   The new string.
# Returns:
#   None
#######################################
replace() {
  sed -i '' -e "s|$2|$3|g" "$1"
  cd "$(dirname "$1")" # Change to directory containing the file and check for success.
  if ! git status --porcelain 2>/dev/null | grep "$(basename "$1")"; then
    echo "${R}Error patching file: $1${N}" && exit 1
  fi
  cd ~- # Change back to original folder.
  echo "Updated file: $1"
}

#######################################
# Builds the Unity SDK.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
build() {
  echo "Converting aar-only dependencies to jar..."
  while IFS= read -r -d '' f; do
    local jarFile="${f/.aar/.jar}"
    local filedir
    filedir="$(dirname "$f")"
    if [[ ! -a  $jarFile ]]; then
      echo "Converting from aar to jar: $f"
      cd "$filedir"
      unzip "$f" classes.jar || true
      mv classes.jar "$(basename "$jarFile")" || true
      cd ~-
    fi
  done < <(find "$ANDROID_HOME/extras/" -name '*.aar' -print0)
  
  echo "Preparing dependencies..."
  # Copy AppleSDK
  rm -rf "LeanplumSample/Assets/Plugins/iOS/Leanplum.framework"
  cp -r "/tmp/Leanplum-$APPLE_SDK_VERSION.framework" \
    "LeanplumSample/Assets/Plugins/iOS/Leanplum.framework"

  # Build Android SDK
  rm -rf "../LeanplumSample/Assets/Plugins/Android"
  mkdir -p "../LeanplumSample/Assets/Plugins/Android"
  cd Android
  mvn initialize
  mvn package -U

  # Copy Leanplum Unity SDK to libs folder.
  cp "target/LeanplumUnity-${UNITY_VERSION}.jar" \
    "../LeanplumSample/Assets/Plugins/Android/LeanplumUnity-${UNITY_VERSION}.jar"
  # Copy GCM, FCM, Location Packages to libs folder.
  # shellcheck disable=SC2140
  cp "$ANDROID_HOME/extras/google/m2repository/com/google/android/gms/"\
"play-services-gcm/${PLAY_SERVICES_VERSION}/"\
"play-services-gcm-${PLAY_SERVICES_VERSION}.jar" \
"../LeanplumSample/Assets/Plugins/Android/."
# shellcheck disable=SC2140
  cp "$ANDROID_HOME/extras/google/m2repository/com/google/android/gms/"\
"play-services-base/${PLAY_SERVICES_VERSION}/"\
"play-services-base-${PLAY_SERVICES_VERSION}.jar" \
"../LeanplumSample/Assets/Plugins/Android/."
# shellcheck disable=SC2140
  cp "$ANDROID_HOME/extras/google/m2repository/com/google/android/gms/"\
"play-services-basement/${PLAY_SERVICES_VERSION}/"\
"play-services-basement-${PLAY_SERVICES_VERSION}.jar" \
"../LeanplumSample/Assets/Plugins/Android/."
# shellcheck disable=SC2140
  cp "$ANDROID_HOME/extras/google/m2repository/com/google/android/gms/"\
"play-services-tasks/${PLAY_SERVICES_VERSION}/"\
"play-services-tasks-${PLAY_SERVICES_VERSION}.jar" \
"../LeanplumSample/Assets/Plugins/Android/."
# shellcheck disable=SC2140
  cp "$ANDROID_HOME/extras/google/m2repository/com/google/android/gms/"\
"play-services-iid/${PLAY_SERVICES_VERSION}/"\
"play-services-iid-${PLAY_SERVICES_VERSION}.jar" \
"../LeanplumSample/Assets/Plugins/Android/."
  # shellcheck disable=SC2140
  cp "$ANDROID_HOME/extras/google/m2repository/com/google/firebase/"\
"firebase-messaging/${PLAY_SERVICES_VERSION}/firebase-messaging-${PLAY_SERVICES_VERSION}.jar" \
"../LeanplumSample/Assets/Plugins/Android/."
  # shellcheck disable=SC2140
  cp "$ANDROID_HOME/extras/google/m2repository/com/google/android/gms/"\
"play-services-location/${PLAY_SERVICES_VERSION}/"\
"play-services-location-${PLAY_SERVICES_VERSION}.jar" \
"../LeanplumSample/Assets/Plugins/Android/."

  cd ../

  echo "Exporting Unity SDK Package..."

  PATH_TO_UNITY_ROOT="/Applications/Unity/Unity.app"
  PATH_TO_UNITY="$PATH_TO_UNITY_ROOT/Contents/MacOS/Unity"
  PATH_TO_PROJECT="$(pwd)/LeanplumSample"
  PATH_TO_EXPORT="$(pwd)/Leanplum-Unity-Plugin"

  export OUT_PKG="Leanplum_Unity-$UNITY_VERSION_STRING.unitypackage"
  $PATH_TO_UNITY -quit -nographics -batchmode -projectPath "$PATH_TO_PROJECT" -executeMethod Leanplum.Private.PackageExporter.ExportPackage -logfile
  export UNITY_BINARY="$PATH_TO_PROJECT/$OUT_PKG"

  mv $UNITY_BINARY $PATH_TO_EXPORT

  echo "Done"
}

#######################################
# Configures the Unity SDK build and starts the build.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
main() {
  for i in "$@"; do
    case $i in
      --apple-sdk-version=*)
      APPLE_SDK_VERSION="${i#*=}"
      shift # past argument=value
      ;;
      --android-sdk-version=*)
      ANDROID_SDK_VERSION="${i#*=}"
      shift # past argument=value
      ;;
      --version=*)
      UNITY_VERSION="${i#*=}"
      shift # past argument=value
      ;;
      --stacktrace)
      set -o xtrace
      shift
      ;;
    esac
  done

  # Check for Jenkins build number, otherwise default to curent time in seconds.
  if [[ -z "${BUILD_NUMBER+x}" ]]; then
    BUILD_NUMBER=$(date "+%s")
  fi

  if [[ -z "${UNITY_VERSION+x}" ]]; then
    echo "Unity SDK version not specified, using current: ${UNITY_VERSION}"
  fi

  if [[ -z ${APPLE_SDK_VERSION+x} ]]; then
    APPLE_SDK_VERSION=$(get_latest_version "Leanplum/Leanplum-iOS-SDK")
    echo "iOS SDK version not specified, using latest: ${APPLE_SDK_VERSION}"
  fi
  if [[ -z ${ANDROID_SDK_VERSION+x} ]]; then
    ANDROID_SDK_VERSION=$(get_latest_version "Leanplum/Leanplum-Android-SDK")
    echo "Android SDK version not specified, using latest: ${ANDROID_SDK_VERSION}"
  fi

  export UNITY_VERSION_STRING=${UNITY_VERSION_STRING:-"$UNITY_VERSION.$BUILD_NUMBER"}
  echo "Building unitypackage with version ${UNITY_VERSION_STRING}, using iOS ${APPLE_SDK_VERSION} and Android ${ANDROID_SDK_VERSION}"

  download_ios_sdk $APPLE_SDK_VERSION

  replace "Android/pom.xml" \
    "<version>%LP_UNITY_VERSION%</version>" "<version>${UNITY_VERSION}</version>"
  replace "LeanplumSample/Assets/Plugins/Android/mainTemplate.gradle" \
    "%LP_VERSION%" "${ANDROID_SDK_VERSION}"
  replace "LeanplumSample/Assets/Plugins/Android/mainTemplate.gradle" \
    "%LP_UNITY_VERSION%" "${UNITY_VERSION}"
  replace "Android/pom.xml" "<version>\[1.2.25,)</version>" \
    "<version>${ANDROID_SDK_VERSION}</version>"

  build

  # Restore variable Android version
  git checkout "Android/pom.xml"

  echo "Done."
}

main "$@"
