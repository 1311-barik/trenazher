#!/bin/zsh
# Тесты пакета TrenazherKit.
# С установленным Xcode хватает обычного `swift test`. Без Xcode (только Command Line Tools)
# нужны два обхода: SDK 26.5 (в SDK 27 из CLT @State — макрос без плагина) и явный путь
# к плагину Swift Testing (иначе «plugin for module 'TestingMacros' not found»).
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    CLT=/Library/Developer/CommandLineTools
    export SDKROOT="$CLT/SDKs/MacOSX26.5.sdk"
    swift test -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" "$@"
else
    swift test "$@"
fi
