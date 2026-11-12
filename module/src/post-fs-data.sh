#!/system/bin/sh

DEBUG=@DEBUG@

if [ "$DEBUG" = true ]; then
set -e
fi

MODDIR=${0%/*}

# INFO: KernelSU 3.3.x applies every module's sepolicy.rule from a single batch during its module
#         stage, and that batch only partially succeeds ("apply sepolicy batch partially succeeded:
#         39/86", `Type(zygisk_file) failed: Invalid argument (os error 22)`), so the types declared
#         here are never created. zygote then cannot open /data/adb nor connect to the control
#         socket (-EACCES) and no Zygisk module is injected. Replaying the exact same file from
#         post-fs-data succeeds instead, so do it here before anything gets started.
if command -v ksud >/dev/null 2>&1 && [ -f "$MODDIR/sepolicy.rule" ]; then
  log -p i -t "zygisk-sh" "KernelSU: re-applying sepolicy.rule, its boot-time batch is only partial on KSU 3.3.x"
  ksud sepolicy apply "$MODDIR/sepolicy.rule" >/dev/null 2>&1 || true
fi

if [ "$ZYGISK_ENABLED" ]; then
  exit 0
fi

cd "$MODDIR"

rm -f /data/adb/treat_wheel/status

if [ "$(which magisk)" ]; then
  for file in ../*; do
    if [ -d "$file" ] && [ -d "$file/zygisk" ] && ! [ -f "$file/disable" ]; then
      if [ -f "$file/post-fs-data.sh" ]; then
        cd "$file"
        log -p i -t "zygisk-sh" "Manually trigger post-fs-data.sh for $file"
        sh "$(realpath ./post-fs-data.sh)"
        cd "$MODDIR"
      fi
    fi
  done
fi

create_sys_perm() {
  mkdir -p "$1"
  chmod 555 "$1"
  chcon u:object_r:system_file:s0 "$1"
}

export TMP_PATH=/data/adb/rezygisk
rm -rf "$TMP_PATH"

create_sys_perm $TMP_PATH

sh /data/adb/post-fs-data.d/rezygisk.sh

# INFO: Utilize the one with the biggest output, as some devices with Tango have the full list
#         in ro.product.cpu.abilist but others only have a subset there, and the full list in
#         ro.system.product.cpu.abilist
CPU_ABIS_PROP1=$(getprop ro.system.product.cpu.abilist)
CPU_ABIS_PROP2=$(getprop ro.product.cpu.abilist)

if [ "${#CPU_ABIS_PROP2}" -gt "${#CPU_ABIS_PROP1}" ]; then
  CPU_ABIS=$CPU_ABIS_PROP2
else
  CPU_ABIS=$CPU_ABIS_PROP1
fi

if [[ "$CPU_ABIS" == *"arm64-v8a"* || "$CPU_ABIS" == *"x86_64"* ]]; then
  ./bin/zygisk-ptrace64 monitor &
else
  # INFO: Device is 32-bit only

  ./bin/zygisk-ptrace32 monitor &
fi

exit 0
