# shellcheck shell=ash
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
rm -f "$MODDIR/.bootcount"
