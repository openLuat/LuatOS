# UART ARQ2 implementation and bench record

Follow-up WiFi/OTA validation and additional framing/memory fixes are recorded in
[`UART_OTA_TEST_REPORT.md`](UART_OTA_TEST_REPORT.md). That report also records the
later OTA-installed test versions and artifacts; the measurements below describe
the earlier command-transport fixture.

## Wire contract

This branch uses the single UART transport state machine. The independent
two-instance implementation is saved separately on `feat/airlink-dual-instance`.

- Framing, escaping and CRC16 remain compatible with legacy AirLink.
- A UART devinfo command contains the existing `luat_airlink_dev_info_t`, followed
  by 16 bytes: `AL-ARQ2\0` (8 bytes), local boot nonce (LE32), echoed peer nonce
  (LE32). Its command length and frame length include the actual complete data.
- Only an exact extension size/magic and an echoed local nonce enable TX ARQ.
  Seeing a capable peer without the echo pauses data TX until negotiation finishes.
- `devinfo.caps` bit2 is cleared **on the UART wire**, even for ARQ2. The original
  experimental ARQ implementation enabled itself from this bit alone, so setting
  it would break fallback with that implementation. RPC/FRAG bits are preserved.
- Reliable frames use flags bit8=ARQ, bit9=sequence-valid, bits16..31=session tag.
  The nonzero tag is CRC16 of the two sorted LE32 boot nonces (CRC zero maps to 1).
  It is a stale-session discriminator, **not authentication**. Like the existing
  CRC16/16-bit sequence protocol, it does not provide mathematical immunity to
  collisions or frames delayed across an entire sequence-number cycle.
- Old RPC/FRAG bit8/9 flags without a session tag are treated as legacy traffic
  before negotiation. A tagged frame from an unknown/previous session is rejected
  even immediately after reboot, before HELLO arrives. Otherwise an old reset
  retry could reset the freshly booted peer repeatedly.
- Legacy UART devinfo has a known malformed shape: frame payload length 128 and
  command length 128, leaving only 124 command data bytes. Only that devinfo shape
  is clamped; data-command length validation remains strict. The devinfo handler
  copies into a zero-filled bounded snapshot before reading fields.

## Delivery and ownership

- Stop-and-wait, RTO 60 ms, sequence/ACK modulo 65536.
- RX classifies a sequence without advancing it. Successful command admission
  commits the next expected sequence and requests ACK. OOM/full/rejected admission
  leaves the sequence unchanged, so retransmission retries delivery.
- Nonmatching sequences are never arbitrarily adopted. They are discarded and
  the current next-expected ACK is repeated.
- The common accepted-command API queues IP commands too; the XT804 IP path
  returns its actual WiFi TX admission result. ACK means transport acceptance,
  not that an application action or an over-the-air WiFi transmission completed.
- TX alone owns and frees `pending.cmd`. RX publishes ACK/session state under a
  mutex. A matching ACK is checked before the timeout alarm. The 3-second alarm
  reports a stalled link but retains the original pending frame and sequence.
- Peer boot/session changes discard an uncertain old-session pending command
  with explicit drop/giveup counters. There is no durable exactly-once guarantee
  across peer power loss; applications requiring that need persistent IDs/results.
- XT804 producers copy commands into a bounded 32-entry queue; the main-loop TX
  poll owns framing buffers and retransmission. Devinfo has a separate snapshot
  so heartbeats cannot be blocked behind pending data. RX is drained on each poll
  rather than relying on a potentially lost interrupt flag.

## Diagnostic builds

Both platform xmake projects accept process environment `AIRLINK_ARQ_TEST=1`.
Only these builds expose `airlink.arqFault(kind, count, remote)` / `arqState()`
and recognize diagnostic command `0x7ffe` (two bytes: kind/count).

Kinds: 0=drop outgoing data, 1=drop outgoing ACK-only, 2=duplicate outgoing data,
3=reject incoming admission. Budgets are bounded to 100. The admission hook
models an OOM/full rejection; it does not allocate until the real heap is exhausted.
Duplicated writes wait for serialization so the second frame actually reaches RX.
Normal builds do not include these control hooks.

## Bench, 2026-11-03

Evidence root on the test machine:

`C:\Users\ThinkPad\AppData\Local\Temp\opencode\airlink-evidence`

### Saved source and active branches

| Repository | Saved dual-instance branch/commit | ARQ baseline |
|---|---|---|
| LuatOS | `feat/airlink-dual-instance`, `f6b6ac64c` (62 files, including new source/tests/docs) | `airlink_uart_arq`, tracking `origin/feat/airlink_uart_arq` at `60aac60bb` |
| luatos-soc-xt804 | `feat/airlink-dual-instance`, `3e96de5` | `airlink_uart_arq`, based on `18ba9fe` |
| luatos-sdk-ccm42xx-gcc | No dual-instance changes existed to commit; original CAN changes retained | `airlink_uart_arq`, based on `fe4df4a` |

