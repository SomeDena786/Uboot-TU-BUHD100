#!/system/bin/sh
log -t PIXBOOT "eth0: waiting for PHY..."
sleep 13
ip link set eth0 up
sleep 2
# dhclient uses BIND library which fails to create sockets on this kernel.
# dhcpcd works without BIND; fall back to dhclient only if dhcpcd is absent.
if [ -x /system/bin/dhcpcd ]; then
    /system/bin/dhcpcd -t 30 eth0
else
    /system/bin/dhclient -v -1 -cf /dhclient.conf \
        -sf /system/bin/dhclient-script eth0
fi
IP=$(ip -4 addr show eth0 2>/dev/null | grep 'inet ' | head -1 \
    | sed 's/.*inet \([0-9.]*\)\/.*/\1/')
[ -n "$IP" ] && log -t PIXDBG "*** ADB: adb connect $IP:5555 ***"
