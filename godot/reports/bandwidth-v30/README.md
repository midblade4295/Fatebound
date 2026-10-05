# Protocol 30 bandwidth reduction — 2026-10-05

The dedicated server sends fewer repeated fields and uses zstd level 9. Existing protocol 30 apps continue to receive 15 snapshots per second with the same positions, combat events, and task progress. The installed server simulation stays unchanged.

## Measured savings

Two deterministic seeds (1337 and 424242), 32 units, 252 simulation seconds, and 3,780 snapshots generated a common fixture corpus using the exact installed simulation. The original protocol decoder applied the baseline and candidate streams to independent mirrors. Every compared unit field, world field, and event matched.

| Codec / server compression | Download payload MB/hour | Average encode per packet | Typical 32-recipient broadcast |
|---|---:|---:|---:|
| Installed codec / level 3 | 54.04 | 177 µs | 2.59 ms |
| Candidate / level 3 | 47.84 | 102 µs | 0.40 ms |
| Candidate / level 9 (selected) | 45.66 | 414 µs | 1.33 ms |
| Candidate / level 12 | 44.65 | 814 µs | 2.35 ms |
| Candidate / level 15 | 43.43 | 1,521 µs | 4.19 ms |
| Candidate / level 19 | 43.13 | 2,934 µs | 7.83 ms |

Level 9 saves **15.51%** of downloads against the installed codec at level 3. Typical broadcast samples had 1.79 private tasks on average. With all 32 recipients on private tasks, level 9 averaged 11.67 ms per broadcast and peaked at 23.38 ms across 63 samples; level 12 peaked at 52.93 ms and level 15 at 86.82 ms. The snapshot interval is 66.67 ms. These are elapsed timings under shared host load, not process CPU counters or a full concurrent-user load test.

The earlier 60-second live probe measured 65.29 MB/hour received and 10.15 MB/hour sent with synthetic 20 Hz inputs. Applying the controlled download ratio estimates **55.16 MB/hour received + 10.15 sent = 65.31 combined**, versus 75.44 before. This is a projection, not a post-deployment measurement. Traffic depends on match activity and client inputs. All figures use decimal MB and game payload bytes; WebSocket framing, TLS, TCP, and IP overhead are excluded. No physical Android device was measured.

Raw measurements are in [benchmark.json](benchmark.json).

## Compatibility changes

- Unchanged score, kills, and Oracle state travel only when dirty, with full refreshes every four seconds. Existing clients retain omitted values.
- Every joining player receives a full snapshot immediately. A unicast never consumes changes owed to the next shared broadcast.
- Empty events, default match-end values, and empty private task dictionaries are omitted. Active tasks and nondefault match-end values remain present.
- The whirlwind timer becomes its already-quantized active/inactive flag; the original decoder only consumes that flag.
- One compressed snapshot is reused for players without a private task. Players with private tasks receive individually encoded packets.
- Projectile and item arrays remain present, including empty arrays, so old clients clear vanished entities.

Compression is configured through the dedicated server's startup override. Mobile input compression and cadence are unchanged. Full installations also copy this setting into their minimal server project.

## Validation

- 3,780 snapshots and all five compression levels: zero compatibility/serialization differences.
- Explicit tests: dirty state during a late join, full joins, private task progress and clearing, match ending and reset, projectile/item clearing, and whirlwind rounding boundaries.
- Real isolated server on 127.0.0.1:18082 at level 9: two original-codec clients joined, decoded/applied 28 and 20 snapshots, and disconnected cleanly.
- Fast committed regression: two seeds, 240 snapshots, zero differences on both the installed simulation and the Play-branch simulation.
- Patched `parse_all`, `net_interp_test`, and real `siege_net_smoke` passed.
- Rootless full installer on isolated port 18084 passed `PROBE_OK` and retained the selected config. Shell syntax checks and the read-only narrow-update preflight passed.
- Existing 22-test quick suite: 21 patched-source checks passed; the unmodified simulation test reproduced the previously documented zero-rescue failure for seeds 11/22 before applying changes. The suite therefore returned failure solely for that baseline issue. The new bandwidth regression passed separately; no simulation code was changed.

Run the new regression from the repository root:

```bash
/opt/godot-4.7.2/godot --headless --path godot -s res://tests/siege_bandwidth_test.gd
```

The standard quick runner now includes this regression. The legacy codec in `tests/fixtures/siege_net_v30.gd` is test-only. Optional benchmark mode (`SIEGE_BANDWIDTH_BENCH=1 SIEGE_BANDWIDTH_STEPS=3780`) writes its corpus/results into the project directory; run it in an isolated copy.

## Narrow live update

The checked-out Play source is based on 53690c51b42425f5d7ac811440c82b4beb3bb3de. Its original Net and server files exactly match the live protocol-30 files, but its simulation is newer. **Do not run the full installer for this rollout.** The narrow helper updates only the Net script, server script, and dedicated compression override.

The helper requires the exact original Net/server/simulation/project hashes, no existing override, an active Fatebound service, and no established player connections. It backs up the original scripts and project, restarts Fatebound, probes local and public sockets, verifies the simulation and unrelated service PIDs, and restores the prior state on failure. Live deployment is pending administrator access; the connected remote tool blocks `sudo`.

On the server:

```bash
bash /home/midblade4295/fatebound-bandwidth-v30/godot/server/deploy/update_siege_bandwidth.sh --check
sudo bash /home/midblade4295/fatebound-bandwidth-v30/godot/server/deploy/update_siege_bandwidth.sh
```

A successful application prints `BANDWIDTH_DEPLOY_OK` and the backup directory. A post-deployment live bandwidth sample is still needed to replace the projection with measured production traffic.
