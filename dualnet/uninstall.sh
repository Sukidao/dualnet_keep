#!/system/bin/sh
# 卸载时清理本模块添加的 iptables 规则与运行配置
TAG=dualnet

for p in $(ps -A -o PID,ARGS 2>/dev/null | grep "dualnet.KeepAlive" | grep -v grep | awk '{print $1}'); do
  kill "$p" 2>/dev/null
done

for p in $(ps -A -o PID,ARGS 2>/dev/null | grep "notify_status.sh" | grep -v grep | awk '{print $1}'); do
  kill "$p" 2>/dev/null
done

while iptables -S OUTPUT 2>/dev/null | grep -q "comment dn_wifi_probe"; do
  r=$(iptables -S OUTPUT 2>/dev/null | grep "comment dn_wifi_probe" | head -1 | sed 's/^-A /-D /')
  [ -z "$r" ] && break
  iptables $r 2>/dev/null || break
done

ip rule show 2>/dev/null | awk -F: '$1 >= 15060 && $1 <= 15990 {print $1}' \
  | while read -r p; do [ -n "$p" ] && ip rule del pref "$p" 2>/dev/null; done

while iptables -t mangle -S OUTPUT 2>/dev/null | grep -q "comment $TAG"; do
  r=$(iptables -t mangle -S OUTPUT 2>/dev/null | grep "comment $TAG" | head -1 | sed 's/^-A /-D /')
  [ -z "$r" ] && break
  iptables -t mangle $r 2>/dev/null || break
done

rm -rf /data/adb/dualnet