All three origins were fetched before branch selection. At the end of the bench
run, ARQ work was left uncommitted pending separate publication authorization.
No new stash, push, amend, or git-config change was used during that bench run. The pre-existing LuatOS
stash `On fix/soft-uart-duplex-engine: temp-airlink-stdbool` remains untouched.
The two Air8000 demo edits,
CCM CAN edits, and unrelated untracked files were retained.

### Actual hardware / artifacts

- COM8, VID:PID `1a86:55d3`, CH343: hardware reports **Air1602_A10**, not Air1601.
  Before: V1025 (Aug 10), immediate BusFault. After: V1029, firmware type **101**,
  64-bit Lua, UART2 at 2,000,000; log port at 6,000,000 baud.
- COM7, VID:PID `1a86:7523`, CH340: XT804/Air6208, ROM `R:8`, Flash `FID:85,14`
  (1 MiB). The original application's version could not be read before replacing
  it. Rebuilt baseline and new no-VM application both identify as V1002; use the
  archived hashes to distinguish them. Log output is plain UTF-8 at 2,000,000 baud
  with NUL separators, not SOC binary framing.
- `final-ccm/` and `final-xt804/` contain the tested final SOC/ELF/MAP, plus FLS
  for XT804. Each directory has `manifest.json` with SHA256 hashes.
- Reproducible old-protocol baseline: shared `origin/master@ca64b51a9` in detached
  worktree `...\opencode\airlink-legacy-luatos`. Use `legacy-ccm-platform-fixed/`
  and `legacy-xt804/`. This baseline includes the necessary CCM platform fixes
  below; it is not an untouched historical vendor firmware image.

### Build/bring-up issues actually resolved

1. PATH selected a broken bundled xmake. Prepending
   `C:\Users\ThinkPad\AppData\Local\xmake` uses the working installation.
2. CCM `LV_USE_GLTF=0`, but generated GLTF shader source unconditionally included
   absent OpenGL driver headers. Excluded that disabled backend in the BSP build.
   No media feature was disabled. `mp4player/video_decode/yuv_rgb_565.h` exists in
   the current ext repository and the previously reported YUV failure did not recur.
3. Local ignored `luat_fw_type.h` contained `1`, selecting the RAM linker layout
   despite a type-1 flash map: 6,217,280 bytes did not fit its 4.5 MiB region.
   Selected supported firmware type `101` (XIP), retaining the full feature set.
4. XIP erase loop lacked `done_len` advancement: LFS formatting repeatedly erased
   one sector and hit WDT. Matching ELF resolved PC `1421c32e` to the erase loop;
   adding the increment allowed normal boot and formatting.
5. CCM semaphore creation inverted initial count 0/1. Ping returned immediately
   with `ok=false, timeout` rather than waiting. Corrected the API contract and
   changed SPI/I2C completion-semaphore initialization to zero to preserve their
   intended empty state. SPI/I2C peripheral hardware was not separately exercised.
6. Current CCM platform expects `LUAT_ONEWIRE_VIRTUAL_MASK`, missing on the older
   ARQ shared branch. Added a guarded platform fallback (`0x80`).
7. Native `luatos-cli flash run` tried to erase 2 MiB on 1 MiB Air6208 and ROM
   rejected it with `S`. Used CLI `device boot`, then the repository vendor tool
   after reading its help:
   `wm_tool.exe -c COM7 -ds 2000000 -rs rts -eo all -dl <AIR6208.fls>`.
   The earlier failing flash log is retained. CCM CLI flash passed, using its
   automatic uncompressed retry after device-side compressed MD5 mismatch.

### Completed compatibility matrix

All rows validated 30 x 256-byte requests and exact replies including escaped
0x7d/0x7e, NUL and 0xff. Throughput counts both directions' application payload,
measured over wall time; these are short-run measurements, not sustained maxima.

| CCM host / XT804 peer | Result | Payload bytes/s | Evidence file |
|---|---|---:|---|
| old / old | PASS | 8,692 | `matrix-old-old-final.log` |
| old / new | PASS, legacy fallback | 79,585 | `matrix-old-new-2.log` |
| new / old | PASS, state=0, no ARQ retries | 80,000 | `matrix-new-old-final.log` |
| new / new | PASS, ARQ2 state=1 | 64,267 | `matrix-new-new-verified.log` |

The new/new burst additionally completed **128 requests with 16 outstanding at
once**, 65,536 bidirectional payload bytes in **804 ms = 81,512 bytes/s**.

### Fault/recovery evidence

