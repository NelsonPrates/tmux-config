# remote-stats.sh - streamed to the remote host over ssh as `sh -s`.
# Prints one line every IV seconds, until the connection goes away:
#   OK <cpu%> <mem_total_kb> <mem_avail_kb> <iface> <rx_B/s> <tx_B/s> <disk%> <disk_avail_kb> <user> <host>
# Needs only POSIX sh + awk (gawk, mawk and busybox awk all work).
# Nothing is installed or left behind on the remote host.
LC_ALL=C; export LC_ALL
IV=${IV:-2}
if [ ! -r /proc/stat ] || [ ! -r /proc/meminfo ]; then echo "ERR unsupported"; exit 0; fi
exec awk -v iv="$IV" -v user="$(id -un 2>/dev/null || echo "${USER:-?}")" -v host="$(uname -n)" '
function ppid(   l, a) {
  # field 4 of /proc/self/stat, skipping "(comm)" which may contain spaces
  if ((getline l < "/proc/self/stat") <= 0) return 0
  close("/proc/self/stat"); sub(/^.*\) /, "", l); split(l, a, " "); return a[2]
}
BEGIN {
  parent = ppid(); n = 0
  while (1) {
    # stop as soon as sshd goes away and we get re-parented
    if (parent && ppid() != parent) exit 0

    getline l < "/proc/uptime"; close("/proc/uptime"); split(l, a, " "); up = a[1] + 0

    getline l < "/proc/stat"; close("/proc/stat"); split(l, a, " ")
    t = 0; for (k = 2; k <= 9; k++) t += a[k]; idle = a[5] + a[6]

    mt = ma = mf = bu = ca = 0
    while ((getline l < "/proc/meminfo") > 0) {
      split(l, a, " ")
      if (a[1] == "MemTotal:") mt = a[2]; else if (a[1] == "MemAvailable:") ma = a[2]
      else if (a[1] == "MemFree:") mf = a[2]; else if (a[1] == "Buffers:") bu = a[2]
      else if (a[1] == "Cached:") ca = a[2]
    }
    close("/proc/meminfo"); if (!ma) ma = mf + bu + ca   # kernels < 3.14

    ifc = ""   # interface of the default route
    while ((getline l < "/proc/net/route") > 0) { split(l, a, " "); if (a[2] == "00000000" && ifc == "") ifc = a[1] }
    close("/proc/net/route")
    rx = tx = 0
    if (ifc != "") {
      while ((getline l < "/proc/net/dev") > 0) { sub(/:/, " ", l); split(l, a, " "); if (a[1] == ifc) { rx = a[2]; tx = a[10] } }
      close("/proc/net/dev")
    }

    if (n % 15 == 0) {   # disk usage changes slowly
      c = "df -kP / 2>/dev/null"; dl = ""
      while ((c | getline l) > 0) dl = l
      close(c); split(dl, a, " "); da = a[4] + 0; dp = a[5]; sub(/%/, "", dp); dp += 0
    }

    if (n > 0) {
      dt = t - pt; cpu = dt > 0 ? int((dt - (idle - pidle)) * 100 / dt) : 0
      el = up - pup; if (el <= 0) el = iv
      rxr = int((rx - prx) / el); txr = int((tx - ptx) / el)
      if (rxr < 0 || ifc != pifc) rxr = 0; if (txr < 0 || ifc != pifc) txr = 0
      printf "OK %d %d %d %s %d %d %d %d %s %s\n", cpu, mt, ma, (ifc == "" ? "-" : ifc), rxr, txr, dp, da, user, host
      fflush()
    }
    pt = t; pidle = idle; pup = up; prx = rx; ptx = tx; pifc = ifc; n++
    system("sleep " (n == 1 ? 1 : iv))
  }
}'
