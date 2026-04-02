package com.vpnapp.vpn;

import android.content.Intent;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.vpnapp/vpn";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "connect": {
                            String proxyUrl = call.argument("proxyUrl");
                            Intent intent = new Intent(this, TunVpnService.class);
                            intent.setAction(TunVpnService.ACTION_START);
                            intent.putExtra(TunVpnService.EXTRA_PROXY_URL, proxyUrl);
                            startService(intent);
                            result.success(true);
                            break;
                        }
                        case "disconnect": {
                            Intent intent = new Intent(this, TunVpnService.class);
                            intent.setAction(TunVpnService.ACTION_STOP);
                            startService(intent);
                            result.success(null);
                            break;
                        }
                        default:
                            result.notImplemented();
                    }
                });
    }
}
