#!/system/bin/sh
# Box defaults, run as root on every boot from /system/bin/install-recovery.sh.
# Network time is enforced on every boot; the rest is applied once per factory reset.

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
sleep 3

# The vendor Provision app (Kodi pre-installer) is removed from this image,
# so mark setup as finished here; otherwise HOME and the status bar stay locked.
settings put global device_provisioned 1
settings put secure user_setup_complete 1

settings put global auto_time 1
settings put global ntp_server kz.pool.ntp.org

[ -z "$(getprop persist.sys.timezone)" ] && setprop persist.sys.timezone Asia/Almaty

MARK=/data/local/box_init_done
if [ ! -e $MARK ]; then
    settings put global window_animation_scale 0.5
    settings put global transition_animation_scale 0.5
    settings put global animator_duration_scale 0.5
    settings put global auto_time_zone 0
    settings put secure install_non_market_apps 1
    touch $MARK
    log -t box_init "first-boot defaults applied"
fi
log -t box_init "boot defaults applied"
