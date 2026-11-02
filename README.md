# tmux-config

My tmux configuration, built on top of [Oh my tmux!](https://github.com/gpakosz/.tmux)
by Gregory Pakosz. It adds a system monitor to the status line: CPU, memory,
network throughput, disk usage and battery, refreshed every 2 seconds at almost
no CPU cost. When the active pane is an SSH session, the status line shows the
**remote server's** metrics instead, with nothing to install on the server.

```
Local pane:
↑ ◼◼◼◼  93% | CPU ◼◻◻◻◻  14% | MEM ◼◼◻◻◻  44% 13.8/31G | WiFi ↓    1K ↑    1K | DISK  93% (  32G free) | 15:17 | 02 Nov  me    laptop

Pane running `ssh deploy@web-01`:
↑ ◼◼◼◼  93% | CPU ◼◼◼◻◻  58% | MEM ◼◼◼◼◻  81% 12.9/16G | NET  ↓  2.4M ↑  310K | DISK  47% (  52G free) | 15:17 | 02 Nov  deploy  web-01
```

## Features

| Segment | Shows | Width |
| --- | --- | --- |
| **Battery** | local battery: charging ↑ / discharging ↓, 4-block bar, charge % | fixed |
| **CPU** | 5-block bar + usage %, sampled over the refresh interval | fixed |
| **MEM** | 5-block bar + used % + used/total GiB (`MemTotal - MemAvailable`) | fixed |
| **WiFi** / **NET** | download ↓ and upload ↑ rate: local WiFi interface, or the remote default-route interface | fixed |
| **DISK** | usage % and free space of `/` | fixed |
| **user / host** | who and where the metrics come from | |

- Bars use the Oh my tmux! `gradient` palette. CPU and memory use it reversed
  (green near 0%, red near 100%), while the battery keeps the original
  direction (red when empty, green when full).
- The percentage takes the color of the last filled block, like the battery
  in Oh my tmux!.
- Every value is padded to a fixed width, so the status line does not shift
  when numbers change.

## Remote metrics over SSH

When the foreground process of the active pane is `ssh`, run directly or
under a wrapper such as `sshpass` or `autossh`, the collector:

1. reads the ssh command line from `/proc` and keeps only its connection
   options (`-p`, `-l`, `-i`, `-J`, `-F`, `-o`, `-S`, ...); forwarding, tty
   and remote command arguments are dropped;
2. opens its own background connection with those options, plus
   `BatchMode=yes` (never prompts), `ControlMaster=no` (reuses an existing
   multiplexed connection but never becomes the master),
   `ClearAllForwardings=yes` and `RemoteCommand=none`;
3. streams [`libexec/remote-stats.sh`](libexec/remote-stats.sh) to `sh -s`
   on the server. It is a single `awk` loop that reads `/proc` and prints one
   line per interval. Nothing is installed or written on the server, and the
   loop exits by itself as soon as the connection closes.

The connection stays open for 2 minutes after the pane stops being active
(`TMUX_SYSSTAT_REMOTE_GRACE`), so switching back is instant. It closes right
away when the pane's ssh session ends.

| State | Status line |
| --- | --- |
| connecting (first ~2 s) | `NET   connecting...` and the destination host |
| key/agent auth not possible | `NET   ssh failed` (retried every 30 s) |
| non-Linux server | `NET   unsupported` |

Requirements on the server: Linux, POSIX `sh` and `awk`. Tested with
dash + mawk (Debian/Ubuntu) and BusyBox (Alpine).

**Password logins.** The background connection never asks for a password,
so it needs key or agent authentication. If you log in with a password, turn
on SSH connection sharing in `~/.ssh/config`. Your interactive session then
becomes the master, and the collector rides on it without authenticating
again:

```
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm-%C
    ControlPersist 10m
```

Limitations: only the first hop is seen (an ssh started *inside* the remote
session is not followed), `mosh` is not detected, and with several clients
attached to different sessions the status line follows the most recently
used client.

## Performance

tmux re-runs `#(...)` status jobs whenever it redraws the status line, not only
once per `status-interval`. A status line made of shell jobs (the usual way to
show CPU/memory/network, and how Oh my tmux! renders the battery, user name
and hostname) can therefore spawn processes nonstop.

Instead, everything comes from a single background collector,
[`bin/tmux-sysstat`](bin/tmux-sysstat). It samples `/proc` and `/sys` with
bash builtins only and publishes the results as tmux user options
(`#{@sys_cpu}`, `#{@sys_mem}`, ...). The status line just reads variables and
never forks.

Measured on a 20-core laptop with `status-interval 2`, as CPU time of one core:

| Setup | CPU |
| --- | --- |
| Stats as `#()` shell jobs + Oh my tmux! battery/user/hostname jobs | ~16% |
| This configuration, local pane (collector + plain variables) | **~0.8%** |
| Remote mode: collector + background ssh, local side | ~0.6% |
| Remote mode: `awk` loop, server side | ~0.3% |

Each cycle the collector forks exactly one `tmux` client, which both publishes
the values and reports the active pane. `df` runs every 30 seconds only. A
lock file keeps one collector per tmux server, and it exits by itself (closing
any remote connection) when the server goes away.

## Requirements

- Linux (reads `/proc` and `/sys`)
- tmux (tested with 3.2a)
- bash >= 5.0
- `flock` (util-linux), `git`
- OpenSSH client, for remote metrics
- [Oh my tmux!](https://github.com/gpakosz/.tmux) (cloned by the installer if missing)

## Installation

```sh
git clone https://github.com/NelsonPrates/tmux-config.git ~/tmux-config
~/tmux-config/install.sh
```

The installer:

1. clones Oh my tmux! into `~/.tmux` and links `~/.tmux.conf`, if not already there;
2. links `~/.tmux.conf.local` to `tmux.conf.local` from this repository;
3. links `~/.local/bin/tmux-sysstat` to `bin/tmux-sysstat`, which finds
   `libexec/remote-stats.sh` through the link;
4. reloads tmux if it is running.

Existing files are moved to `<file>.bak-<timestamp>` before being replaced.
Because the installed files are symlinks, edits to your live config end up in
this repository, ready to commit.

## Configuration

All settings live in [`tmux.conf.local`](tmux.conf.local), following the
Oh my tmux! conventions. The main changes from the upstream template are:

- `tmux_conf_theme_status_right`: the battery / CPU / MEM / network / DISK
  segments, with `#{@sys_user}` and `#{@sys_host}` instead of the Oh my tmux!
  `#{username}` and `#{hostname}` jobs;
- `tmux_conf_battery_bar_length="4"`;
- `set -g status-interval 2`;
- `run -b 'exec ~/.local/bin/tmux-sysstat'` to start the collector.

Environment variables read by the collector:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TMUX_SYSSTAT_INTERVAL` | `2` | refresh interval in seconds; keep it in sync with `status-interval` |
| `TMUX_SYSSTAT_REMOTE_GRACE` | `120` | seconds to keep a remote connection open after its pane stops being active |

Debug logs are written to `$XDG_RUNTIME_DIR/tmux-sysstat/`: one
`<socket>.log` per tmux server and one `<ssh-pid>.err` per remote connection,
holding ssh's own error message.

### Trade-offs

User and host follow SSH sessions, but not `sudo`/`su` inside a pane. The
Oh my tmux! root indicator (`!`) is not shown.

## Uninstall

Remove the symlinks and restore any backup made by the installer:

```sh
rm ~/.tmux.conf.local ~/.local/bin/tmux-sysstat
# optionally restore: mv ~/.tmux.conf.local.bak-<timestamp> ~/.tmux.conf.local
tmux kill-server   # or: pkill -f 'bin/tmux-sysstat' && tmux source ~/.tmux.conf
```

## Credits

- [Oh my tmux!](https://github.com/gpakosz/.tmux) by Gregory Pakosz: the base
  configuration, theme, bar symbols and color palette this repository builds on.

## License

[MIT](LICENSE). `tmux.conf.local` is derived from the Oh my tmux! template
(Copyright 2012— Gregory Pakosz, dual licensed WTFPL v2 / MIT, used here under
MIT). See [LICENSE](LICENSE) for both notices.
