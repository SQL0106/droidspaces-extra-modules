#!/usr/bin/env bash
# Build one or both modules inside the pinned DDK image.
# Usage: scripts/build.sh [macvlan] [ip6table_nat]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOCKER="${DOCKER:-docker}"
IMAGE="${DDK_IMAGE:-$(python3 -c 'import json;print(json.load(open("build/targets.json"))["image"])')}"
KMI="${KMI:-$(python3 -c 'import json;print(json.load(open("build/targets.json"))["kmi"])')}"

if [ "$#" -gt 0 ]; then
  TARGETS="$*"
else
  TARGETS="macvlan ip6table_nat"
fi

mkdir -p out logs .build
: > logs/build-summary.txt
echo "KMI=$KMI" | tee -a logs/build-summary.txt
echo "IMAGE=$IMAGE" | tee -a logs/build-summary.txt
echo "TARGETS=$TARGETS" | tee -a logs/build-summary.txt

status=0

echo "=== DDK environment ===" | tee logs/ddk-env.log
$DOCKER run --rm --platform linux/amd64 "$IMAGE" bash -lc '
  echo "KDIR=$KDIR"
  echo "ARCH=$ARCH"
  echo "LLVM=$LLVM"
  ls -l "$KDIR/Module.symvers"
  grep -m1 "module_layout" "$KDIR/Module.symvers"
' >> logs/ddk-env.log 2>&1
if [ $? -ne 0 ]; then
  echo "DDK environment check FAILED" | tee -a logs/ddk-env.log logs/build-summary.txt
  status=1
fi

for t in $TARGETS; do
  log="logs/$t.log"
  work="$ROOT/.build/$t"
  ko="$work/$t.ko"
  echo "=== build $t ===" | tee "$log"

  mkdir -p "$work/modules/$t"
  cp -a "$ROOT/Makefile" "$work/Makefile"
  cp -a "$ROOT/modules/$t/$t.c" "$work/modules/$t/$t.c"
  rm -f "$ko" "out/$t.ko"

  $DOCKER run --rm --platform linux/amd64 \
    -v "$ROOT:/module" \
    -w "/module/.build/$t" \
    "$IMAGE" \
    make TARGET="$t" 2>&1 | tee -a "$log"
  rc=${PIPESTATUS[0]}

  echo "$rc" > "logs/$t.status"
  if [ "$rc" -eq 0 ] && [ -s "$ko" ]; then
    cp "$ko" "out/$t.ko"
    printf '%s OK %s bytes sha256=%s\n' "$t" "$(stat -c%s "out/$t.ko")" \
      "$(sha256sum "out/$t.ko" | awk '{print $1}')" | tee -a logs/build-summary.txt
  else
    echo "$t FAILED rc=$rc ko_exists=$([ -s "$ko" ] && echo yes || echo no)" \
      | tee -a logs/build-summary.txt
    status=1
  fi
done

# Package the KernelSU flashable zip when both modules built.
if [ -f out/macvlan.ko ] && [ -f out/ip6table_nat.ko ]; then
  if ! python3 scripts/pack_ksu.py | tee -a logs/build-summary.txt; then
    echo "KSU packaging FAILED" | tee -a logs/build-summary.txt
    status=1
  fi
fi

# Metadata is written even when a target failed.
python3 - "$ROOT" "$KMI" "$IMAGE" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

root, kmi, image = sys.argv[1], sys.argv[2], sys.argv[3]
meta = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "kmi": kmi,
    "ddk_image": image,
    "commit": subprocess.run(
        ["git", "-C", root, "rev-parse", "HEAD"],
        capture_output=True, text=True,
    ).stdout.strip(),
    "targets": {},
}
for name in ("macvlan", "ip6table_nat"):
    ko = os.path.join(root, "out", name + ".ko")
    status_path = os.path.join(root, "logs", name + ".status")
    rc = None
    if os.path.exists(status_path):
        try:
            rc = int(open(status_path).read().strip())
        except ValueError:
            pass
    entry = {"rc": rc, "built": os.path.exists(ko)}
    if os.path.exists(ko):
        data = open(ko, "rb").read()
        entry.update({
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })
        try:
            entry["modinfo"] = subprocess.run(
                ["modinfo", ko], capture_output=True, text=True,
            ).stdout.strip()
        except FileNotFoundError:
            entry["modinfo"] = ""
    meta["targets"][name] = entry
open(os.path.join(root, "metadata.json"), "w").write(
    json.dumps(meta, indent=2, ensure_ascii=False) + "\n"
)
PY

echo "=== result ===" | tee -a logs/build-summary.txt
cat logs/build-summary.txt
if [ "$status" -ne 0 ]; then
  echo "BUILD FAILED" >&2
fi
exit "$status"
