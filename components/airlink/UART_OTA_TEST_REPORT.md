# Air1602 / Air6208 UART2 OTA bench — 2026-11-03

## Result and existing capabilities

All three normal upgrade paths completed over the network:

| Target | Actual path | Before → after | Result |
|---|---|---|---|
| CCM script | PC hotspot HTTP → Air6208 WiFi bridge → UART2 → CCM HTTP FOTA → bootloader | `OTA_SCRIPT_A` → `OTA_SCRIPT_B`, core stays V1029 | PASS |
| CCM complete application + script | Same HTTP/AirLink path, complete CCM `.sota` | V1029 → V1030, script B retained | PASS |
| XT804 application | CCM HTTP downloads app `.img` → `airlink.sfota()` → UART2 ARQ commands 0x04–0x07 → existing XT804 bootloader | V1002 → V1003 | PASS |

Air6208 **already supported OTA** before this task: its BSP enables
`LUAT_USE_FOTA` and `LUAT_USE_AIRLINK_EXEC_FOTA`, builds `luat_fota_air101.c`,
and uses the existing secondary bootloader upgrade flag. The host already has
the UART `airlink.sfota(path)` executor. No new OTA service/protocol framework,
bootloader implementation, or flash partition layout was introduced.

This particular Air6208 application is no-VM, with script/FS sizes zero and no
standalone HTTP/lwIP client. Its tested OTA is a complete **application** update
forwarded by the host, not a Lua script update or bootloader update. The receiver
was hardened during USB preparation before the actual OTA test below; success
is not a claim that the untouched original receiver had adequate validation.

USB/ISP downloads were used only to prepare/recover the baseline and install
the test controller. The V1030 and V1003 target applications were never installed
over USB during this test. Their observed version changes came from OTA.

## Fixture and evidence

- COM8 / CH343: actual hardware `Air1602_A10`, not Air1601; log 6 Mbps.
- COM7 / CH340: Air6208/XT804, 1 MiB flash; text log 2 Mbps.
- UART2 crossover: 2 Mbps. ARQ2 handshake was observed after each upgrade.
- Hotspot gateway `192.168.137.1`, device DHCP address `192.168.137.53`.
- Supplied credentials are confined to temporary test scripts/packages; none
  were added to repository sources or this report.

Evidence root:

`C:\Users\ThinkPad\AppData\Local\Temp\opencode\airlink-evidence\ota`

Primary evidence:

- `ota-host-continuous.log`: uninterrupted capture across all actual OTA phases.
- `ota-peer-continuous.log`: peer transfer, CRC, flag verification and new boot.
- `http.log`: requests from `192.168.137.53` for all three upgrade artifacts.
- `peer-image-validation.json`: offline header/layout/body CRC and SHA256 check.
- `pc-framing-regression.log`: production UART parser corruption/recovery test.

Continuous logs were opened before the test and kept open during OTA. This avoids
modem-line transitions from reopening COM7 being mistaken for an OTA reboot.

### Exact observed evidence

Host script:

- HTTP package: **2873 bytes**.
- Host log lines 373–377: `common data md5 ok`, FOTA ready, HTTP 200, explicit
  `REBOOT_AFTER_VALIDATED_OTA`.
- Line 389: bootloader `soc ota done!`.
- Line 430: `OTA_BOOT OTA_SCRIPT_B V1029 Air1602`.
- Lines 443 / 486: ARQ2 ready / post-reboot HTTP probe 200.

Host complete application:

- HTTP package: **3,683,719 bytes**, within the existing 5 MiB staging partition.
- Host action starts at 164.805 s; HTTP FOTA returns 200 at 207.748 s
  (about **42.94 s**, including staging writes and validation).
- Lines 1090–1094: common-data MD5 OK and explicit reboot after successful FOTA.
- Line 1252: bootloader `soc ota done!` at 25.925 s in the bootloader phase.
- Line 1293: `OTA_BOOT OTA_SCRIPT_B V1030 Air1602`.
- Lines 1306 / 1352: ARQ2 ready / HTTP probe 200.

Peer application:

- Host line 1508: HTTP 200 and local image size **204,864 bytes**.
- Host lines 1511–1525: UART FOTA start, all 204,864 bytes sent, done/end/reset.
  The existing conservative transfer executor took about **31.66 s** to enqueue
  the entire file (including its erase/first-block pacing).
- Peer lines 797–798: 376 KiB staging initialization, `fota_init ret 0`.
- Peer line 820: header verified, total bytes 204864, body CRC `F99B3507`.
- Peer lines 858–860: complete stored-image CRC verified, 204800 payload bytes,
  total written 204864, `fota_done ret 0`.
- Peer lines 868–870: upgrade flag written at `0x080FF000`, read back and verified,
  `fota_end ret 0`.
- Peer lines 871 / 874: reset command, then **Firmware version V1003**.
- Host lines 1531–1532: new ARQ2 session and `NEW_VERSION 1003`.
- Host lines 1557 / 1559: `PING ... true ... OTA_PEER_RECOVERED` and
  `POST_REBOOT_HTTP 200` after reconnecting WiFi.

## Formats and partition checks

CCM used the CLI's actual supported package generator:

```text
luatos-cli build filesystem --src <temporary-scripts> --output <unpacked-soc>/script.bin --luac --bitw 64
luatos-cli soc pack --dir <unpacked-soc> --output <target.soc>
luatos-cli fota build --new <target.soc> --script-only --output <script.sota>
luatos-cli fota build --new <target.soc> --output <full.sota>
```

