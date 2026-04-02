# Android Native Libraries

Place the `libtun2socks.so` native libraries in the appropriate ABI subdirectories:

## Required

| Directory | Architecture | Download |
|-----------|-------------|---------|
| `arm64-v8a/` | ARM 64-bit (most modern Android) | See below |
| `armeabi-v7a/` | ARM 32-bit (older Android) | See below |
| `x86_64/` | x86 64-bit (emulators) | See below |

## How to get libtun2socks.so

1. Download from: https://github.com/xjasonlyu/tun2socks/releases
   - Look for Android build artifacts, or
   - Build from source:
     ```bash
     git clone https://github.com/xjasonlyu/tun2socks.git
     cd tun2socks
     # Build for Android ARM64
     CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
       CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang \
       go build -buildmode=c-shared -o libtun2socks.so ./...
     ```

2. Place the compiled `.so` file in the matching ABI directory.

## Notes

- Without `libtun2socks.so`, the Android VPN will establish the TUN interface
  but will not forward traffic to the SOCKS5 proxy.
- The `TunVpnService.java` contains a placeholder comment where the native
  library should be invoked.
