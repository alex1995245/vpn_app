# Download Required Binaries

Place the following binaries in this directory before building for Windows:

## 1. tun2socks.exe

Download from: https://github.com/xjasonlyu/tun2socks/releases

- Download `tun2socks-windows-amd64.zip`
- Extract `tun2socks.exe` to this folder (`assets/bin/windows/tun2socks.exe`)

## 2. wintun.dll

Download from: https://www.wintun.net/

- Download the latest `wintun-X.XX.zip`
- Extract `wintun/bin/amd64/wintun.dll` to this folder (`assets/bin/windows/wintun.dll`)

## Notes

- Both files must be present for the Windows VPN to work
- The app requires Administrator privileges on Windows to create TUN interfaces and modify routes
- Run the app as Administrator (right-click → Run as Administrator)
