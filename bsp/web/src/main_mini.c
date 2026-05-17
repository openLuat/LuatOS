
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
#include "luat_posix_compat.h"
#include "luat_timer_engine.h"

extern char *luadb_ptr;
extern const uint8_t luadb_mod[];

const uint8_t luatdb_secret[] = {0xa8, 0xe4, 0x9c, 0x1a, 0x57, 0x4b, 0x00, 0x2f, 0x4c, 0xc4, 0x74, 0xb8, 0x69, 0x1d, 0x90, 0xc1, 0x84, 0x24, 0x16, 0x11, 0x79, 0xa2, 0xd0, 0x4b, 0xfc, 0xf5, 0x14, 0x5d, 0xdd, 0x54, 0xdd, 0x55};

#define LUAT_HEAP_SIZE (4 * 1024 * 1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

int cmdline_argc;
char** cmdline_argv;
extern void luat_mcu_startup_init(void);

int lua_main (int argc, char** argv);
void luat_main(void);

void luat_log_init_win32(void);
void luat_log_deinit_win32(void);
void luat_network_init(void);

int luat_cmd_parse(int argc, char** argv);

int32_t luatos_pc_climode;

static void web_luat_main(void) {
    if (cmdline_argc == 1) {
        luatos_pc_climode = 1;
#ifdef LUAT_CONF_VM_64bit
        LLOGI("LuatOS@%s %s, Build: " __DATE__ " " __TIME__ " 64bit", "WEB", LUAT_VERSION);
#else
        LLOGI("LuatOS@%s %s, Build: " __DATE__ " " __TIME__ " 32bit", "WEB", LUAT_VERSION);
#endif
        lua_main(cmdline_argc, cmdline_argv);
    }
    else {
        luat_main();
    }
}

int main(int argc, char** argv) {
    cmdline_argc = argc;
    cmdline_argv = argv;

    luat_heap_opt_init(LUAT_HEAP_SRAM);
    luat_mcu_startup_init();
    luat_timer_engine_init();

    luat_pcconf_init();

    luat_log_init_win32();
    bpool(luavm_heap, LUAT_HEAP_SIZE);
    luat_heap_opt_init(LUAT_HEAP_PSRAM);

    luat_fs_init();
    luat_network_init();

    if (!memcmp(luatdb_secret, luadb_mod, 32)) {
        LLOGI("luadb mod init");
        luadb_ptr = (char*)luadb_mod + 32;
        cmdline_argc = 2;
    }
    else {
        int ret = luat_cmd_parse(cmdline_argc, cmdline_argv);
        if (ret) {
            return ret;
        }
    }

    web_luat_main();

    luat_log_deinit_win32();
    return 0;
}
