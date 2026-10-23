package dualnet;

import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;

import java.io.FileOutputStream;
import java.lang.reflect.Method;

/**
 * 导出单个应用图标为 PNG。
 * 用法: app_process -Djava.class.path=label.dex /system/bin dualnet.DumpIcon <pkg> <outPng>
 */
public class DumpIcon {
    private static final int SIZE = 96;

    public static void main(String[] args) {
        if (args.length < 2) {
            System.out.println("usage: DumpIcon <pkg> <outPng>");
            return;
        }
        String pkg = args[0];
        String out = args[1];
        FileOutputStream fos = null;
        try {
            Context ctx = getSystemContext();
            PackageManager pm = ctx.getPackageManager();
            Drawable d = pm.getApplicationIcon(pkg);

            Bitmap bmp = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bmp);
            d.setBounds(0, 0, SIZE, SIZE);
            d.draw(canvas);

            fos = new FileOutputStream(out);
            bmp.compress(Bitmap.CompressFormat.PNG, 100, fos);
            bmp.recycle();
            System.out.println("ok");
        } catch (Throwable t) {
            System.out.println("err " + t);
        } finally {
            if (fos != null) try { fos.close(); } catch (Throwable ignored) {}
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
