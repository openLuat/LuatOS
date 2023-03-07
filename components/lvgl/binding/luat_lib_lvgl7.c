/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "luat_malloc.h"
#include "luat_zbuff.h"

typedef struct luat_lv {
    lv_disp_t* disp;
    lv_disp_buf_t disp_buf;
    int buff_ref;
    int buff2_ref;
}luat_lv_t;

static luat_lv_t LV = {0};
//static lv_disp_drv_t my_disp_drv;


/**
初始化LVGL
@api lvgl.init(w, h, lcd, buff_size, buff_mode)
@int 屏幕宽,可选,默认从lcd取
@int 屏幕高,可选,默认从lcd取
@userdata lcd指针,可选,lcd初始化后有默认值,预留的多屏入口
@int 缓冲区大小,默认宽*10, 不含色深.
@int 缓冲模式,默认0, 单buff模式, 可选1,双buff模式
@return bool 成功返回true,否则返回false
 */
int luat_lv_init(lua_State *L);

#ifdef LUAT_USE_LVGL_SDL2
#include "luat_lcd.h"
// SDL2 模式
extern lv_disp_t *lv_sdl_init_display(const char* win_name, int width, int height);
extern lv_indev_t *lv_sdl_init_input(void);
#endif
#if defined(LUAT_EMULATOR_MODE)
// 模拟器模式
int luat_lv_init(lua_State *L) {
    LLOGE("emulator mode init");
    int w = 480;
    int h = 320;

    if (lua_isnumber(L, 1) && lua_isnumber(L, 2)) {
        w = luaL_checkinteger(L, 1);
        h = luaL_checkinteger(L, 2);
    }

    extern void emulator_lvgl_init(int w, int h);
    emulator_lvgl_init(w, h);
    return 0;
}
// #elif defined(LUA_USE_WINDOWS)
// // win32遗留模式
// #include <windows.h>
// extern uint32_t WINDOW_HOR_RES;
// extern uint32_t WINDOW_VER_RES;
// int luat_lv_init(lua_State *L) {
//     if (lua_isnumber(L, 1) && lua_isnumber(L, 2)) {
//         WINDOW_HOR_RES = luaL_checkinteger(L, 1);
//         WINDOW_VER_RES = luaL_checkinteger(L, 2);
//     }
//     LLOGD("win32 lvgl init %d %d", WINDOW_HOR_RES, WINDOW_VER_RES);
//     HWND windrv_init(void);
//     windrv_init();
//     lua_pushboolean(L, 1);
//     return 1;
// }

#elif defined(LUAT_USE_LVGL_INIT_CUSTOM)
// 自定义模式, 这个由bsp自行实现了

#else
// 普通MCU模式
#include "luat_lcd.h"

static luat_lcd_conf_t* lcd_conf;

LUAT_WEAK void luat_lv_disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p) {
    //-----
    if (lcd_conf != NULL) {
        luat_lcd_draw(lcd_conf, area->x1, area->y1, area->x2, area->y2, color_p);
        if (disp_drv->buffer->flushing_last)
            luat_lcd_flush(lcd_conf);
    }
    //LLOGD("CALL disp_flush (%d, %d, %d, %d)", area->x1, area->y1, area->x2, area->y2);
    lv_disp_flush_ready(disp_drv);
}
int luat_lv_init(lua_State *L) {
    int w = 0;
    int h = 0;

    if (LV.disp != NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }

    if (lua_isnumber(L, 1) && lua_isnumber(L, 2)) {
        w = luaL_checkinteger(L, 1);
        h = luaL_checkinteger(L, 2);
    }

    lv_color_t *fbuffer = NULL;
    lv_color_t *fbuffer2 = NULL;
    size_t fbuff_size = 0;
    size_t buffmode = 0;

    if (lua_isuserdata(L, 3)) {
        lcd_conf = lua_touserdata(L, 3);
    }
    else {
        lcd_conf = luat_lcd_get_default();
    }
    if (lcd_conf == NULL) {
        #if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS)
        if (w == 0 || h == 0) {
            w = 800;
            h = 640;
        }
        #else
        LLOGE("setup lcd first!!");
        return 0;
        #endif
    }
    if (w == 0 || h == 0) {
        w = lcd_conf->w;
        h = lcd_conf->h;
    }

    if (lua_isinteger(L, 4)) {
        fbuff_size = luaL_checkinteger(L, 4);
        if (fbuff_size < w*10)
            fbuff_size = w * 10;
    }
    else {
        fbuff_size = w * 10;
    }

    if (lua_isinteger(L, 5)) {
        buffmode = luaL_checkinteger(L, 5);
    }

    LLOGD("w %d h %d buff %d mode %d", w, h, fbuff_size, buffmode);

    if (lcd_conf != NULL && lcd_conf->buff != NULL) {
        //LLOGD("use LCD buff");
        fbuffer = lcd_conf->buff;
        fbuff_size = w * h;
    }
    else if (buffmode & 0x02) {
        //LLOGD("use HEAP buff");
        fbuffer = luat_heap_malloc(fbuff_size * sizeof(lv_color_t));
        if (fbuffer == NULL) {
            LLOGD("not enough memory");
            return 0;
        }
        if (buffmode & 0x01) {
            fbuffer2 = luat_heap_malloc(fbuff_size * sizeof(lv_color_t));
            if (fbuffer2 == NULL) {
                luat_heap_free(fbuffer);
                LLOGD("not enough memory");
                return 0;
            }
        }
    }
    else {
        //LLOGD("use VM buff");
        fbuffer = lua_newuserdata(L, fbuff_size * sizeof(lv_color_t));
        if (fbuffer == NULL) {
            LLOGD("not enough memory");
            return 0;
        }
        if (buffmode & 0x01) {
            fbuffer2 = lua_newuserdata(L, fbuff_size * sizeof(lv_color_t));
            if (fbuffer2 == NULL) {
                LLOGD("not enough memory");
                return 0;
            }
        }
        // 引用即弹出
        if (fbuffer2)
            LV.buff2_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        LV.buff_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }

    lv_disp_buf_init(&LV.disp_buf, fbuffer, fbuffer2, fbuff_size);

    lv_disp_drv_t my_disp_drv;
    lv_disp_drv_init(&my_disp_drv);

    my_disp_drv.flush_cb = luat_lv_disp_flush;

    my_disp_drv.hor_res = w;
    my_disp_drv.ver_res = h;
    my_disp_drv.buffer = &LV.disp_buf;
    //LLOGD(">>%s %d", __func__, __LINE__);

#ifdef LUAT_USE_LVGL_SDL2
    if (lcd_conf == NULL) {
        LLOGD("use LVGL-SDL2");
        LV.disp =lv_sdl_init_display("LuatOS", w, h);
        lv_sdl_init_input();
        lua_pushboolean(L, LV.disp != NULL ? 1 : 0);
        return 1;
    }
#endif
    LV.disp = lv_disp_drv_register(&my_disp_drv);
    //LLOGD(">>%s %d", __func__, __LINE__);
    lua_pushboolean(L, LV.disp != NULL ? 1 : 0);
#ifdef LUAT_USE_LVGL_SDL2
    LLOGD("use LVGL-LCD-SDL2 swap %d", LV_COLOR_16_SWAP);
    lv_sdl_init_input();
#endif
#ifdef __LVGL_SLEEP_ENABLE__
    luat_lvgl_tick_sleep(0);
#endif
    return 1;
}
#endif
