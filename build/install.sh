#!/system/bin/sh
# 在手机上以 root 运行：从 /data/local/tmp/dualnet 安装到模块目录
SRC=/data/local/tmp/dualnet
DST=/data/adb/modules/dualnet_keep

[ -d "$SRC" ] || { echo "缺少 $SRC"; exit 1; }

rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC"/* "$DST"/

chmod 755 "$DST/service.sh" "$DST/uninstall.sh"
chmod 755 "$DST"/scripts/*.sh
chmod 755 "$DST/tools"
chmod 644 "$DST/tools/label.dex"
find "$DST/webroot" -type f -exec chmod 644 {} \;

mkdir -p /data/adb/dualnet
[ -f /data/adb/dualnet/keep_data ] || touch /data/adb/dualnet/keep_data
chmod 700 /data/adb/dualnet

# 重启守护进程
for p in $(ps -A -o PID,ARGS 2>/dev/null | grep "dualnet_keep/servic[e].sh" | awk '{print $1}'); do
  kill "$p" 2>/dev/null
done
sleep 1

nohup "$DST/service.sh" >/dev/null 2>&1 &
sleep 2

echo "安装完成"
sh "$DST/scripts/ctl.sh" status
