/*
@module  ufont
@summary 统一字体库(开发中)
@version 1.0
@date    2022.08.05
@usage
-- 尚处于开发阶段,暂不可用
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_fs.h"
#include "string.h"

#define LUAT_LOG_TAG "ufont"
#include "luat_log.h"

#include "luat_ufont.h"

extern const luat_font_desc_t luat_font_sarasa_bold_16;
extern const lv_font_t luat_font_sarasa_bold_16_lvgl;

typedef struct ufont_reg
{
    const char* name;
    const lv_font_t* font;
}ufont_reg_t;

const ufont_reg_t ufonts[] = {
#ifdef LUAT_UFONT_FONTS_SARASA_BOLD_16
    {.name="sarasa_bold_16", .font=&luat_font_sarasa_bold_16_lvgl},
#endif
    {.name = NULL, .font = (NULL)}
};

/*
获取字体
@api ufont.get(name)
@string 字体名称, 例如
@return userdata 若字体存在,返回字体指针, 否则返回nil
@usage
-- TODO
*/
static int l_ufont_get(lua_State *L) {
    const char* font_name = luaL_optstring(L, 1, "sarasa_bold_16");
    ufont_reg_t* reg = ufonts;
    while (reg->font != NULL) {
        //LLOGD("[%s] - [%s]", reg->name, font_name);
        if (strcmp(reg->name, font_name) == 0) {
            lua_pushlightuserdata(L, reg->font);
            return 1;
        }
        reg++;
    }
    LLOGW("font not exists [%s]", font_name);
    return 0;
}

/*
返回固件支持的字体列表
@api ufont.list()
@return table 字体列表
@usage
-- API新增于2022-08-05
log.info("fonts", "u8g2", json.encode(ufont.list()))
*/
static int l_ufont_list(lua_State *L) {
    ufont_reg_t* reg = ufonts;
    lua_createtable(L, 10, 0);
    int index = 1;
    while (reg->font != NULL) {
        lua_pushinteger(L, index);
        lua_pushstring(L, reg->name);
        lua_settable(L, -3);
        index ++;
        reg ++;
    }
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_ufont[] =
{
    { "get" ,       ROREG_FUNC(l_ufont_get)},
    { "list" ,      ROREG_FUNC(l_ufont_list)},
	{ NULL,         ROREG_INT(0)},
};

LUAMOD_API int luaopen_ufont( lua_State *L ) {
    luat_newlib2(L, reg_ufont);
    return 1;
}
