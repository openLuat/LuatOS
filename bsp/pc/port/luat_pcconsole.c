#include "luat_base.h"
#include <stdlib.h>
#include <string.h>
#ifdef LUAT_USE_WINDOWS
#include <windows.h>
static HANDLE input_handle = INVALID_HANDLE_VALUE;
static DWORD saved_mode;
static int registered_cleanup;
static unsigned char held[256];
static BOOL WINAPI console_control(DWORD event) {
    if (event == CTRL_C_EVENT || event == CTRL_BREAK_EVENT || event == CTRL_CLOSE_EVENT ||
        event == CTRL_LOGOFF_EVENT || event == CTRL_SHUTDOWN_EVENT) {
        if (input_handle != INVALID_HANDLE_VALUE) SetConsoleMode(input_handle, saved_mode);
    }
    return FALSE; /* Preserve the standard process exit behavior. */
}
static void console_close(void) {
    if (input_handle != INVALID_HANDLE_VALUE) SetConsoleMode(input_handle, saved_mode);
    input_handle = INVALID_HANDLE_VALUE;
    SetConsoleCtrlHandler(console_control, FALSE);
    memset(held, 0, sizeof(held));
}
#endif
static int l_close(lua_State *L) {
    (void)L;
#ifdef LUAT_USE_WINDOWS
    console_close();
#endif
    return 0;
}
static int l_open(lua_State *L) {
#ifdef LUAT_USE_WINDOWS
    if (input_handle != INVALID_HANDLE_VALUE) { lua_pushboolean(L, 1); return 1; }
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode;
    if (h != INVALID_HANDLE_VALUE && GetConsoleMode(h, &mode) &&
        SetConsoleMode(h, (mode | ENABLE_EXTENDED_FLAGS | ENABLE_PROCESSED_INPUT) &
            ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_QUICK_EDIT_MODE | ENABLE_VIRTUAL_TERMINAL_INPUT))) {
        saved_mode = mode;
        input_handle = h;
        SetConsoleCtrlHandler(console_control, TRUE);
        if (!registered_cleanup) { atexit(console_close); registered_cleanup = 1; }
        lua_pushboolean(L, 1);
        return 1;
    }
#endif
    lua_pushboolean(L, 0);
    lua_pushliteral(L, "interactive Windows console required");
    return 2;
}
static int l_poll(lua_State *L) {
    lua_newtable(L);
#ifdef LUAT_USE_WINDOWS
    DWORD available = 0, count = 0;
    INPUT_RECORD records[64];
    if (input_handle == INVALID_HANDLE_VALUE ||
        !GetNumberOfConsoleInputEvents(input_handle, &available) || !available) return 1;
    if (available > 64) available = 64;
    if (!ReadConsoleInputW(input_handle, records, available, &count)) return 1;
    int index = 1;
    for (DWORD i = 0; i < count; i++) {
        if (records[i].EventType != KEY_EVENT) continue;
        KEY_EVENT_RECORD *key = &records[i].Event.KeyEvent;
        WORD vk = key->wVirtualKeyCode;
        if (!key->bKeyDown) { if (vk < 256) held[vk] = 0; continue; }
        if (vk == VK_RETURN || vk == VK_BACK) {
            if (held[vk]) continue;
            held[vk] = 1;
            if (index <= 64) {
                lua_pushstring(L, vk == VK_RETURN ? "enter" : "backspace");
                lua_rawseti(L, -2, index++);
            }
        } else if (!(key->dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED | LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED))) {
            WCHAR ch = key->uChar.UnicodeChar;
            if (ch < 32 || ch > 126) continue;
            char c = (char)ch;
            unsigned repeat = key->wRepeatCount;
            while (repeat-- && index <= 64) {
                lua_pushlstring(L, &c, 1);
                lua_rawseti(L, -2, index++);
            }
        }
    }
#endif
    return 1;
}
/** Register the PC-only, nonblocking console keyboard interface. */
LUAMOD_API int luaopen_pcconsole(lua_State *L) {
    static const luaL_Reg api[] = {{"open", l_open}, {"poll", l_poll}, {"close", l_close}, {NULL, NULL}};
    luaL_newlib(L, api);
    return 1;
}
