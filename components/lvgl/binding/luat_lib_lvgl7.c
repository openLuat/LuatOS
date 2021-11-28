
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

#if !defined (LUA_USE_WINDOWS) && !defined (LUA_USE_LINUX)
#include "luat_lcd.h"

static luat_lcd_conf_t* lcd_conf;

LUAT_WEAK luat_lv_disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p) {
    //-----
    if (lcd_conf != NULL) {
#ifdef LV_NO_BLOCK_FLUSH
    	luat_lcd_draw_no_block(lcd_conf, area->x1, area->y1, area->x2, area->y2, color_p, disp_drv->buffer->flushing_last);
#else
        luat_lcd_draw(lcd_conf, area->x1, area->y1, area->x2, area->y2, color_p);
#endif
    }
    // LLOGD("CALL disp_flush (%d, %d, %d, %d)", area->x1, area->y1, area->x2, area->y2);
    lv_disp_flush_ready(disp_drv);
}
#endif

#ifdef LUA_USE_WINDOWS
#include <windows.h>
extern uint32_t WINDOW_HOR_RES;
extern uint32_t WINDOW_VER_RES;
#endif

/**
初始化LVGL
@api lvgl.init(w, h, lcd, buff_mode)
@int 屏幕宽,可选,默认从lcd取
@int 屏幕高,可选,默认从lcd取
@userdata lcd指针,可选,lcd初始化后有默认值,预留的多屏入口
@int 缓冲区大小,默认宽*10, 不含色深.
@int 缓冲模式,默认0, 单buff模式, 可选1,双buff模式
@return bool 成功返回true,否则返回false
 */
int luat_lv_init(lua_State *L) {
    if (LV.disp != NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    #ifdef LUA_USE_WINDOWS
    if (lua_isnumber(L, 1) && lua_isnumber(L, 2)) {
        WINDOW_HOR_RES= luaL_checkinteger(L, 1);
        WINDOW_VER_RES = luaL_checkinteger(L, 2);
    }
    HWND windrv_init(void);
    windrv_init();
    lua_pushboolean(L, 1);
    return 1;
    #elif defined(LUA_USE_LINUX)
    //lvgl_linux_init();
    lua_pushboolean(L, 1);
    return 1;
    #else

    lv_color_t *fbuffer = NULL;
    lv_color_t *fbuffer2 = NULL;
    size_t fbuff_size = 0;
    bool buffmode = 0;

    if (lua_isuserdata(L, 3)) {
        lcd_conf = lua_touserdata(L, 3);
    }
    else {
        lcd_conf = luat_lcd_get_default();
    }
    if (lcd_conf == NULL) {
        LLOGE("setup lcd first!!");
        return 0;
    }

    int w = lcd_conf->w;
    int h = lcd_conf->h; 
    if (lua_isinteger(L, 1))
        w = luaL_checkinteger(L, 1);
    if (lua_isinteger(L, 2))
        h = luaL_checkinteger(L, 2);

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
        if (buffmode < 0)
            buffmode =0;
    }


    LLOGD("w %d h %d buff %d mode %d", w, h, fbuff_size, buffmode);

    if (buffmode & 0x02) {
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
    LV.disp = lv_disp_drv_register(&my_disp_drv);
    //LLOGD(">>%s %d", __func__, __LINE__);
    lua_pushboolean(L, LV.disp != NULL ? 1 : 0);
    //LLOGD(">>%s %d", __func__, __LINE__);
    return 1;
    #endif
}