The tested firmware type is 101/XIP. Its package metadata selects core
`0x14000000`, script `0x14700000`, staging `0x14800000` / length `0x500000`.
The receiver checks package-header CRC and stored common-data MD5; bootloader
checks common-data MD5 and final decompressed destination data MD5.

For XT804 the correct artifact is the build-generated **`AIR6208.img`**, not
`AIR6208.fls` and not the `.soc` archive. Its 64-byte image header and complete
body CRC were independently checked against `wm_tool.c`'s CRC convention.

| Field | Verified value |
|---|---|
| Magic | `0xA0FFFF9F` |
| Image type / compression | application / uncompressed |
| Running image header | `0x0806E000` |
| Running application | `0x0806E400` |
| Staging start | `0x08010000` |
| Staging capacity | 376 KiB, ends before running image header |
| Header CRC | `C9D90F9F` |
| Payload CRC | `F99B3507` |

The generated `.img` addresses match the known baseline image. The repository's
`soc_tools/AIR6208.json` template still has historical `app_addr=0x08011000`,
which is inconsistent with this no-VM layout. Therefore the generic CLI Air6208
FOTA generator was not used blindly; its fallback metadata would not describe
the running layout. No partition addresses were guessed or changed.

## Changes made in this task

### XT804

- `app/port/luat_fota_air101.c`: validate staging bounds, application destination
  and complete length; reject failed writes; verify the **whole stored payload**
  CRC before marking DONE; require successful upgrade-flag readback. Previously
  the complete-body CRC was skipped, the length check was incorrect, and exhausted
  flag-readback retries could still be logged as successful.
- `app/port/luat_airlink_uart_air101.c`: move the 2 KiB TX raw buffer to the existing
  P2 heap, freeing scarce P1/SDK space used during WiFi association; preserve a
  closing delimiter as a possible next start to recover from damaged/truncated
  frames. Added bounded/test-build UART diagnostics used during investigation.
- `app/network/luat_wlan_air101.c`: log association error number/detail and SDK heap
  size to make join failures diagnosable.

### Shared library

- `src/task/luat_airlink_uart_task.c`: matching delimiter resynchronization fix;
  ignore a lone retained delimiter in the partial-frame watchdog; check short UART
  writes; test-build TX diagnostics; PC parser selftest.
- `binding/luat_lib_airlink_arq_test.c`: exercise real parser recovery for adjacent
  delimiters, a shared end/start delimiter and a truncated frame followed by a valid
  frame. Verified using `build_windows_32bit_msvc.bat` and the existing ARQ suite.

No new CCM FOTA implementation was needed. Prior ARQ/platform changes and unrelated
user changes were preserved. At the end of the OTA bench run, all ARQ/OTA work
was left uncommitted pending separate publication authorization.

## Bring-up failures and resolution

Early ARQ peer firmware repeatedly failed WiFi association while the saved legacy
peer connected to the same hotspot. Reducing P1 pressure by moving the new raw TX
buffer into P2, and waiting for a valid AirLink peer before network setup, produced
successful association. A separate reproducible stream failure then showed host
ACKs written successfully and increasing peer RX byte counts, but no parsed ACK:
after a damaged frame the parser consumed both adjacent delimiters and stayed
one boundary out of phase. The delimiter fix recovered the link and passed the
PC corruption regression as well as the real OTA transfer.

The temporary HTTP listener at TCP/8765 was not reachable from the hotspot client.
The process lacks administrator privileges. An **existing** firewall permission
already allowed the installed test Python runtime on TCP/53, bound to
`192.168.137.1` and scoped to `192.168.137.0/24`. TCP/53 had no listener, so the
temporary HTTP artifact server used that permitted endpoint. UDP DNS and firewall
configuration were not changed. Only the dedicated `ota/www` directory was served;
directory listings and other paths were rejected.

Failed preparation/network runs remain in the evidence directory. They are not
counted as OTA successes. Once the continuous-capture fixture was established,
all three actual upgrade attempts above passed.

## Artifacts and cleanup

- `pre-ota-host/`, `pre-ota-peer/`: known working preparation SOC/FLS/IMG/ELF/MAP
  plus SHA256 manifests; previous `airlink-evidence/final-*` archives also remain.
- `target-host-v1030/`: target firmware/ELF/MAP, combined-script SOC and both SOTA
  packages with SHA256 manifest.
- `target-peer-v1003/`: target SOC/IMG/FLS/ELF/MAP with SHA256 manifest.
- Full host SOTA SHA256:
  `b01691d64c29daab5108e620dca4a3dbd92b37a92e2b5ed8198552c4a5720f0d`.
- Peer application IMG SHA256:
  `09d8744d77cfd0a088774e7b218acf69e29cf40365130602b9b1b2363482be58`.

The temporary V1030/V1003 source version changes were restored to V1029/V1002
after archiving; the devices remain on the successfully OTA-installed test
versions. XT804 generated `ld/air101_103.ld` and `lib/libwmarch.a` were clean at
task start and were restored again after the builds. No user edits were restored.

The temporary HTTP process and serial capture processes were stopped. Read-only
verification confirmed no TCP listener remained at `192.168.137.1:53`. Test
scripts, packages and logs remain in the evidence directory. No commits/pushes
or permanent firewall changes were made during the OTA bench run.

No external blocker remains for these normal OTA paths. Power-loss/interrupted
upgrade recovery and compressed XT804 OTA images were not exercised in this run.
