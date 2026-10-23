#!/system/bin/sh
# 白名单应用的 WiFi 出包探针
# 在 filter OUTPUT 上按 uid + oif wlan0 挂计数器，用于发现"漏到 WiFi"的流量
TAG=dn_wifi_probe
CONFDIR=${CONFDIR:-/data/adb/dualnet}
APPS_CONF=$CONFDIR/apps.conf
STATE=$CONFDIR/wifi_leak.state

uid_of() {
  pm list packages -U 2>/dev/null | grep "^package:$1 " | head -1 \
    | sed 's/.*uid:\([0-9]*\).*/\1/'
}

clean_probe() {
  while iptables -S OUTPUT 2>/dev/null | grep -q "comment $TAG"; do
    r=$(iptables -S OUTPUT 2>/dev/null | grep "comment $TAG" | head -1 | sed 's/^-A /-D /')
    [ -z "$r" ] && break
    iptables $r 2>/dev/null || break
  done
}

install_probe() {
  # 已装且数量匹配则跳过
  cur=$(iptables -S OUTPUT 2>/dev/null | grep -c "comment $TAG")
  want=$(grep -vcE '^[[:space:]]*(#|$)' "$APPS_CONF" 2>/dev/null)
  [ "$cur" = "$want" ] && [ "$cur" != "0" ] && return 0

  clean_probe
  for pkg in $(grep -vE '^[[:space:]]*(#|$)' "$APPS_CONF" 2>/dev/null); do
    uid=$(uid_of "$pkg")
    [ -z "$uid" ] && continue
    iptables -I OUTPUT -m owner --uid-owner "$uid" -o wlan0 \
      -m comment --comment "$TAG" -j RETURN 2>/dev/null
  done
}

# 输出 "uid pkts bytes" 每行一条
read_counts() {
  iptables -L OUTPUT -v -n 2>/dev/null \
    | grep "$TAG" \
    | sed -n 's/^ *\([0-9]*\) *\([0-9]*\).*UID match \([0-9]*\).*/\3 \1 \2/p'
}

check() {
  install_probe
  read_counts > "$STATE.new"
  # 与上次比对，找出包数增长的 uid
  leak=""
  if [ -f "$STATE" ]; then
    while read -r uid pkts bytes; do
      [ "$pkts" = "0" ] && continue
      prev=$(awk -v u="$uid" '$1 == u { print $2 }' "$STATE" 2>/dev/null)
      [ -z "$prev" ] && prev=0
      [ "$pkts" -gt "$prev" ] && leak="$leak $uid:$((pkts - prev))"
    done < "$STATE.new"
  fi
  mv -f "$STATE.new" "$STATE"
  echo "${leak# }"
}

case "$1" in
  install) install_probe; echo ok ;;
  check)   check ;;
  reset)   clean_probe; rm -f "$STATE"; echo ok ;;
  clean)   clean_probe; rm -f "$STATE" "$STATE.new"; echo ok ;;
  raw)     read_counts ;;
  *) echo "usage: $0 install|check|reset|clean|raw" ;;
esac
