#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    TASK_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
mkdir -p .build/checks
xcrun swiftc -sdk "$TASK_SDK" DSHMeter/RefreshSchedule.swift Tests/RefreshChecks/main.swift -o .build/checks/refresh
.build/checks/refresh
xcrun swift run --sdk "$TASK_SDK" --triple "$(uname -m)-apple-macosx13.0" DSHMeterChecks "$@"
