#!/system/bin/sh
# 双网络守护 - WebUI 后端

MODDIR=/data/adb/modules/dualnet_keep
. "$MODDIR/scripts/common.sh"

# 生成已安装第三方应用列表：pkg|uid|label（含中文名）
_build_apps_list() {
  LABELS=$CONFDIR/labels.txt

  NEED=0
  if [ ! -s "$LABELS" ]; then
    NEED=1
  elif [ -n "$(find "$LABELS" -mmin +1440 2>/dev/null)" ]; then
    NEED=1
  else
    pm list packages 2>/dev/null | sed 's/package://' | sort > "$CONFDIR/.pk.tmp"
    MISS=$(awk -F'|' 'NR==FNR{h[$1]=1;next} !($1 in h)' "$LABELS" "$CONFDIR/.pk.tmp" 2>/dev/null | head -1)
    rm -f "$CONFDIR/.pk.tmp"
    [ -n "$MISS" ] && NEED=1
  fi

  if [ "$NEED" = "1" ]; then
    TMP=$CONFDIR/.labels.tmp
    rm -f "$TMP"
    app_process -Djava.class.path="$MODDIR/tools/label.dex" /system/bin dualnet.LabelDump "$TMP" >/dev/null 2>&1
    if [ -s "$TMP" ] && ! grep -q '^__error__' "$TMP"; then
      mv -f "$TMP" "$LABELS"
    else
      rm -f "$TMP"
    fi
  fi

  # 收集所有用户（主空间 / 小云空间 / 应用分身）的第三方应用，按包名去重
  TMP1=$CONFDIR/.apps1.tmp
  TMP2=$CONFDIR/.apps2.tmp
  : > "$TMP1"
  for _u in $(dn_users); do
    pm list packages -3 -U --user "$_u" 2>/dev/null \
      | sed -n 's/^package:\([^ ]*\) uid:\([0-9]*\).*/\1|\2/p' >> "$TMP1"
  done
  # 同一个包在多个用户下只保留最小 uid（通常是主空间）
  sort -t'|' -k1,1 -k2,2n "$TMP1" | awk -F'|' '!seen[$1]++' > "$TMP2"
  mv -f "$TMP2" "$TMP1"

  if [ -s "$LABELS" ]; then
    awk -F'|' 'NR==FNR{lbl[$1]=$2; next}
      {n=split($0,a,"|"); print a[1]"|"a[2]"|"((a[1] in lbl)?lbl[a[1]]:a[1])}' "$LABELS" "$TMP1"
  else
    awk -F'|' '{print $0"|"$1}' "$TMP1"
  fi
  rm -f "$TMP1"
}

CMD=$1
shift 2>/dev/null

case "$CMD" in

status)
  SSID=$(cmd wifi status 2>/dev/null | grep -m1 "connected to" | sed 's/.*connected to //; s/"//g')
  WIP=$(dn_mobile_ip wlan0)
  IF=$(dn_mobile_iface 2>/dev/null)
  MIP=""
  MK=""
  if [ -n "$IF" ]; then
    MIP=$(dn_mobile_ip "$IF")
    MK=$(dn_iface_mark "$IF")
  fi
  echo "ssid=${SSID:-未连接}"
  echo "wifi_ip=${WIP:-}"
  echo "mobile_iface=${IF:-}"
  echo "mobile_ip=${MIP:-}"
  echo "mark=${MK:-}"
  echo "keep_data=$([ -f "$CONFDIR/keep_data" ] && echo 1 || echo 0)"
  echo "force_route=$([ -f "$CONFDIR/force_route" ] && echo 1 || echo 0)"
  echo "notify=$([ -f "$CONFDIR/notify_off" ] && echo 0 || echo 1)"
  echo "daemon=$(dn_daemon_alive)"
  echo "rule_count=$(iptables -t mangle -S OUTPUT 2>/dev/null | grep -c "comment $TAG")"
  echo "wifi_leak=$(awk '$2 > 0 { s += $2 } END { print s + 0 }' "$CONFDIR/wifi_leak.state" 2>/dev/null)"
  echo "app_count=$(grep -vcE '^[[:space:]]*(#|$)' "$APPS_CONF" 2>/dev/null)"
  echo "version=$(grep -m1 '^version=' "$MODDIR/module.prop" | cut -d= -f2)"
  ;;

labels)
  # 生成 包名|应用名|uid 缓存
  TMP=$CONFDIR/.labels.tmp
  rm -f "$TMP"
  app_process -Djava.class.path="$MODDIR/tools/label.dex" /system/bin dualnet.LabelDump "$TMP" >/dev/null 2>&1
  if [ -s "$TMP" ] && ! grep -q '^__error__' "$TMP"; then
    mv -f "$TMP" "$CONFDIR/labels.txt"
    echo "ok $(wc -l < "$CONFDIR/labels.txt")"
  else
    rm -f "$TMP"
    echo "err"
  fi
  ;;

apps)
  # 只输出 已选 + 已安装 列表；未安装部分优先读缓存，秒出
  echo "##selected"
  grep -vE '^[[:space:]]*(#|$)' "$APPS_CONF" 2>/dev/null
  echo "##installed"
  if [ -s "$CONFDIR/apps_cache.txt" ]; then
    cat "$CONFDIR/apps_cache.txt"
  else
    _build_apps_list
  fi
  ;;

