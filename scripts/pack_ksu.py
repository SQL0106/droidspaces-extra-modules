#!/usr/bin/env python3
"""Package out/*.ko and ksu-module/ into a KernelSU flashable zip."""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "out")
SRC = os.path.join(ROOT, "ksu-module")
NAME = "droidspaces_extra"

ko = [os.path.join(OUT, n + ".ko") for n in ("ip6table_nat", "macvlan")]
missing = [p for p in ko if not os.path.isfile(p)]
if missing:
    sys.exit("missing: " + ", ".join(missing))

os.makedirs(OUT, exist_ok=True)
zip_path = os.path.join(OUT, NAME + "-ksu.zip")
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for f in ("module.prop", "service.sh"):
        z.write(os.path.join(SRC, f), f"{NAME}/{f}")
    for p in ko:
        z.write(p, f"{NAME}/{os.path.basename(p)}")
print(zip_path)
