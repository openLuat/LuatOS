
/*
@module  gbc
@summary GBC模拟器
@version 1.0
@date    2024.1.1
@tag     LUAT_USE_GBC
*/

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_msgbus.h"

#include "gbc.h"
#include "gbc_joypad.h"

#define LUAT_LOG_TAG "gbc"
#include "luat_log.h"

enum {
    GBC_LUA_KEY_UP = 1,
    GBC_LUA_KEY_DOWN,
    GBC_LUA_KEY_LEFT,
    GBC_LUA_KEY_RIGHT,
    GBC_LUA_KEY_A,
    GBC_LUA_KEY_B,
    GBC_LUA_KEY_START,
    GBC_LUA_KEY_SELECT
};

static luat_rtos_task_handle gbc_thread;
static gbc_t *gbc = NULL;
static int _gbc_cleanup_handler(lua_State *L, void *ptr);

void gbc_task(void *param)
{
    gbc_t *ctx = (gbc_t *)param;
    gbc_run(ctx);
    rtos_msg_t msg = {
        .handler = _gbc_cleanup_handler,
        .ptr     = ctx,
        .arg1    = 0,
        .arg2    = 0,
    };
    luat_msgbus_put(&msg, 0);
    while (1) { luat_rtos_task_sleep(1000); }
}

/*
gbc模拟器初始化
@api gbc.init(file_path)
@string file_path ROM文件路径
@return bool 成功返回true,否则返回false
@usage
gbc.init("/luadb/game.gb")
*/
static int l_gbc_init(lua_State *L)
{
    const char *rom_path = luaL_checkstring(L, 1);
    gbc = gbc_init();
    if (!gbc) {
        LLOGE("gbc_init failed");
        lua_pushboolean(L, 0);
        return 1;
    }
    if (gbc_load_file(gbc, rom_path) != GBC_OK) {
        LLOGE("gbc_load_file failed: %s", rom_path);
        gbc_deinit(gbc);
        gbc = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    if (luat_rtos_task_create(&gbc_thread, 8 * 1024, 27, "gbc", gbc_task, gbc, 0)) {
        LLOGE("gbc task create failed");
        gbc_deinit(gbc);
        gbc = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
gbc模拟器反初始化，释放资源
@api gbc.deinit()
@usage
gbc.deinit()
*/
static int l_gbc_deinit(lua_State *L)
{
    (void)L;
    if (gbc) {
        gbc->gbc_quit = 1;
    }
    return 0;
}

static int _gbc_cleanup_handler(lua_State *L, void *ptr)
{
    (void)L;
    gbc_t *ctx = (gbc_t *)ptr;
    if (!ctx) return 0;
    gbc_deinit(ctx);
    if (gbc == NULL || gbc == ctx) {
        gbc = NULL;
        if (gbc_thread) {
            luat_rtos_task_delete(gbc_thread);
            gbc_thread = NULL;
        }
    }
    return 0;
}

/*
GBC按键控制
@api gbc.key(key, val)
@number key 按键常量
@number val 状态 1按下 0抬起
@usage
gbc.key(gbc.Up, 1)
gbc.key(gbc.Up, 0)
*/
static int l_gbc_key(lua_State *L)
{
    if (!gbc) return 0;
    int key = luaL_checkinteger(L, 1);
    int val = luaL_checkinteger(L, 2);
    gbc_key_t gbc_key;
    switch (key) {
        case GBC_LUA_KEY_UP:     gbc_key = GBC_KEY_UP;     break;
        case GBC_LUA_KEY_DOWN:   gbc_key = GBC_KEY_DOWN;   break;
        case GBC_LUA_KEY_LEFT:   gbc_key = GBC_KEY_LEFT;   break;
        case GBC_LUA_KEY_RIGHT:  gbc_key = GBC_KEY_RIGHT;  break;
        case GBC_LUA_KEY_A:      gbc_key = GBC_KEY_A;      break;
        case GBC_LUA_KEY_B:      gbc_key = GBC_KEY_B;      break;
        case GBC_LUA_KEY_START:  gbc_key = GBC_KEY_START;  break;
        case GBC_LUA_KEY_SELECT: gbc_key = GBC_KEY_SELECT; break;
        default: return 0;
    }
    gbc_joypad_set(gbc, gbc_key, (uint8_t)val);
    return 0;
}

/*
查询GBC是否已退出
@api gbc.quit_requested()
@return bool 已退出则返回true
@usage
if gbc.quit_requested() then
    gbc.deinit()
end
*/
static int l_gbc_quit_requested(lua_State *L)
{
    lua_pushboolean(L, gbc != NULL && gbc->gbc_quit);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_gbc[] =
{
    {"init",           ROREG_FUNC(l_gbc_init)           },
    {"deinit",         ROREG_FUNC(l_gbc_deinit)         },
    {"key",            ROREG_FUNC(l_gbc_key)             },
    {"quit_requested", ROREG_FUNC(l_gbc_quit_requested)  },

    //@const Up number 按键上
    { "Up",     ROREG_INT(GBC_LUA_KEY_UP)     },
    //@const Down number 按键下
    { "Down",   ROREG_INT(GBC_LUA_KEY_DOWN)   },
    //@const Left number 按键左
    { "Left",   ROREG_INT(GBC_LUA_KEY_LEFT)   },
    //@const Right number 按键右
    { "Right",  ROREG_INT(GBC_LUA_KEY_RIGHT)  },
    //@const A number 按键A
    { "A",      ROREG_INT(GBC_LUA_KEY_A)      },
    //@const B number 按键B
    { "B",      ROREG_INT(GBC_LUA_KEY_B)      },
    //@const Start number 按键开始
    { "Start",  ROREG_INT(GBC_LUA_KEY_START)  },
    //@const Select number 按键选择
    { "Select", ROREG_INT(GBC_LUA_KEY_SELECT) },
    { NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_gbc(lua_State *L)
{
    luat_newlib2(L, reg_gbc);
    return 1;
}
