package com.vpnapp.vpn;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import androidx.core.app.NotificationCompat;

public class TunVpnService extends VpnService {

    private static final String TAG = "TunVpnService";
    private static final String CHANNEL_ID = "vpn_service_channel";
    private static final int NOTIFICATION_ID = 1;

    public static final String ACTION_START = "com.vpnapp.vpn.START";
    public static final String ACTION_STOP = "com.vpnapp.vpn.STOP";
    public static final String EXTRA_PROXY_URL = "proxy_url";

    private ParcelFileDescriptor tunInterface;
    private volatile boolean isRunning = false;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;

        final String action = intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopVpn();
            return START_NOT_STICKY;
        }

        if (ACTION_START.equals(action)) {
            final String proxyUrl = intent.getStringExtra(EXTRA_PROXY_URL);
            startVpn(proxyUrl);
        }

        return START_STICKY;
    }

    private void startVpn(String proxyUrl) {
        startForeground(NOTIFICATION_ID, buildNotification("VPN connecting..."));

        try {
            // Build TUN interface
            final Builder builder = new Builder();
            builder.setSession("VpnApp");
            builder.addAddress("10.0.0.2", 24);
            builder.addRoute("0.0.0.0", 0);
            builder.addDnsServer("1.1.1.1");
            builder.addDnsServer("8.8.8.8");
            builder.setMtu(1500);

            tunInterface = builder.establish();
            if (tunInterface == null) {
                Log.e(TAG, "Failed to create TUN interface");
                stopSelf();
                return;
            }

            isRunning = true;
            Log.i(TAG, "TUN interface created, fd=" + tunInterface.getFd());

            // TODO: Start tun2socks native library here
            // The native library (libtun2socks.so) should be integrated to forward
            // packets from the TUN fd to the SOCKS5 proxy URL.
            // Example: Tun2Socks.start(tunInterface.getFd(), proxyUrl);

            updateNotification("VPN connected via " + proxyUrl);

        } catch (Exception e) {
            Log.e(TAG, "Failed to start VPN", e);
            stopSelf();
        }
    }

    private void stopVpn() {
        isRunning = false;
        try {
            if (tunInterface != null) {
                tunInterface.close();
                tunInterface = null;
            }
        } catch (Exception e) {
            Log.e(TAG, "Error closing TUN interface", e);
        }
        stopForeground(true);
        stopSelf();
    }

    @Override
    public void onDestroy() {
        stopVpn();
        super.onDestroy();
    }

    private Notification buildNotification(String text) {
        createNotificationChannel();
        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("VPN App")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setOngoing(true)
                .build();
    }

    private void updateNotification(String text) {
        final NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) {
            nm.notify(NOTIFICATION_ID, buildNotification(text));
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            final NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "VPN Service",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("VPN connection status");
            final NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.createNotificationChannel(channel);
            }
        }
    }
}
