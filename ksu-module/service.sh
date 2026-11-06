#!/system/bin/sh
# KernelSU service stage: load the two extra modules after boot.
MODDIR=${0%/*}
LOG="$MODDIR/load.log"
exec >>"$LOG" 2>&1

printf 'droidspaces_extra: %s\n' "$(date -u)"
printf 'kernel: %s\n' "$(uname -r)"

KSUD=/data/adb/ksud
[ -x "$KSUD" ] || KSUD=/data/adb/ksu/bin/ksud

for m in ip6table_nat macvlan; do
    if grep -q "^$m " /proc/modules 2>/dev/null; then
        echo "$m: already loaded"
        continue
    fi
    if [ ! -f "$MODDIR/$m.ko" ]; then
        echo "$m: missing $MODDIR/$m.ko"
        continue
    fi
    if [ -x "$KSUD" ]; then
        "$KSUD" insmod "$MODDIR/$m.ko"
    else
        insmod "$MODDIR/$m.ko"
    fi
    echo "$m: rc=$?"
done
