# tmux-config

My tmux configuration, built on top of [Oh my tmux!](https://github.com/gpakosz/.tmux)
by Gregory Pakosz. It adds a system monitor to the status line: CPU, memory,
WiFi throughput, disk usage and battery, refreshed every 2 seconds at almost no
CPU cost.

```
CPU ◼◻◻◻◻  14% | MEM ◼◼◻◻◻  44% 13.8/31G | WiFi ↓    1K ↑    1K | DISK  93% (  32G free) | ↑ ◼◼◼◼  93% | 15:17 | 02 Nov  user  hostname
```

## Features

| Segment | Shows | Width |
| --- | --- | --- |
| **CPU** | 5-block bar + usage %, sampled over the refresh interval | fixed |
| **MEM** | 5-block bar + used % + used/total GiB (`MemTotal - MemAvailable`) | fixed |
| **WiFi** | download ↓ and upload ↑ rate of the wireless interface (auto-detected) | fixed |
| **DISK** | usage % and free space of `/` | fixed |
| **Battery** | charging ↑ / discharging ↓, 4-block bar, charge % | fixed |

- Bars use the Oh my tmux! `gradient` palette. CPU and memory use it reversed
  (green near 0%, red near 100%), while the battery keeps the original
  direction (red when empty, green when full).
- The percentage takes the color of the last filled block, like the battery
  in Oh my tmux!.
- Every value is padded to a fixed width, so the status line does not shift
  when numbers change.

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
| This configuration (collector + plain variables) | **~0.8%** |

Each cycle the collector forks exactly one `tmux` client. `df` runs every
30 seconds only. A lock file keeps one collector per tmux server, and it exits
by itself when the server goes away.

## Requirements

- Linux (reads `/proc` and `/sys`)
- tmux (tested with 3.2a)
- bash >= 5.0
- `flock` (util-linux), `git`
- [Oh my tmux!](https://github.com/gpakosz/.tmux) (cloned by the installer if missing)

## Installation

```sh
git clone https://github.com/NelsonPrates/tmux-config.git ~/tmux-config
~/tmux-config/install.sh
```

The installer:

1. clones Oh my tmux! into `~/.tmux` and links `~/.tmux.conf`, if not already there;
2. links `~/.tmux.conf.local` to `tmux.conf.local` from this repository;
3. links `~/.local/bin/tmux-sysstat` to `bin/tmux-sysstat`;
4. reloads tmux if it is running.

Existing files are moved to `<file>.bak-<timestamp>` before being replaced.
Because the installed files are symlinks, edits to your live config end up in
this repository, ready to commit.

## Configuration

All settings live in [`tmux.conf.local`](tmux.conf.local), following the
Oh my tmux! conventions. The main changes from the upstream template are:

- `tmux_conf_theme_status_right`: the CPU / MEM / WiFi / DISK / battery
  segments, with the user name from `#{@sys_user}` and the hostname from `#h`
  (both job-free);
- `tmux_conf_battery_bar_length="4"`;
- `set -g status-interval 2`;
- `run -b 'exec ~/.local/bin/tmux-sysstat'` to start the collector.

The collector refresh interval can be changed with the
`TMUX_SYSSTAT_INTERVAL` environment variable (in seconds, default `2`). Keep
it in sync with `status-interval`.

### Trade-offs

The user name and hostname are no longer SSH- or `sudo`-aware: they always
show the local user and machine. The Oh my tmux! root indicator (`!`) is not
shown either.

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
