#!/system/bin/sh
# 双网络守护：WiFi 连接时保持移动数据链路活跃，并可强制指定应用走移动数据

MODDIR=${0%/*}
. "$MODDIR/scripts/common.sh"

# 日志轮转
if [ -f "$LOG" ]; then
  sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  [ "$sz" -gt 204800 ] && mv -f "$LOG" "$LOG.1"
fi

# 等待系统启动完成
n=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 150 ]; do
  sleep 2; n=$((n+1))
done
sleep 8
dn_log "=== daemon started (pid $$) ==="

# 后台生成应用列表缓存（供 WebUI 秒开）
( sh "$MODDIR/scripts/ctl.sh" apps-refresh >/dev/null 2>&1 & )

LAST_SIG=""
LAST_IF=""
LAST_MK=""
TICK=0
LAST_LEAK=0

# 常驻保活进程：向系统持续请求蜂窝网络，阻止 PDN 被释放
start_keepalive() {
  pgrep -f "dualnet.KeepAlive" >/dev/null 2>&1 && return 0
  nohup app_process -Djava.class.path="$MODDIR/tools/label.dex" /system/bin \
    dualnet.KeepAlive "$CONFDIR/keepalive.log" >/dev/null 2>&1 &
  dn_log "keepalive started"
}

[ -f "$CONFDIR/keep_data" ] && start_keepalive

while true; do
  # 1) 维护数据相关开关（只写设置项，绝不动数据开关）
  if [ -f "$CONFDIR/keep_data" ]; then
    # AOSP：WiFi 连接时保持蜂窝数据活跃
    [ "$(settings get global mobile_data_always_active 2>/dev/null)" = "1" ] \
      || settings put global mobile_data_always_active 1 2>/dev/null
    # MIUI/HyperOS：设置界面与流量监控仍读取的旧总开关
    [ "$(settings get global mobile_data 2>/dev/null)" = "1" ] \
      || settings put global mobile_data 1 2>/dev/null
    # MIUI 自有开关
    [ "$(settings get global mobile_data_always_on 2>/dev/null)" = "1" ] \
      || settings put global mobile_data_always_on 1 2>/dev/null

    # 保活进程掉了就重新拉起
    pgrep -f "dualnet.KeepAlive" >/dev/null 2>&1 || start_keepalive

    # 状态栏通知进程保活
    pgrep -f "notify_status.sh" >/dev/null 2>&1 \
      || ( nohup sh "$MODDIR/scripts/notify_status.sh" >/dev/null 2>&1 & )

    # WiFi 漏包检测：白名单应用不应该有任何包从 wlan0 出去
    LEAK=$(sh "$MODDIR/scripts/wifi_probe.sh" check 2>/dev/null)
    if [ -n "$LEAK" ]; then
      NOW2=$(date +%s)
      if [ $((NOW2 - LAST_LEAK)) -gt 600 ]; then
        LAST_LEAK=$NOW2
        dn_log "WIFI_LEAK: $LEAK"
        dn_notify "双网络守护" dualnet_alert "检测到白名单应用流量漏到 WiFi: $LEAK"
      fi
    fi
  fi

  # 2) 接口 / fwmark / 配置变化时重建分流规则
  CUR_IF=$(dn_mobile_iface 2>/dev/null)
  CUR_MK=""
  [ -n "$CUR_IF" ] && CUR_MK=$(dn_iface_mark "$CUR_IF")
  SIG=$(ls -l "$APPS_CONF" 2>/dev/null | awk '{print $5"-"$6"-"$7"-"$8}')
  TICK=$((TICK+1))

  if [ "$SIG" != "$LAST_SIG" ] || [ "$CUR_IF" != "$LAST_IF" ] || [ "$CUR_MK" != "$LAST_MK" ]; then
    dn_lock
    R=$(dn_apply_routes)
    dn_unlock
    case "$R" in
      *keep)
        # 条件不满足，规则未改动，不记录状态以便下一轮重试
        dn_log "apply deferred: $R"
        ;;
      *)
        LAST_SIG="$SIG"; LAST_IF="$CUR_IF"; LAST_MK="$CUR_MK"
        dn_log "apply: $R"
        ;;
    esac
  elif [ $((TICK % 20)) -eq 0 ]; then
    # 兜底：每 10 分钟校正一次，防止规则被系统清理
    dn_lock
    R=$(dn_apply_routes)
    dn_unlock
    dn_log "periodic apply: $R"
    # 顺带刷新应用列表缓存（新装应用自动收录）
    ( sh "$MODDIR/scripts/ctl.sh" apps-refresh >/dev/null 2>&1 & )
  fi

  sleep 30
done
