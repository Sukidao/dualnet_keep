#!/system/bin/sh
# 状态栏常驻通知：显示当前前台 App 走流量还是走 WiFi
MODDIR=${MODDIR:-/data/adb/modules/dualnet_keep}
CONFDIR=${CONFDIR:-/data/adb/dualnet}

BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB=$(command -v busybox 2>/dev/null)
HAS_BB=0
[ -x "$BB" ] && $BB --list 2>/dev/null | grep -qx setuidgid && HAS_BB=1

ICON_DIR=/data/local/tmp/dualnet_icons
mkdir -p "$ICON_DIR" 2>/dev/null
chmod 755 "$ICON_DIR" 2>/dev/null

post() {
  _title="$1"; _text="$2"; _icon="$3"
  if [ -n "$_icon" ] && [ -s "$_icon" ]; then
    _iconarg="-i file://$_icon -I file://$_icon"
  else
    _iconarg=""
  fi
  if [ "$HAS_BB" = "1" ]; then
    $BB setuidgid 2000 cmd notification post -S bigtext $_iconarg -t "$_title" dualnet_status "$_text" >/dev/null 2>&1
  else
    su 2000 -c "cmd notification post -S bigtext $_iconarg -t \"$_title\" dualnet_status \"$_text\"" >/dev/null 2>&1
  fi
}

EVLOG=$CONFDIR/events.log
LAST_PKG=""

log_event() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$EVLOG"
  _n=$(wc -l < "$EVLOG" 2>/dev/null)
  if [ "${_n:-0}" -gt 600 ]; then
    tail -n 300 "$EVLOG" > "$EVLOG.tmp" 2>/dev/null && mv -f "$EVLOG.tmp" "$EVLOG"
  fi
}

LAST=""
LAST_POST=0

while true; do
  [ -f "$CONFDIR/notify_off" ] && { sleep 5; continue; }

  pkg=$(dumpsys activity activities 2>/dev/null \
        | grep -m1 "topResumedActivity" \
        | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p')
  [ -z "$pkg" ] && pkg=$(dumpsys window 2>/dev/null \
        | grep -m1 "mCurrentFocus" \
        | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p')
  [ -z "$pkg" ] && pkg="unknown"

  name=""
  [ -f "$CONFDIR/labels.txt" ] && name=$(grep -m1 "^$pkg|" "$CONFDIR/labels.txt" 2>/dev/null | cut -d'|' -f2)
  [ -z "$name" ] && name=$(echo "$pkg" | awk -F. '{print $NF}')

  if grep -qx "$pkg" "$CONFDIR/apps.conf" 2>/dev/null; then
    route="移动数据"
  else
    route="WiFi"
  fi

  mif=$(ip -4 addr show 2>/dev/null | grep -oE 'rmnet_data[0-9]+' | head -1)
  mip=""
  [ -n "$mif" ] && mip=$(ip -4 addr show dev "$mif" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)

  wif=$(cmd wifi status 2>/dev/null | grep -m1 -oE 'SSID: "[^"]*"' | sed 's/SSID: "//;s/"//')

  # 前台应用切换时记录一条网络走向
  if [ "$pkg" != "$LAST_PKG" ] && [ "$pkg" != "unknown" ]; then
    LAST_PKG=$pkg
    log_event "$name → $route"
  fi

  NOW=$(date +%s)
  cur="$pkg|$route|$mip|$wif"
  if [ "$cur" != "$LAST" ] || [ $((NOW - LAST_POST)) -gt 300 ]; then
    LAST="$cur"
    LAST_POST=$NOW

    # 前台应用图标（按包名缓存）
    icon="$ICON_DIR/$pkg.png"
    if [ ! -s "$icon" ] && [ "$pkg" != "unknown" ]; then
      app_process -Djava.class.path="$MODDIR/tools/label.dex" /system/bin \
        dualnet.DumpIcon "$pkg" "$icon" >/dev/null 2>&1
      chmod 644 "$icon" 2>/dev/null
    fi

    post "$name → $route" "4G ${mip:-未连接} ｜ WiFi ${wif:-未连接}" "$icon"
  fi

  sleep 3
done
