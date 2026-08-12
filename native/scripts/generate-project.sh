#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
test "$(xcodegen --version | awk '{print $2}')" = "2.46.0"
xcodegen generate --spec project.yml