apps-refresh)
  # 后台重建已安装应用列表（含中文名），结果写入缓存
  TMPC=$CONFDIR/.apps_cache.tmp
  rm -f "$TMPC"
  _build_apps_list > "$TMPC" 2>/dev/null
  if [ -s "$TMPC" ]; then
    mv -f "$TMPC" "$CONFDIR/apps_cache.txt"
    echo "ok $(wc -l < "$CONFDIR/apps_cache.txt")"
  else
    rm -f "$TMPC"
    echo "err"
  fi
  ;;

save)
  TMP=$CONFDIR/.apps.tmp
  cat > "$TMP"
  grep -E '^[A-Za-z0-9_][A-Za-z0-9_.]*$' "$TMP" 2>/dev/null | sort -u > "$APPS_CONF"
  CNT=$(grep -vcE '^[[:space:]]*(#|$)' "$APPS_CONF" 2>/dev/null)
  rm -f "$TMP"
  # 勾选了应用就自动启用强制分流
  [ "$CNT" -gt 0 ] && touch "$CONFDIR/force_route"
  dn_lock
  R=$(dn_apply_routes)
  dn_unlock
  dn_log "webui save: $CNT apps | $R"
  dn_event "勾选变更：$CNT 个应用走移动数据"
  echo "ok $CNT $R"
  ;;

set)
  KEY=$1
  VAL=$2
  case "$KEY" in
    keep_data)
      [ "$VAL" = "1" ] && touch "$CONFDIR/keep_data" || rm -f "$CONFDIR/keep_data"
      dn_log "webui: keep_data=$VAL"
      echo "ok"
      ;;
    notify)
      if [ "$VAL" = "1" ]; then
        rm -f "$CONFDIR/notify_off"
        pgrep -f "notify_status.sh" >/dev/null 2>&1 \
          || ( nohup sh "$MODDIR/scripts/notify_status.sh" >/dev/null 2>&1 & )
      else
        touch "$CONFDIR/notify_off"
        for p in $(pgrep -f "notify_status.sh" 2>/dev/null); do kill "$p" 2>/dev/null; done
      fi
      dn_log "webui: notify=$VAL"
      echo "ok"
      ;;
    force_route)
      [ "$VAL" = "1" ] && touch "$CONFDIR/force_route" || rm -f "$CONFDIR/force_route"
      dn_lock
      R=$(dn_apply_routes)
      dn_unlock
      dn_log "webui: force_route=$VAL | $R"
      echo "ok $R"
      ;;
    *) echo "err unknown key";;
  esac
  ;;

apply)
  dn_lock
  R=$(dn_apply_routes)
  dn_unlock
  dn_log "webui: manual apply | $R"
  echo "ok $R"
  ;;

icons-ver)
  # 只返回版本标记，供前端判断是否需要重新拉取图标
  ICONS=$CONFDIR/icons.txt
  if [ -s "$ICONS" ]; then
    stat -c '%Y-%s' "$ICONS" 2>/dev/null || echo "$(wc -c < "$ICONS")"
  else
    echo "none"
  fi
  ;;

icons)
  ICONS=$CONFDIR/icons.txt
  NEED=0
  if [ ! -s "$ICONS" ]; then
    NEED=1
  else
    pm list packages 2>/dev/null | sed 's/package://' | sort > "$CONFDIR/.pk3.tmp"
    MISS=$(awk -F'|' 'NR==FNR{h[$1]=1;next} !($1 in h)' "$ICONS" "$CONFDIR/.pk3.tmp" 2>/dev/null | head -1)
    rm -f "$CONFDIR/.pk3.tmp"
    [ -n "$MISS" ] && NEED=1
  fi
  if [ "$NEED" = "1" ]; then
    TMP=$CONFDIR/.icons.tmp
    rm -f "$TMP"
    app_process -Djava.class.path="$MODDIR/tools/label.dex" /system/bin dualnet.DumpIcons "$TMP" >/dev/null 2>&1
    if [ -s "$TMP" ] && ! grep -q '^__error__' "$TMP"; then
      mv -f "$TMP" "$ICONS"
    else
      rm -f "$TMP"
    fi
  fi
  cat "$ICONS" 2>/dev/null
  ;;

publicip)
  TMP=$CONFDIR/.ip.tmp
  rm -f "$TMP"
  app_process -Djava.class.path="$MODDIR/tools/label.dex" /system/bin dualnet.PublicIp "$TMP" >/dev/null 2>&1
  if [ -s "$TMP" ] && grep -q '^wifi=' "$TMP"; then
    grep -E '^(wifi|mobile)=' "$TMP"
  else
    printf 'wifi=-\nmobile=-\n'
  fi
  rm -f "$TMP"
  ;;

log)
  echo "───── 应用网络 ─────"
  tail -30 "$CONFDIR/events.log" 2>/dev/null || echo "(暂无记录)"
  echo
  echo "───── 守护事件 ─────"
  tail -25 "$LOG" 2>/dev/null || echo "(暂无记录)"
  ;;

reset)
  dn_clear_rules
  echo "ok"
  ;;

*)
  echo "usage: ctl.sh {status|apps|save|set|apply|log|reset}"
  ;;
esac
