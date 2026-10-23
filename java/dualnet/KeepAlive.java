package dualnet;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Looper;

import java.io.FileOutputStream;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * 常驻进程：向系统持续声明"需要一个蜂窝网络"，
 * 阻止 WiFi 连接时 Telephony 释放 PDN。
 * 用法: app_process -Djava.class.path=label.dex /system/bin dualnet.KeepAlive <logFile>
 */
public class KeepAlive {
    private static String logPath = "/data/adb/dualnet/keepalive.log";
    private static final SimpleDateFormat FMT = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US);

    public static void main(String[] args) {
        if (args.length > 0) logPath = args[0];

        try {
            Context ctx = getSystemContext();
            final ConnectivityManager cm =
                    (ConnectivityManager) ctx.getSystemService(Context.CONNECTIVITY_SERVICE);

            NetworkRequest req = new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build();

            ConnectivityManager.NetworkCallback cb = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(Network n) { log("cellular available: " + n); }

                @Override
                public void onLost(Network n) { log("cellular LOST: " + n); }

                @Override
                public void onCapabilitiesChanged(Network n, NetworkCapabilities nc) {
                    // 静默，避免日志刷屏
                }
            };

            cm.requestNetwork(req, cb);
            log("requestNetwork(CELLULAR) submitted");

            // 心跳线程：定期记录，同时保持引用不被回收
            Thread hb = new Thread(new Runnable() {
                @Override
                public void run() {
                    int i = 0;
                    while (true) {
                        try { Thread.sleep(60000); } catch (InterruptedException ignored) {}
                        i++;
                        if (i % 10 == 0) log("heartbeat alive");
                    }
                }
            });
            hb.setDaemon(true);
            hb.start();

            Looper.loop();   // 保持进程与回调存活
        } catch (Throwable t) {
            log("fatal: " + t);
        }
    }

    private static synchronized void log(String msg) {
        try {
            FileOutputStream fos = new FileOutputStream(logPath, true);
            fos.write((FMT.format(new Date()) + " " + msg + "\n").getBytes("UTF-8"));
            fos.close();
        } catch (Throwable ignored) {
        }
    }

    private static Context getSystemContext() throws Exception {
        Class<?> looper = Class.forName("android.os.Looper");
        looper.getMethod("prepareMainLooper").invoke(null);
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        return (Context) at.getMethod("getSystemContext").invoke(thread);
    }
}
