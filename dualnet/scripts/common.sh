#!/system/bin/sh
# 双网络守护 - 公共函数库（service.sh 与 ctl.sh 共用）

CONFDIR=/data/adb/dualnet
APPS_CONF=$CONFDIR/apps.conf
LOG=$CONFDIR/daemon.log
TAG=dualnet

mkdir -p "$CONFDIR" 2>/dev/null
[ -f "$APPS_CONF" ] || : > "$APPS_CONF"

dn_log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
}

dn_lock() {
  n=0
  while ! mkdir "$CONFDIR/.lock" 2>/dev/null; do
    n=$((n+1))
    if [ $n -gt 10 ]; then rm -rf "$CONFDIR/.lock"; break; fi
    sleep 1
  done
}

dn_unlock() {
  rmdir "$CONFDIR/.lock" 2>/dev/null
}

# 当前真正承载数据的移动接口：有 IPv4 且存在策略路由表项
dn_mobile_iface() {
  for d in /sys/class/net/rmnet_data*; do
    [ -e "$d" ] || continue
    i=${d##*/}
    ip -4 addr show dev "$i" 2>/dev/null | grep -q "inet " || continue
    ip rule 2>/dev/null | grep -qF "iif lo lookup $i" && { echo "$i"; return 0; }
  done
  return 1
}

dn_mobile_ip() {
  ip -4 addr show dev "$1" 2>/dev/null | grep -oE "inet [0-9.]+" | head -1 | cut -d' ' -f2
}

# 该接口对应的 fwmark（形如 0x10069）
dn_iface_mark() {
  ip rule 2>/dev/null \
    | grep -F "iif lo lookup $1" | grep -v uidrange \
    | grep -oE "0x[0-9a-f]+/0x1ffff" | head -1 | cut -d/ -f1
}

dn_uid_of() {
  pm list packages -U 2>/dev/null | grep "^package:$1 " | head -1 \
    | sed 's/.*uid:\([0-9]*\).*/\1/'
}

dn_clear_rules() {
  while iptables -t mangle -S OUTPUT 2>/dev/null | grep -q "comment $TAG"; do
    r=$(iptables -t mangle -S OUTPUT 2>/dev/null | grep "comment $TAG" | head -1 | sed 's/^-A /-D /')
    [ -z "$r" ] && break
    iptables -t mangle $r 2>/dev/null || break
  done
}

# 应用分流规则，输出 "iface mark count"
# 两层配合：
#   1) ip rule + uidrange：让 socket 在 connect 时就选中移动数据的源地址（决定成败）
#   2) iptables MARK：兜底，给已绑定其他接口的包打标记
# 注意：必须先探测接口/mark 成功才清理旧规则，否则接口抖动会误删规则
dn_clear_iprules() {
  # 只清理我们自己用的 15060-15099 段，避开系统规则（15040 等）
  ip rule show 2>/dev/null \
    | awk -F: '$1 >= 15060 && $1 <= 15099 {print $1}' \
    | while read -r p; do
        [ -n "$p" ] && ip rule del pref "$p" 2>/dev/null
      done
}

dn_apply_routes() {
  if [ ! -f "$CONFDIR/force_route" ]; then
    dn_clear_rules
    dn_clear_iprules
    echo "- - 0"; return 0
  fi

  IF=$(dn_mobile_iface 2>/dev/null)
  [ -z "$IF" ] && { echo "- - keep"; return 0; }

  MK=$(dn_iface_mark "$IF")
  [ -z "$MK" ] && { echo "$IF - keep"; return 0; }

  dn_clear_rules
  dn_clear_iprules

  n=0
  pref=15060
  for pkg in $(grep -vE '^[[:space:]]*(#|$)' "$APPS_CONF" 2>/dev/null); do
    uid=$(dn_uid_of "$pkg")
    [ -z "$uid" ] && continue
    n=$((n+1))

    for u in "$uid" "1$uid"; do
      # 关键：按 uid 强制路由到移动数据表，connect 时即选中正确源地址
      if [ "$pref" -le 15099 ]; then
        ip rule add from all uidrange "$u-$u" lookup "$IF" pref "$pref" 2>/dev/null
        pref=$((pref+1))
      fi

      # 兜底：包级 mark
      if ! iptables -t mangle -C OUTPUT -m owner --uid-owner "$u" \
            -m comment --comment "$TAG" -j MARK --set-xmark "$MK/0x1ffff" 2>/dev/null; then
        iptables -t mangle -I OUTPUT 1 -m owner --uid-owner "$u" \
          -m comment --comment "$TAG" -j MARK --set-xmark "$MK/0x1ffff" 2>/dev/null
      fi
    done
  done
  echo "$IF $MK $n"
}

dn_daemon_alive() {
  pgrep -f "dualnet_keep/service.sh" >/dev/null 2>&1 && echo 1 || echo 0
}
