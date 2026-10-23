package dualnet;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Looper;

import java.io.FileOutputStream;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * 用 NotificationManager 发布/更新常驻通知。
 * 用法: app_process -Djava.class.path=label.dex /system/bin dualnet.Notify <title> <text> [logFile]
 */
public class Notify {
    private static final String CHANNEL_ID = "dualnet_status";
    private static final int NOTIFY_ID = 20251023;

    public static void main(String[] args) {
        String title = args.length > 0 ? args[0] : "双网络守护";
        String text = args.length > 1 ? args[1] : "";
        String logPath = args.length > 2 ? args[2] : "/data/adb/dualnet/notify.log";

        try {
            Context ctx = getSystemContext();
            NotificationManager nm =
                    (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);

            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID, "双网络状态", NotificationManager.IMPORTANCE_LOW);
            ch.setShowBadge(false);
            ch.enableVibration(false);
            ch.setSound(null, null);
            nm.createNotificationChannel(ch);

            Notification.Builder b = new Notification.Builder(ctx, CHANNEL_ID)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                    .setShowWhen(false);

            nm.notify("dualnet", NOTIFY_ID, b.build());
            log(logPath, "ok: " + title + " | " + text);
        } catch (Throwable t) {
            log(logPath, "FAIL: " + t);
        }
    }

    private static synchronized void log(String path, String msg) {
        try {
            String ts = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(new Date());
            FileOutputStream fos = new FileOutputStream(path, true);
            fos.write((ts + " " + msg + "\n").getBytes("UTF-8"));
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