`matrix-new-new-verified.log` and `xt804-new-new-verified.log`:

- Drop three host data frames: all data recovered; host retransmissions +3.
- Drop three peer data frames: complete echo recovered.
- Duplicate data in each direction: exact single response; host duplicate count
  +1 and XT804 explicitly logs the rejected duplicate sequence.
- Reject admission three times on either endpoint: ACK does not advance prematurely,
  complete echo recovered; peer statistics show its retries.
- Drop three peer ACK-only frames: host retransmissions +3, no duplicate execution.
- Drop **45 host data transmissions**: same pending frame survives the 3-second
  alarm, complete echo at **3542 ms**. No timeout fallback to legacy.
- Peer reset: exactly one reset invocation in XT804 log, new boot nonce,
  renegotiation, then successful 256-byte echo. Earlier reset-retry storm logs
  are retained as failing intermediate evidence, not used as the final result.
- Host-only reset was additionally verified in `host-only-reboot-host.log` and
  `host-only-reboot-peer.log`: peer nonce stayed `66ff9419` while the host nonce
  changed from `1201db2e` to `1e537c87`, then the entire suite passed again
  (burst 65,536 bytes / 805 ms = 81,411 bytes/s).
- Host final totals: `retx=56`, `giveup=2` (one stall alarm, one uncertain reset
  command discarded at peer session change), `adopt=0`, `dup=1`.
- XT804 before reboot: `retx=6`, `dup=4`, `giveup=0`, `drop=0`.

### PC and build checks

- PC built using **`bsp/pc/build_windows_32bit_msvc.bat`**; output contains
  `Build completed successfully`. Latest build log:
  `bsp/pc/build/logs/pc_build_20261103_160107.log`.
- `pc-arq-state-3.log`: production state-machine tests pass: explicit handshake,
  legacy flag collision, failed admission/retry, delayed/reordered sequence,
  65,536-sequence wrap, retained pending on alarm, stale session/HELLO rejection,
  and the specific old devinfo length workaround.
- `pc-ping-regression.log`, `pc-nanopb-regression.log`: existing regression suites
  pass (4/4 ping, 5/5 nanopb).
- Final hardware build logs: `ccm-arq-build-5.log`, `xt804-arq-build-6.log`.
  Builds retain existing unrelated warnings; this is not a warning-free SDK build.

### Scope of evidence

The fixture covered UART2 command traffic, queue/concurrency load, deterministic
admission rejection, and reboot recovery. It did not test WiFi/TCP throughput,
heap exhaustion by actual allocation pressure, all other BSPs, long-duration soak,
or physical pre-`ad5410835` firmware with RPC/FRAG header bits (that collision is
covered by the PC state-machine test). No external blocker remains for this fixture.

XT804 builds also regenerate tracked `ld/air101_103.ld` and `lib/libwmarch.a`;
both were clean at task start. After confirming their changes came from this
build (including the `wmarch` archive entries in the build logs), final cleanup
restored only these two generated artifacts to HEAD. At that point, before the
OTA follow-up, the XT804 functional diff contained only `app/main.c`, `app/port/luat_airlink_uart_air101.c`,
`app/stubs/luat_airlink_port.c`, and `xmake.lua`. User changes and archived test
artifacts were preserved. Read-only verification confirmed `OVERALL_PASS` in
`matrix-new-new-verified.log:263` and `host-only-reboot-host.log:252`, each with
`Total: 1 passed, 0 failed`; no hardware test was rerun during final cleanup.

## Reproduction

Set `PATH` as above and `AIRLINK_ARQ_TEST=1` in each platform build process.
Build CCM from `csdk/project/luatos`, XT804 from its root. Both support
`LUATOS_REPO_DIR` for selecting the shared source. For the old CCM baseline also
set `LUAT_EXT_REPO_DIR` to the ext repository. Select firmware type 101 in the
ignored generated header for the tested Air1602/XIP configuration.

PC tests (working directory `LuatOS/bsp/pc`):

```text
cmd /c build_windows_32bit_msvc.bat
build/out/luatos-lua.exe ../../testcase/common/scripts ../../testcase/func/airlink/airlink_uart_arq_basic/scripts
```

CCM end-to-end test (use an absolute SOC path, COM8 on this fixture):

```text
luatos-cli flash test --soc <CCM.soc> --port COM8 --script <LuatOS>/testcase/common/scripts --script <LuatOS>/testcase/func/airlink/airlink_uart_arq_hw/scripts --timeout 50 --keyword "### OVERALL_PASS ###" --fail-keyword "### OVERALL_FAIL ###"
```

`flash test` judges the runner token; bounded `log view-binary` capture processes
are deliberately stopped after the observation interval (exit 124), and their
PASS/FAIL must be read from the captured runner output, not the process exit code.
