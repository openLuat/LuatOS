// bsp/pc/stubs/uart_dll_utest/luat_uart_dll_utest.c
// PC-only probe used by testcase/utest/drv/uart_basic/.
// Verifies the Rust UART dll is loaded into the process and that each
// of the 8 luat_uart_*_extern symbols is exported.

#include "luat_base.h"

#ifdef LUA_USE_WINDOWS
#include <windows.h>
#include <string.h>

static int probe_module_handle(const char *name) {
    return GetModuleHandleA(name) != NULL ? 1 : 0;
}
static int probe_export(const char *dll, const char *sym) {
    HMODULE m = GetModuleHandleA(dll);
    if (m == NULL) return 0;
    return GetProcAddress(m, sym) != NULL ? 1 : 0;
}

// 约定:返 0 = case 命中且通过,返 -1 = 失败或未知 case
int luat_uart_dll_utest(lua_State *L, const char *case_name) {
    if (!case_name) return -1;
    if (strcmp(case_name, "dll_loaded") == 0) {
        return probe_module_handle("luat_uart_i686.dll") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_exist_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_exist_extern") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_open_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_open_extern") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_close_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_close_extern") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_read_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_read_extern") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_send_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_send_extern") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_recv_cb_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_recv_cb_extern") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_sent_cb_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_sent_cb_extern") == 1 ? 0 : -1;
    } else if (strcmp(case_name, "export_get_list_extern") == 0) {
        return probe_export("luat_uart_i686.dll", "luat_uart_get_list_extern") == 1 ? 0 : -1;
    }
    return -1;  // 未知 case name
}
#endif