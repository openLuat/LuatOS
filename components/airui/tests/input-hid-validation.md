# HID / LVGL validation — 2026-09-08

This records the earlier headless validation. The temporary C board test and
its startup/build hook have since been removed in favor of the Lua screen demo
in `olddemo/demo/usb/`; see `README.input-hid.md` for the current workflow.

## Scope

Air1601, COM89 at 6000000 baud, bundled LVGL 9.4. The opt-in C test
uses real AirUI input callbacks, LVGL indev processing, button and textarea
objects on an 800x480 headless display. Physical LCD rendering was not tested.
No Lua input API was added; the USB demo only starts USB Host.

## Hardware observations

- Logitech receiver `046d:c542`: relative movement reaches the pointer callback.
- SIGMACHIP keyboard `1c4f:0002`: `a -> ab -> abc -> abcA`, Tab focuses the
  button, and Enter produces a click in the first capture.
- After the fixes, Backspace changes `abc` to `ab`.
- Over a non-scrollable button: one physical down/up pair produces one click;
  the following 30 wheel reports produce no additional clicks.
- With scrolling enabled: 42 wheel reports produce 39 scroll notifications
  (reports can coalesce or reach a boundary). Positions advance in 32-pixel
  steps and return to zero. No click occurs during scrolling. The subsequent
  two physical down/up pairs produce exactly two clicks.
- Replacing the keyboard with the mouse succeeds. Keyboard removal produces
  transient input reset/state-lost messages before device removal; subsequent
  mouse input works. This is not a long-duration hot-plug stress test.
- Startup checks find `LVGL_HID_TEST_READY` and `HID_C_HOST_STABLE`, with no
  `stack traceback` or `LVGL_HID_TEST_INIT_FAILED`.

Capture paths, relative to the sibling CCM42xx SDK's `csdk/project/luatos/`:

- `build/input-lvgl-live.log`: initial keyboard and mouse observations.
- `build/input-lvgl-wheel-live.log`: Backspace and no wheel-induced clicks.
- `build/input-lvgl-scroll-live.log`: actual scrolling and click counts.
- Corresponding binary captures are in `build/input-lvgl-raw/`,
  `build/input-lvgl-wheel-raw/` and `build/input-lvgl-scroll-raw/`.
- Final download/startup result: `build/input-lvgl-scroll-flash.log` (PASS).

## Fixes and automated checks

The adapter avoids the bundled LVGL pointer `enc_diff` path, which could replay
a click on the previously pressed non-scrollable object. Wheel input instead
scrolls the hovered object's nearest eligible ancestor using public LVGL APIs.
LVGL core was not modified.

The adapter also leaves timestamps to LVGL, avoiding mixed clock epochs between
device uptime and GUI ticks. Removing the two queued timestamp fields saves
256 bytes of static queue storage.

`run_input_hid_test.py` passes against real bundled LVGL: fast click edges,
wheel without false clicks, hovered scrolling, held states, differing clock
epochs and long-press timing, Shift, Backspace, overlapping keys, Tab, Enter,
and cancellation on unplug or queue overflow.

SDK test build passes (`build/input-lvgl-scroll-test-build.log`): FLASH 5248456 B,
RAM 56808 B, PSRAM 3997624 B. Existing linker warnings remain for wchar_t size
in algorithm archives and an RWX segment; the existing display source glob
also has no matches. A normal build without the test flag was separately
checked earlier and did not contain the test startup symbols.

The Windows PC GUI build path was exercised, but the full simulator build is
blocked by unresolved GmSSL symbols (`sm2_bn_*`, `SM2_N`, `sm3_digest`,
`sm4_cbc_*`). It is not recorded as a successful GUI simulator build.

At the end of that run the board retained the opt-in test firmware. Serial capture was stopped after
validation, releasing COM89. See `README.input-hid.md` for test setup and the
adapter's supported keys and limits.

## Lua screen validation — same day

The temporary SDK `tests/input_lvgl_test.c`, xmake test flag and msgbus startup
hook were removed. The normal firmware contains no `luat_input_lvgl_test_start`,
`test_ctx` or `test_poll` symbols. The host regression source is retained.

The USB Lua demo now initializes the real AirCAMERA_1032 LCD and AirUI, creates
a textarea, button/counter and 24-row table, and then starts USB Host. The LCD
driver is an identical copy of the repository's AirCAMERA_1032 `lcd_drv.lua`.
The normal C mouse adapter has a small display-owned cursor; test widgets and
their callbacks are entirely created from Lua.

Validation:

- Lua syntax check passes for all three demo scripts.
- Normal SDK build passes: FLASH 5247568 B, RAM 56808 B, PSRAM 3997136 B.
- Download/startup passes after one transient COM89 access-denied failure.
  Logs show `lcd.init true`, font loaded and `HID_LUA_LVGL_READY 1024 600`.
- User confirms physical display, cursor, button clicks and table scrolling
  work; table scrolling does not increment the button counter.
- User confirms keyboard input, Shift, Backspace, Tab and Enter work on-screen.
  Capture includes Lua `TEXT`, `CLICKED` and `ROW` callbacks, with zero
  `callback error` and zero `stack traceback` messages.
- PC GUI build was rerun; the same GmSSL unresolved-symbol link failure remains
  (`bsp/pc/build/logs/pc_build_20260908_121953.log`).

SDK logs: `build/input-lua-lvgl-build.log`,
`build/input-lua-lvgl-flash-retry.log`, `build/input-lua-lvgl-live.log`, and
`build/input-lua-lvgl-raw/ap_20260908_122347_COM89.bin`.
The board now retains the normal firmware with the Lua screen demo; serial
capture was stopped and COM89 released.
