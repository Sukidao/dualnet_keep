package dualnet;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.util.Base64;

import java.io.BufferedWriter;
import java.io.ByteArrayOutputStream;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.lang.reflect.Method;
import java.util.List;

/**
 * 导出应用图标（webp + base64），每行 pkg|base64
 * 用法: app_process -Djava.class.path=label.dex /system/bin dualnet.DumpIcons <outFile>
 */
public class DumpIcons {
    private static final int SIZE = 48;

    public static void main(String[] args) {
        String out = args.length > 0 ? args[0] : "/data/local/tmp/icons.txt";
        BufferedWriter bw = null;
        try {
            Context ctx = getSystemContext();
            PackageManager pm = ctx.getPackageManager();
            List<ApplicationInfo> apps = pm.getInstalledApplications(0);
            bw = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(out), "UTF-8"));

            Bitmap.CompressFormat fmt = Bitmap.CompressFormat.WEBP_LOSSY;

            for (ApplicationInfo ai : apps) {
                try {
                    // 只导出第三方应用，与 WebUI 列表范围一致
                    int sysFlags = ApplicationInfo.FLAG_SYSTEM | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP;
                    if ((ai.flags & sysFlags) != 0) continue;

                    Drawable d = pm.getApplicationIcon(ai);
                    Bitmap bmp = toBitmap(d, SIZE);
                    if (bmp == null) continue;
                    ByteArrayOutputStream bos = new ByteArrayOutputStream();
                    bmp.compress(fmt, 80, bos);
                    String b64 = Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP);
                    bw.write(ai.packageName + "|" + b64);
                    bw.newLine();
                    bmp.recycle();
                } catch (Throwable ignored) {
                }
            }
        } catch (Throwable t) {
            if (bw != null) {
                try { bw.write("__error__|" + t + "\n"); } catch (Throwable ignored) {}
            }
        } finally {
            if (bw != null) {
                try { bw.close(); } catch (Throwable ignored) {}
            }
        }
    }

    private static Bitmap toBitmap(Drawable d, int size) {
        try {
            Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bmp);
            d.setBounds(0, 0, size, size);
            d.draw(canvas);
            return bmp;
        } catch (Throwable t) {
            return null;
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
