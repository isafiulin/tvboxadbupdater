#!/system/bin/sh
# Turns a stock A95X_R1_RTL (RK3229, Android 6.0.1, build xfwu.20170222) into the golden /system.
# Run as root on the box from the pushed staging dir:  su -c "sh /data/local/tmp/golden/apply.sh"
# Idempotent: safe to run again on a box that already has it.

SRC=/data/local/tmp/golden
FP_OK="Android/A95X_R1_RTL/A95X_R1_RTL:6.0.1/MXC89L/xfwu02222034:userdebug/test-keys"

fail() { echo "FAIL: $*"; mount -o ro,remount /system 2>/dev/null; exit 1; }

[ "$(id -u)" = "0" ] || fail "not root"
[ "$(getprop ro.build.fingerprint)" = "$FP_OK" ] || fail "unexpected build: $(getprop ro.build.fingerprint)"
[ -f $SRC/app/NeoTV/NeoTV.apk ] || fail "staging dir missing"

mount -o rw,remount /system || fail "remount rw"

echo "== remove bloat"
for d in \
    app/FotaUpdate app/FotaUpdateReboot app/Gmail2 app/eHomeMediaCenter_box app/DeviceTest \
    priv-app/StressTest app/PicoTts app/Gallery2 app/Galaxy4 app/NoiseField app/PhaseBeam \
    app/HoloSpiralWallpaper app/TvLauncher app/QuickSearchBox \
    priv-app/Provision ; do
    [ -e /system/$d ] && rm -rf /system/$d && echo "  removed $d"
done
rm -f /system/pre_app/*.apk
rm -f /system/media/kodi.zip
printf '#!/system/bin/sh\nexit 0\n' > /system/bin/preinstall.sh
chmod 755 /system/bin/preinstall.sh

echo "== install apps"
# True when /system/app/$1 already holds exactly the staged files.
same_app() {
    d=/system/app/$1
    [ -d $d ] || return 1
    [ "$(busybox find $SRC/app/$1 -type f | wc -l)" = "$(busybox find $d -type f | wc -l)" ] || return 1
    for f in $(cd $SRC/app/$1 && busybox find . -type f); do
        busybox cmp -s $SRC/app/$1/$f $d/$f || return 1
    done
    return 0
}
# Toolbox df prints sizes like 243.2M; busybox df can't see mounts on this build.
free_kb() {
    df /system | grep '^/system' | busybox awk '{v=$4; u=substr(v,length(v)); n=substr(v,1,length(v)-1);
        if (u=="G") n*=1048576; else if (u=="M") n*=1024; else if (u=="K") n*=1; else n=v/1024;
        printf "%d\n", n}'
}

for pair in NeoTV:com.neotelecom.tvapp SmartTube:org.smarttube.stable \
            TVBro:com.phlox.tvwebbrowser BoxLauncher:com.box.launcher \
            WebViewGoogle:com.google.android.webview AirScreen:com.ionitech.airscreen; do
    n=${pair%%:*}; pkg=${pair#*:}
    if same_app $n; then echo "  unchanged $n"; continue; fi
    # A running app keeps its deleted files allocated; stop it so rm frees the space.
    am force-stop $pkg >/dev/null 2>&1
    rm -rf /system/app/$n
    sync
    need=$(busybox du -sk $SRC/app/$n | busybox awk '{print $1}')
    have=$(free_kb)
    [ "$have" -gt "$((need + 1024))" ] || fail "no space for $n: need ${need}K, free ${have}K (reboot the box and run again)"
    cp -r $SRC/app/$n /system/app/$n || fail "copy $n"
    chown -R 0:0 /system/app/$n
    find /system/app/$n -type d -exec chmod 755 {} \;
    find /system/app/$n -type f -exec chmod 644 {} \;
    echo "  installed $n"
done

echo "== root certificates"
for f in $SRC/cacerts/*; do
    b=$(basename $f)
    [ -e /system/etc/security/cacerts/$b ] || cp $f /system/etc/security/cacerts/$b
done
chown 0:0 /system/etc/security/cacerts/*
chmod 644 /system/etc/security/cacerts/*
echo "  cacerts now: $(ls /system/etc/security/cacerts | wc -l)"

echo "== defaults"
cp $SRC/etc/box_launcher.conf /system/etc/box_launcher.conf
cp $SRC/etc/box_init.sh /system/etc/box_init.sh
chmod 644 /system/etc/box_launcher.conf
chmod 755 /system/etc/box_init.sh
if ! grep -q box_init.sh /system/bin/install-recovery.sh; then
    echo '/system/bin/sh /system/etc/box_init.sh &' >> /system/bin/install-recovery.sh
fi
sed -i 's/^ro.product.locale=.*/ro.product.locale=ru-RU/' /system/build.prop
sed -i 's/^persist.sys.timezone=.*/persist.sys.timezone=Asia\/Almaty/' /system/build.prop
grep -q '^ro.box.golden=' /system/build.prop || echo 'ro.box.golden=1' >> /system/build.prop

sync
mount -o ro,remount /system
echo "== free: $(df /system | tail -1)"
echo "DONE"
