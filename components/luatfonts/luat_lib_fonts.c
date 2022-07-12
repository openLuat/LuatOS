/*
@module  fonts
@summary 字体库
@version 1.0
@date    2022.07.11
*/


#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "fonts"
#include "luat_log.h"

#include "u8g2.h"
#include "u8g2_luat_fonts.h"

typedef struct u8g2_font
{
    const char* name;
    const uint8_t* font;
}u8g2_font_t;

static u8g2_font_t u8g2_fonts[] = {
#ifdef USE_U8G2_OPPOSANSM_ENGLISH
    {.name="unifont_t_symbols", .font=u8g2_font_unifont_t_symbols},
    {.name="open_iconic_weather_6x_t", .font=u8g2_font_open_iconic_weather_6x_t},
    {.name="opposansm8", .font=u8g2_font_opposansm8},
    {.name="opposansm10", .font=u8g2_font_opposansm10},
    {.name="opposansm12", .font=u8g2_font_opposansm12},
    {.name="opposansm16", .font=u8g2_font_opposansm16},
    {.name="opposansm20", .font=u8g2_font_opposansm20},
    {.name="opposansm24", .font=u8g2_font_opposansm24},
    {.name="opposansm32", .font=u8g2_font_opposansm32},
#endif
#ifdef USE_U8G2_OPPOSANSM8_CHINESE
    {.name="opposansm8_chinese", .font=u8g2_font_opposansm8_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM10_CHINESE
    {.name="opposansm10_chinese", .font=u8g2_font_opposansm10_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM12_CHINESE
    {.name="opposansm12_chinese", .font=u8g2_font_opposansm12_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM16_CHINESE
    {.name="opposansm16_chinese", .font=u8g2_font_opposansm16_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM18_CHINESE
    {.name="opposansm18_chinese", .font=u8g2_font_opposansm18_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM20_CHINESE
    {.name="opposansm20_chinese", .font=u8g2_font_opposansm20_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM22_CHINESE
    {.name="opposansm22_chinese", .font=u8g2_font_opposansm22_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM24_CHINESE
    {.name="opposansm24_chinese", .font=u8g2_font_opposansm24_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM32_CHINESE
    {.name="opposansm32_chinese", .font=u8g2_font_opposansm32_chinese},
#endif

#ifdef LUAT_FONTS_CUSTOM_U8G2
    LUAT_FONTS_CUSTOM_U8G2
#endif
    {.name="", .font=NULL},
};

/*
获取u8g2字体
@api fonts.u8g2_get(name)
@string 字体名称, 例如opposansm8_chinese unifont_t_symbols
@return userdata 若字体存放,返回字体指针, 否则返回nil
@usage
oppo_8 = fonts.u8g2_get("opposansm8_chinese")
if oppo_8 then
    u8g2.SetFont(oppo_8)
else
    log.warn("fonts", "no such font opposansm8_chinese")
end
*/
static int l_fonts_u8g2_get(lua_State *L) {
    const char* name = luaL_checkstring(L,  1);
    u8g2_font_t *font = u8g2_fonts;
    while (font->font != NULL) {
        if (!strcmp(name, font->name)) {
            lua_pushlightuserdata(L, font->font);
            return 1;
        }
        font ++;
    }
    return 0;
}

/*
从文件加载u8g2字体
@api fonts.u8g2_load(path)
@string 字体路径, 例如 /luadb/abc.bin
@return userdata 若字体存放,返回字体指针, 否则返回nil
@usage
-- API新增于2022-07-11
-- 提醒: 若文件位于/luadb下, 不需要占用内存
-- 若文件处于其他路径, 例如tf/sd卡, spi flash, 会自动加载到内存, 消耗lua vm的内存空间
-- 加载后请适当引用, 不必反复加载同一个字体文件
oppo12 = fonts.u8g2_load("/luadb/oppo12.bin")
if oppo12 then
    u8g2.SetFont(oppo12)
else
    log.warn("fonts", "no such font file oppo12.bin")
end
*/
static int l_fonts_u8g2_load(lua_State *L) {
    char* ptr = NULL;
    // 从文件加载
    const char* path = luaL_checkstring(L, 1);
    size_t flen = luat_fs_fsize(path);
    if (flen < 16) {
        LLOGE("not a good font file %s", path);
        return 0;
    }
    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGE("no such file %s", path);
        return 0;
    }
#ifdef LUAT_USE_FS_VFS
  //LLOGD("try mmap");
  ptr = (char*)luat_vfs_mmap(fd);
  if (ptr != NULL) {
    LLOGD("load by mmap %s %p", path, ptr);
    lua_pushlightuserdata(L, ptr);
    luat_fs_fclose(fd);
    return 1;
  }
#endif
    ptr = lua_newuserdata(L, flen);
    if (ptr == NULL) {
        luat_fs_fclose(fd);
        LLOGE("no engouh memory for font %s", path);
        return 0;
    }
    char buff[256];
    int len = 0;
    int count = 0;
    while (count < flen)
    {
        len = luat_fs_fread(buff, 256, 1, fd);
        if (len < 0)
            break;
        if (len > 0) {
            memcpy(ptr + count, buff, len);
            count += len;
        }
    }
    luat_fs_fclose(fd);
    lua_pushlightuserdata(L, ptr);
    return 1;
}

/*
返回固件支持的u8g2字体列表
@api fonts.u8g2_list()
@return table 字体列表
@usage
-- API新增于2022-07-12
if fonts.u8g2_list then
    log.info("fonts", "u8g2", json.encode(fonts.u8g2_list()))
end
*/
static int l_fonts_u8g2_list(lua_State *L) {
    const char* name = luaL_checkstring(L,  1);
    u8g2_font_t *font = u8g2_fonts;
    lua_createtable(L, 10, 0);
    while (font->font != NULL) {
        lua_pushstring(L, font->name);
    }
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_fonts[] =
{
    { "u8g2_get" ,       ROREG_FUNC(l_fonts_u8g2_get)},
    { "u8g2_load" ,      ROREG_FUNC(l_fonts_u8g2_load)},
	{ NULL,              ROREG_INT(0)},
};

LUAMOD_API int luaopen_fonts( lua_State *L ) {
    luat_newlib2(L, reg_fonts);
    return 1;
}
