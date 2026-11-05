# AirLink UART reliable command envelope

## Unchanged link header and capabilities

The link header remains 16 bytes; CRC16 coverage and 0x7e/0x7d escaping are
unchanged. `pkgid` is an incrementing link-frame number, including retransmission
attempts. It carries no ARQ sequence or ACK information.

Flags bit8 is `rpc_supported`, bit9 is `frag_supported`, and the remaining 22 bits
are zeroed. Capabilities are written after transport callbacks so a callback's
flags initialization cannot erase them. Only compiled handlers are advertised:
the XT804 no-VM port declares `LUAT_AIRLINK_NO_FRAGMENT` because its cmd 0x32
handler is currently a stub. SPI, UART and HSPI share this packing logic; HSPI
reads extract the actual validated header rather than assuming peer support.

This follows the published V2054 header layout. Peer capabilities are snapshots
of the most recent validated frame: zero means unsupported, never unknown support.
Startup, stop, ARQ session changes and link-down processing clear the snapshot;
queries also expire it after 20 seconds without a valid header (allowing older
15-second devinfo heartbeats). UART does not update capabilities from an invalid
or stale-session ARQ envelope.

Devinfo bytes 1..3 are initialized padding only, with the original union offset 4
and unchanged structure size. There is no `devinfo.caps`, double declaration,
active RPC probe, or interpretation of padding. Unpublished caps-only experiments
receive no special negotiation; zero header flags leave RPC/fragment disabled.

## HELLO

UART devinfo (cmd 0x10) contains the existing device-info structure followed by
16 bytes: `AL-ARQ3\0` (8 bytes), local session nonce (LE32), echoed peer nonce (LE32).
The complete command/frame lengths include the extension. TX becomes reliable
only after seeing its own nonce echoed. A capable peer awaiting the echo pauses
new application TX. Bare legacy devinfo selects raw fallback. Unsupported or
malformed extensions and retired-session HELLOs are rejected.

The endpoint nonce starts with a random boot value. An established endpoint
rotates its own nonce when the peer changes, and does not rotate repeatedly while
negotiating. Thus a HELLO older than the eight-entry retired-peer cache cannot
reactivate DATA addressed to a former local nonce. DATA/ACK require the current
nonce pair AND completed echo negotiation. Lost HELLOs recover through periodic
heartbeats while pending DATA retries remain bounded by the RTO.

HELLO uses ordinary unsequenced devinfo heartbeats; it never occupies pending.
The old unreleased ARQ2 wire protocol is not negotiated or interpreted.

## DATA and ACK: reserved command 0x0033

Cmd 0x33 is consumed by the UART transport before application dispatch. Its
20-byte metadata is encoded explicitly in little endian:

| Offset | Size | Meaning |
|---|---:|---|
| 0 | 4 | `ARQ3` magic |
| 4 | 1 | Envelope version = 1 |
| 5 | 1 | 1 = DATA, 2 = ACK |
| 6 | 2 | Metadata size = 20 |
| 8 | 4 | Sender session nonce |
| 12 | 4 | Receiver session nonce |
| 16 | 2 | DATA sequence; zero for ACK-only |
| 18 | 2 | Next expected receive sequence |
| 20 | variable | DATA only: complete inner command header and payload |

ACK-only has exactly 20 metadata bytes and no inner command. DATA requires exact
inner/outer lengths. Nested envelopes and inner devinfo are rejected. Unknown
versions/types and session-mismatched envelopes are never dispatched, including
before initial negotiation after reboot. No flags bit or link pkgid is interpreted
as reliability metadata. Capability observations on UART are deferred until this
validation, so stale-session packets cannot change the current peer's capabilities.

## Admission, retry and frame budget

Stop-and-wait uses a 60 ms RTO and 16-bit sequence/ACK arithmetic. RX advances ACK
only after successful admission; queue/allocation failures are retried. Duplicate
or out-of-order DATA repeats the current ACK without executing the command again.
ACK-only frames are not acknowledged. The original `mem_is_high` flag controls new
DATA transmission, while ACKs, HELLOs and pending retries remain possible.

TX alone owns/frees pending. ACK processing precedes the 3-second stall alarm;
the alarm retains the same pending payload/sequence. A changed peer session drops
uncertain pending data with counters; an in-flight old pending pointer cannot be
encoded for the new session. Power-loss exactly-once application semantics require
persistent application IDs/results and are not promised by transport acceptance.

UART reserves envelope space before queue/pending admission, even before negotiation:
`16 link + 4 outer command + 20 metadata + 4 inner command + 1556 payload = 1600`.
Worst-case escaped length is 3202 bytes, within both 4096-byte TX buffers. Ethernet
MTU 1500 (1514-byte frame plus adapter byte) and 1024-byte OTA blocks fit. Larger
commands use verified cmd-level fragmentation (1548 data bytes per fragment), or
are rejected if the peer lacks reassembly. Jumbo IP frames
are rejected before queueing. SPI/HSPI retain their existing 1580-byte payload limit.
