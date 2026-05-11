
#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include <stdlib.h>

#include "luat_pcconf.h"

#include "bget.h"

#define LUAT_LOG_TAG "main"
#include "luat_log.h"

#include "luat_mem.h"
/* luat_posix_compat.h must come before uv.h on Windows to establish the
 * correct winsock2/windows.h include order. */
#include "luat_posix_compat.h"
#include "luat_timer_engine.h"


#ifdef LUAT_USE_LWIP
#include "lwip/tcpip.h"
#endif

#ifdef LUAT_USE_LVGL
luat_timer_handle_t lvgl_timer_handle;
#include "lvgl.h"
#endif

extern char *luadb_ptr;
extern const uint8_t luadb_mod[];

// 如果模拟器luadb_mod 的前32bytes为luatdb_secret，说明可能被luatools修改过
// 这串数据实际上是"FFFFEEEEDDDDCCCCBBBBAAAA999988887777666655554444333322221111"的sha256值
const uint8_t luatdb_secret[] = {0xa8, 0xe4, 0x9c, 0x1a, 0x57, 0x4b, 0x00, 0x2f, 0x4c, 0xc4, 0x74, 0xb8, 0x69, 0x1d, 0x90, 0xc1, 0x84, 0x24, 0x16, 0x11, 0x79, 0xa2, 0xd0, 0x4b, 0xfc, 0xf5, 0x14, 0x5d, 0xdd, 0x54, 0xdd, 0x55};


#define LUAT_HEAP_SIZE (4*1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

int cmdline_argc;
char** cmdline_argv;
// uv_timespec64_t boot_ts;
extern void luat_lwip_init(void);
extern void luat_mcu_startup_init(void);

int lua_main (int argc, char** argv);

void luat_log_init_win32(void);
void luat_log_deinit_win32(void);
void luat_uart_initial_win32(void);
void luat_network_init(void);


int luat_cmd_parse(int argc, char** argv);
static int luat_lvg_handler(lua_State* L, void* ptr);
static void lvgl_timer_cb(void* arg);

int32_t luatos_pc_climode;

void uv_luat_main(void* args) {
    (void)args;
    // printf("cmdline_argc %d\n", cmdline_argc);
    if (cmdline_argc == 1) {
        luatos_pc_climode = 1;
        #ifdef LUAT_CONF_VM_64bit
        LLOGI("LuatOS@%s %s, Build: " __DATE__ " " __TIME__ " 64bit", "PC", LUAT_VERSION);
        #else
        LLOGI("LuatOS@%s %s, Build: " __DATE__ " " __TIME__ " 32bit", "PC", LUAT_VERSION);
        #endif
        lua_main(cmdline_argc, cmdline_argv);
    }
    else {
        luat_main();
    }
}

static void timer_nop(void *arg) { (void)arg; }

// boot
int main(int argc, char** argv) {
    cmdline_argc = argc;
    cmdline_argv = argv;

    luat_heap_opt_init(LUAT_HEAP_SRAM);
    
#ifdef LUAT_USE_WINDOWS
    extern void InitCrashDump();
    InitCrashDump();
    // Windows平台下自动设置控制台编码
    extern void luat_console_auto_encoding(void);
    luat_console_auto_encoding();
#endif

    luat_mcu_startup_init();
    luat_timer_engine_init();

    luat_pcconf_init();

    luat_log_init_win32();
    bpool(luavm_heap, LUAT_HEAP_SIZE);
    luat_heap_opt_init(LUAT_HEAP_PSRAM);
    
    #ifdef LUAT_USE_LVGL
    lv_init();
    #endif
    luat_fs_init();
    luat_network_init();

    // 如果luadb_mod被修改过，那么直接以luadb_mod偏移32bytes作为luadb

    if(!memcmp(luatdb_secret, luadb_mod, 32))
    {
        LLOGI("luadb mod init");
        luadb_ptr = (char*)luadb_mod + 32;
        cmdline_argc = 2;
    }
    else
    {
        int ret = luat_cmd_parse(cmdline_argc, cmdline_argv);
        if (ret) {
            return ret;
        }
    }
    


    #ifdef LUAT_USE_LVGL
    lvgl_timer_handle = luat_timer_engine_create(lvgl_timer_cb, NULL);
    luat_timer_engine_start(lvgl_timer_handle, 25, 1);
    #endif

    #ifdef LUAT_USE_LWIP
    //LLOGD("初始化lwip");
    tcpip_init(NULL, NULL);
    #endif

    uv_luat_main(NULL);

    luat_log_deinit_win32();
    return 0;
}

// UI相关

#ifdef LUAT_USE_LVGL
static int luat_lvg_handler(lua_State* L, void* ptr) {
    (void)L;
    (void)ptr;
    lv_tick_inc(25);
    lv_task_handler();
    return 0;
}
static void lvgl_timer_cb(void* arg) {
    (void)arg;
    rtos_msg_t msg = {
        .handler = luat_lvg_handler
    };
    luat_msgbus_put(&msg, 0);
}
#endif
