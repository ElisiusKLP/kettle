#!/usr/bin/env bash
# Fails if networking APIs appear in Sources/, network entitlements appear in Resources/,
# or Package.swift declares any package dependency.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

status=0

network_apis=(
    'URLSession'
    'NSURLSession'
    'NSURLConnection'
    'NSURLDownload'
    'URLRequest'
    'import Network'
    '\bNW(Connection|Listener|Browser|PathMonitor|Endpoint|Parameters)\b'
    'import WebKit'
    '\bWK[A-Z][A-Za-z]*'
    '\bWebView\b'
    'import CFNetwork'
    'CFSocket'
    'CFStreamCreatePairWith'
    'CFHost'
    '\bsocket\('
    '\bgetaddrinfo\b'
    '\bgethostbyname\b'
    'import CloudKit'
    'import MultipeerConnectivity'
)

for pattern in "${network_apis[@]}"; do
    if matches=$(grep -rnE --include='*.swift' "$pattern" Sources/); then
        echo "error: networking API matching '$pattern' found in Sources/:" >&2
        echo "$matches" >&2
        status=1
    fi
done

if matches=$(grep -rnE 'com\.apple\.security\.network\.(client|server)' Resources/); then
    echo "error: network entitlement found in Resources/:" >&2
    echo "$matches" >&2
    status=1
fi

if matches=$(grep -nE '\.package\(' Package.swift); then
    echo "error: Package.swift declares a package dependency (Kettle has no third-party dependencies):" >&2
    echo "$matches" >&2
    status=1
fi

if (( status == 0 )); then
    echo "No-network check passed."
fi
exit $status
