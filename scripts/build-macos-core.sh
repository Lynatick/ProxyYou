#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="${1:?Specify Hiddify Core v4.1.0 with its pinned submodules}"
source_dir="$(cd "$source_dir" && pwd)"
[[ "$(go -C "$source_dir" version)" == *"go1.25.6 "* ]] || { echo "Go 1.25.6 is required." >&2; exit 1; }
if ! grep -q 'defaultWorkerCount    = 20' "$source_dir/hiddify-sing-box/common/monitoring/outbound_monitoring.go"; then
  patch -d "$source_dir" -p1 < "$root/native-patches/youtube-monitoring.patch"
fi
if [[ ! -f "$source_dir/v2/config/proxyyou_apps.go" ]]; then
  patch -d "$source_dir" -p1 < "$root/native-patches/macos-app-routing.patch"
fi
mkdir -p "$root/hiddify-core/bin"
export GOOS=darwin GOARCH=arm64 CGO_ENABLED=1
tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack,with_dhcp
go -C "$source_dir" test -tags="$tags" ./v2/config -run TestProxyYouApps -count=1
go -C "$source_dir" build -trimpath -ldflags='-w -s -checklinkname=0 -buildid=' -tags="$tags" \
  -buildmode=c-shared -o "$root/hiddify-core/bin/hiddify-core.dylib" ./platform/desktop
