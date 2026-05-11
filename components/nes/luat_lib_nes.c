
/*
@module  nes
@summary nes模拟器
@version 1.0
@date    2023.4.10
@tag     LUAT_USE_NES
*/

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#include "nes.h"
#include "nes_port.h"

#ifdef LUAT_USE_AIRUI
#include "nes_airui_video.h"
#endif

#define LUAT_LOG_TAG "nes"
#include "luat_log.h"

enum {
    Up = 1,
    Down,
    Left,
    Right,
    A,
    B,
    Start,
    Select
};

static luat_rtos_task_handle nes_thread;
static nes_t* nes = NULL;

/* 供 nes_airui_video.c 获取 nes 实例以操作 joypad */
nes_t *luat_nes_get_global_ctx(void) {
    return nes;
}

void nes_task(void *param){
    nes_run((nes_t *)param);
}

/*
nes模拟器初始化
@api nes.init(file_path, opts)
@string file_path 文件路径
@table  opts      可选配置表（仅 AirUI 模式有效）
                  opts.mode           string "airui" 启用 AirUI 渲染，默认 "lcd"
                  opts.scale          number 缩放倍数 1-3，默认 2
                  opts.show_controls  boolean 是否显示触控按钮，默认 true
@return bool 成功返回true,否则返回false
@usage
-- LCD 模式（默认，不变）
nes.init("/luadb/super_mario.nes")

-- AirUI 模式
nes.init("/luadb/super_mario.nes", {mode="airui", scale=2, show_controls=true})
*/
static int l_nes_init(lua_State *L) {
    size_t nes_rom_len;
    const char* nes_rom = luaL_checklstring(L, 1, &nes_rom_len);

#ifdef LUAT_USE_AIRUI
    int airui_mode    = 0;
    int scale         = 2;
    int show_controls = 1;

    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "mode");
        if (lua_isstring(L, -1) && strcmp(lua_tostring(L, -1), "airui") == 0) {
            airui_mode = 1;
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "scale");
        if (lua_isnumber(L, -1)) scale = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, 2, "show_controls");
        if (lua_isboolean(L, -1)) show_controls = lua_toboolean(L, -1);
        lua_pop(L, 1);
    }

    if (airui_mode) {
        nes_airui_video_config_t cfg;
        nes_airui_video_get_default_config(&cfg);
        cfg.scale         = scale;
        cfg.show_controls = show_controls;
        if (!nes_airui_video_init(&cfg)) {
            LLOGE("nes: AirUI video init failed");
            lua_pushboolean(L, 0);
            return 1;
        }
        nes_set_airui_mode(1);
    }
#endif
    nes = nes_init();
    if (!nes){
        return 0;
    }
    nes_load_file(nes, nes_rom);
    if (luat_rtos_task_create(&nes_thread, 4*1024, 50, "nes", nes_task, nes, 0)){
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
nes模拟器反初始化，释放资源
@api nes.deinit()
@usage
nes.deinit()
*/
static int l_nes_deinit(lua_State *L) {
    (void)L;
    if (nes) {
        nes_t *ctx = nes;
        nes = NULL;  /* 先清全局指针，防止 nes_draw/nes_frame 继续写入 */

        /* 设置退出标志，让 nes_run() 的 while 循环在本帧末尾退出 */
        ctx->nes_quit = 1;

        /* 等待至多 2 帧（PC 上约 30ms/帧）让任务自行退出 */
        luat_timer_mdelay(80);

        /* 强制删除任务（若任务已退出，delete 通常为 no-op 或返回错误，不会崩溃） */
        if (nes_thread) {
            luat_rtos_task_delete(nes_thread);
            nes_thread = NULL;
        }

        /* 释放 ROM / PPU 内存 */
        nes_deinit(ctx);
    }

#ifdef LUAT_USE_AIRUI
    nes_set_airui_mode(0);
    nes_airui_video_deinit(NULL);
#endif
    return 0;
}
/*
nes模拟器初始化
@api nes.key(key,val)
@number key 按键
@number val 状态 1按下 0抬起
@return bool 成功返回true,否则返回false
@usage
nes.init("/luadb/super_mario.nes")
*/
static int l_nes_key(lua_State *L) {
    int key = luaL_checkinteger(L, 1);
    int val = luaL_checkinteger(L, 2);
    switch (key){
        case Up:
            nes->nes_cpu.joypad.U1 = val;
            break;
        case Down:
            nes->nes_cpu.joypad.D1 = val;
            break;
        case Left:
            nes->nes_cpu.joypad.L1 = val;
            break;
        case Right:
            nes->nes_cpu.joypad.R1 = val;
            break;
        case A:
            nes->nes_cpu.joypad.A1 = val;
            break;
        case B:
            nes->nes_cpu.joypad.B1 = val;
            break;
        case Start:
            nes->nes_cpu.joypad.ST1 = val;
            break;
        case Select:
            nes->nes_cpu.joypad.SE1 = val;
            break;
        default:
            break;
    }
    return 0;
}

/*
查询 AirUI 模式下用户是否点击了退出按钮
@api nes.quit_requested()
@return bool 已点击退出则返回true
@usage
if nes.quit_requested() then
    nes.deinit()
end
*/
static int l_nes_quit_requested(lua_State *L) {
#ifdef LUAT_USE_AIRUI
    lua_pushboolean(L, nes_airui_video_quit_requested(NULL));
#else
    lua_pushboolean(L, 0);
#endif
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_nes[] =
{
    {"init",            ROREG_FUNC(l_nes_init)          },
    {"key",             ROREG_FUNC(l_nes_key)            },
    {"deinit",          ROREG_FUNC(l_nes_deinit)         },
    {"quit_requested",  ROREG_FUNC(l_nes_quit_requested) },

    //@const Up 按键上
    { "Up",     ROREG_INT(Up)           },
    //@const Down 按键下
    { "Down",   ROREG_INT(Down)         },
    //@const Left 按键左
    { "Left",   ROREG_INT(Left)         },
    //@const Right 按键右
    { "Right",  ROREG_INT(Right)        },
    //@const A 按键A
    { "A",      ROREG_INT(A)            },
    //@const B 按键B
    { "B",      ROREG_INT(B)            },
    //@const Start 按键开始
    { "Start",  ROREG_INT(Start)        },
    //@const Select 按键选择
    { "Select", ROREG_INT(Select)       },
	{ NULL,     ROREG_INT(0)}
};
LUAMOD_API int luaopen_nes( lua_State *L ) {
    luat_newlib2(L, reg_nes);
    return 1;
}
