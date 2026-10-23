package dualnet;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;

import java.io.BufferedReader;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.lang.reflect.Method;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 分别通过 WiFi / 蜂窝网络请求外部服务，得到各自的出口公网 IPv4。
 * 用法: app_process -Djava.class.path=label.dex /system/bin dualnet.PublicIp <outFile>
 * 输出: wifi=1.2.3.4 / mobile=5.6.7.8
 */
public class PublicIp {
    private static final String[] HOSTS = {"ip.3322.net", "myip.ipip.net", "ip.3322.org"};
    private static final Pattern IPV4 = Pattern.compile("\\b((?:\\d{1,3}\\.){3}\\d{1,3})\\b");

    public static void main(String[] args) {
        String out = args.length > 0 ? args[0] : "/data/local/tmp/publicip.txt";
        StringBuilder sb = new StringBuilder();
        try {
            Context ctx = getSystemContext();
            ConnectivityManager cm = (ConnectivityManager) ctx.getSystemService(Context.CONNECTIVITY_SERVICE);
            Network[] nets = cm.getAllNetworks();

            String wifiIp = query(cm, nets, NetworkCapabilities.TRANSPORT_WIFI);
            String cellIp = query(cm, nets, NetworkCapabilities.TRANSPORT_CELLULAR);

            sb.append("wifi=").append(wifiIp == null ? "-" : wifiIp).append('\n');
            sb.append("mobile=").append(cellIp == null ? "-" : cellIp).append('\n');
        } catch (Throwable t) {
            sb.append("wifi=-\nmobile=-\nerror=").append(t.toString().replace('\n', ' ')).append('\n');
        }
        try {
            FileOutputStream fos = new FileOutputStream(out);
            fos.write(sb.toString().getBytes("UTF-8"));
            fos.close();
        } catch (Throwable ignored) {
        }
    }

    private static String query(ConnectivityManager cm, Network[] nets, int transport) {
        for (Network n : nets) {
            NetworkCapabilities nc = cm.getNetworkCapabilities(n);
            if (nc == null) continue;
            if (!nc.hasTransport(transport)) continue;
            if (!nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue;
            for (String host : HOSTS) {
                String ip = fetch(n, host);
                if (ip != null) return ip;
            }
        }
        return null;
    }

    private static String fetch(Network n, String host) {
        Socket s = null;
        try {
            InetAddress addr = InetAddress.getByName(host);
            s = n.getSocketFactory().createSocket();
            s.connect(new InetSocketAddress(addr, 80), 4000);
            s.setSoTimeout(4000);

            OutputStream os = s.getOutputStream();
            String req = "GET / HTTP/1.1\r\nHost: " + host
                    + "\r\nUser-Agent: dualnet\r\nAccept: */*\r\nConnection: close\r\n\r\n";
            os.write(req.getBytes("ISO-8859-1"));
            os.flush();

            BufferedReader br = new BufferedReader(new InputStreamReader(s.getInputStream(), "ISO-8859-1"));
            String line;
            while ((line = br.readLine()) != null) {
                if (line.length() == 0) break;
            }
            StringBuilder body = new StringBuilder();
            while ((line = br.readLine()) != null) body.append(line).append('\n');

            Matcher m = IPV4.matcher(body.toString());
            while (m.find()) {
                String ip = m.group(1);
                if (isPublic(ip)) return ip;
            }
        } catch (Throwable ignored) {
        } finally {
            if (s != null) try { s.close(); } catch (Throwable ignored) {}
        }
        return null;
    }

    private static boolean isPublic(String ip) {
        String[] p = ip.split("\\.");
        int a = Integer.parseInt(p[0]);
        int b = Integer.parseInt(p[1]);
        if (a == 10 || a == 127) return false;
        if (a == 192 && b == 168) return false;
        if (a == 172 && b >= 16 && b <= 31) return false;
        if (a == 169 && b == 254) return false;
        if (a == 100 && b >= 64 && b <= 127) return false;
        if (a == 0 || a >= 224) return false;
        return true;
    }

    private static Context getSystemContext() throws Exception {
        Class<?> looper = Class.forName("android.os.Looper");
        looper.getMethod("prepareMainLooper").invoke(null);
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        return (Context) at.getMethod("getSystemContext").invoke(thread);
    }
}
