# HZMP4 container reader

This component implements the embedded-side HZMP4 v1 demuxer. It intentionally
does not own video or audio decoders.

The first integration stage supports:

- fixed 128-byte header parsing and CRC32 validation;
- bounds-checked iteration over interleaved `HZPK` packets;
- packet payload CRC32 validation;
- MJPEG video packet read/skip and rewind;
- metadata needed by `videoplayer` and the future audio-master scheduler.

`videoplayer` consumes video packets directly when a `.hzmp4` path is opened.
Interleaved audio packets are recognized and skipped in the PC video-only
validation path. Audio decode and audio-master A/V synchronization are the next
hardware integration stage.
