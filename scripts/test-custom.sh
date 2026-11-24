#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --disable-xctest
for suite in bridge touchpad address layout transport stillmouse reconnect players; do
    node "Tests/WebPlayback/$suite.test.cjs"
done
