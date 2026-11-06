#!/system/bin/sh
# Load the extra modules manually as root.
# Usage: sh load.sh [dir]
DIR="${1:-$(dirname "$0")}"

for m in ip6table_nat macvlan; do
    echo "== loading $m =="
    if command -v ksud >/dev/null 2>&1; then
        ksud insmod "$DIR/$m.ko" || insmod "$DIR/$m.ko"
    else
        insmod "$DIR/$m.ko"
    fi
    echo "rc=$?"
done

echo "== ip6tables nat =="
ip6tables -t nat -L -n 2>&1 | head -20

echo "== macvlan probe =="
ip link add link wlan0 name mvtest0 type macvlan mode bridge 2>&1 && {
    ip link set mvtest0 up 2>/dev/null
    ip link del mvtest0
    echo "macvlan OK"
}
