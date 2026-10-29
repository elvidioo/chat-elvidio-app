#!/bin/bash
# Compile l'APK : avec Shorebird (mises a jour du code sans reinstaller) si le secret existe, sinon flutter normal.
# Usage : ci/sb.sh <dossier-debug-info> [--dart-define=...]...
# Variables : MODE (release|patch), RUN (numero de build), SHOREBIRD_TOKEN, BUILD_REF (numero de l'APK a corriger).
set -o pipefail
DIR="$1"; shift
EXTRA=(--no-shrink --obfuscate "--split-debug-info=$DIR")
if [ -n "$SHOREBIRD_TOKEN" ]; then
  if [ "$MODE" = "patch" ]; then
    shorebird patch android --artifact apk --release-version=latest "--dart-define=BUILD_NUMBER=$BUILD_REF" "$@" -- "${EXTRA[@]}"
  else
    shorebird release android --artifact apk --flutter-version=latest --build-name=1.0.0 "--build-number=$RUN" "--dart-define=BUILD_NUMBER=$RUN" "$@" -- "${EXTRA[@]}"
  fi
else
  flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 "${EXTRA[@]}" "--build-number=$RUN" "--dart-define=BUILD_NUMBER=$RUN" "$@"
fi
