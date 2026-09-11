# C input / LVGL validation

The LuatOS platform binds `luat_input_airui_receive` as a second direct input
consumer. A platform-supplied short lock protects the shared state and bounded
queues. All LVGL calls remain on the GUI task. The independent Lua input API
can subscribe to the same devices; see `components/input/README.lua.md`.

- Pointer slots 0/1 receive TP input when `LUAT_USE_INPUT_TOUCH` is enabled,
  with the legacy touch path retained otherwise; slot 2 receives USB mouse
  relative X/Y and left button. With the button released, the vertical wheel
  scrolls the hovered object's nearest scrollable ancestor through public LVGL
  APIs. The `enc_diff` path is avoided because it can replay a click in LVGL 9.
- Movement with unchanged buttons is coalesced; down/up edges are retained.
- Keyboard supports US ASCII, Shift, Caps Lock, arrows, Home/End, Backspace,
  Delete, Tab/Shift+Tab and Enter. LVGL owns long-press/repeat timing; device
  timestamps are not forwarded because their clock epoch can differ.
- Translated keys are remembered until release, even if Shift is released first.
  LVGL has one active keypad key; a new key supersedes the previously active key.
- Unplug/reset/overflow cancels the current interaction instead of completing a
  mouse or Enter click. Queues hold 31 entries each; up to 8 source IDs from one
  serialized input core are supported.
- Right/middle buttons, horizontal wheel, IME, keyboard layout selection, LED
  output and Num Lock behavior are not mapped in this first adapter.

Run `python components/airui/tests/run_input_hid_test.py` from the repository
root with GCC available (or set `CC`). This builds the bundled LVGL independently
of the PC simulator and validates actual button clicks, textarea edits, focus,
held states, overlapping keys, unplug and overflow. It does not mock LVGL.

Board validation now uses the normal firmware and Lua UI in
`olddemo/demo/usb/`. The temporary C headless test, build flag and startup hook
have been removed. Host-side automated regression remains independent.

- `lcd_drv.lua`: copied from the AirCAMERA_1032 example, RGB 1024x600,
  reset GPIO15, backlight GPIO2; initializes LCD buffers and AirUI.
- `hid_lvgl.lua`: Lua textarea, click counter and 24-row scrolling table.
- `input_demo.lua`: independent Lua subscriptions, state queries and input logs.
- `tp_drv.lua`: GT911 through I2C1, INT51 and RST2; binds touch to AirUI.
- `main.lua`: initializes the screen, UI and TP, then starts USB Host.

Build the CCM42xx SDK normally with `xmake build luatos` and download the
firmware plus the USB script directory. Expect `HID_LUA_LVGL_READY` and
`HID_C_HOST_STABLE` at startup. The normal HID pointer has a black circular
cursor with a white border, visible when input from a mouse is received and
hidden after removal. No Lua mouse polling or extra input binding is required.

1. Check the physical screen renders the title, textarea, button and table.
2. Move the mouse, click the button and compare the on-screen count with
   `hid_lvgl ... CLICKED` logs.
3. Wheel over the right-hand table; rows should move without increasing the
   button click count.
4. The textarea initially has keyboard focus. Type abc, Shift+A, Backspace;
   compare visible text with `hid_lvgl ... TEXT` logs. Tab then Enter exercises
   keyboard focus and activation; Shift+Tab returns to the previous control.
5. Verify removal while holding a button/key does not complete a click.
