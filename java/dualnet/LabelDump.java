package dualnet;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;

import java.io.BufferedWriter;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.lang.reflect.Method;
import java.util.List;

/**
 * 通过 app_process 运行，导出 包名|应用名|uid
 * 用法: app_process -Djava.class.path=label.dex /system/bin dualnet.LabelDump <outFile>
 */
public class LabelDump {
    public static void main(String[] args) {
        String outPath = args.length > 0 ? args[0] : "/data/local/tmp/labels.txt";
        BufferedWriter bw = null;
        try {
            Context ctx = getSystemContext();
            PackageManager pm = ctx.getPackageManager();

            List<ApplicationInfo> apps = pm.getInstalledApplications(PackageManager.GET_META_DATA);
            bw = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(outPath), "UTF-8"));
            for (ApplicationInfo ai : apps) {
                CharSequence label;
                try {
                    label = pm.getApplicationLabel(ai);
                } catch (Throwable t) {
                    label = null;
                }
                if (label == null || label.length() == 0) {
                    label = ai.packageName;
                }
                String s = label.toString().replace('|', '/').replace('\n', ' ').replace('\r', ' ');
                bw.write(ai.packageName + "|" + s + "|" + ai.uid);
                bw.newLine();
            }
        } catch (Throwable t) {
            t.printStackTrace();
            if (bw != null) {
                try { bw.write("__error__|" + t + "|0"); bw.newLine(); } catch (Throwable ignored) {}
            } else {
                try {
                    BufferedWriter eb = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(outPath), "UTF-8"));
                    eb.write("__error__|" + t + "|0");
                    eb.newLine();
                    eb.close();
                } catch (Throwable ignored) {}
            }
        } finally {
            if (bw != null) {
                try { bw.close(); } catch (Throwable ignored) {}
            }
        }
    }

    private static Context getSystemContext() throws Exception {
        Class<?> looper = Class.forName("android.os.Looper");
        looper.getMethod("prepareMainLooper").invoke(null);

        Class<?> at = Class.forName("android.app.ActivityThread");
        Method systemMain = at.getMethod("systemMain");
        Object thread = systemMain.invoke(null);
        Method getSystemContext = at.getMethod("getSystemContext");
        return (Context) getSystemContext.invoke(thread);
    }
}
