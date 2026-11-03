# UART ARQ2 protocol

This implementation uses a single UART transport state machine. The independent
two-instance implementation is maintained on `feat/airlink-dual-instance`.

## Negotiation and wire format

- Framing, escaping and CRC16 remain compatible with legacy AirLink.
- A UART devinfo command contains `luat_airlink_dev_info_t` followed by 16 bytes:
  `AL-ARQ2\0` (8 bytes), local boot nonce (LE32), echoed peer nonce (LE32).
  Command and frame lengths describe the complete transmitted data.
- Only an exact extension size/magic and an echoed local nonce enable TX ARQ.
  Seeing a capable peer without its echo pauses data TX until negotiation completes.
- UART devinfo clears caps bit2 even for ARQ2. The old experimental implementation
  enabled ARQ from this bit alone; advertising it would break legacy fallback.
  RPC/FRAG capability bits are preserved.
- Reliable frames use flags bit8=ARQ, bit9=sequence-valid and bits16..31=session tag.
  The tag is CRC16 of the two sorted LE32 boot nonces; zero is mapped to one.
  This is a stale-session discriminator, not authentication. The CRC16/16-bit
  sequence protocol cannot guarantee immunity to collisions or frames delayed
  across an entire sequence-number cycle.
- Old RPC/FRAG bit8/9 flags without a session tag are treated as legacy traffic
  before negotiation. Tagged frames from unknown/previous sessions are rejected
  even immediately after reboot, before HELLO arrives.
- Legacy UART devinfo has a known malformed shape: frame payload length 128 and
  command length 128, leaving only 124 command-data bytes. Only this devinfo shape
  is clamped. Data-command length validation stays strict, and the devinfo handler
  reads fields from a bounded, zero-filled snapshot.

## Delivery and ownership

- Stop-and-wait, RTO 60 ms, sequence/ACK modulo 65536.
- RX classifies a sequence without advancing it. Successful command admission
  commits the next expected sequence and requests ACK. Allocation/queue failure
  leaves the sequence unchanged so retransmission retries delivery.
- Nonmatching sequences are discarded rather than arbitrarily adopted; the
  current next-expected ACK is repeated.
- The common acceptance API queues IP commands too. The XT804 IP path returns
  its actual WiFi TX admission result. ACK means transport acceptance, not
  completion of an application action or over-the-air WiFi transmission.
- TX exclusively owns and frees `pending.cmd`; RX publishes ACK/session state
  under a mutex. A matching ACK is checked before the timeout alarm. The 3-second
  alarm reports a stalled link while retaining the pending frame and sequence.
- Peer session changes discard uncertain old-session pending commands with
  explicit drop/giveup counters. Applications requiring exactly-once processing
  across power loss need persistent IDs/results.
- XT804 producers copy commands into a bounded 32-entry queue. The main-loop TX
  poll owns framing buffers and retransmission; devinfo has a separate snapshot
  so pending data cannot block heartbeats. RX is drained on each poll rather than
  relying on a potentially lost interrupt flag. The raw TX buffer uses P2 heap
  to preserve scarce SDK/P1 memory for WiFi association.
- A delimiter may terminate a damaged frame and begin the next frame. Parsers
  retain the closing delimiter for resynchronization; a lone delimiter is idle.
