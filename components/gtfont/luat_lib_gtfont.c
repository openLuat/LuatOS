/*
@module  gtfont
@summary 高通字库芯片
@version 1.0
@date    2021.11.11
@tag LUAT_USE_GTFONT
@usage
-- 已测试字体芯片型号 GT5SLCD1E-1A
-- 如需要支持其他型号,请报issue
*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_gtfont.h"

#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

/**
初始化高通字体芯片
@api gtfont.init(spi_device)
@userdata 仅支持spi device 生成的指针数据
@return boolean 成功返回true,否则返回false
@usage
-- 特别提醒: 使用本库的任何代码,都需要额外的高通字体芯片 !!
-- 没有额外芯片是跑不了的!!
gtfont.init(spi_device)
*/
static int l_gtfont_init(lua_State* L) {
    if (gt_spi_dev == NULL) {
        gt_spi_dev = lua_touserdata(L, 1);
    }
	const char data = 0xff;
	luat_spi_device_send(gt_spi_dev, &data, 1);
	int font_init = GT_Font_Init();
    // LLOGD("font_init:%d",font_init);
	lua_pushboolean(L, font_init > 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_gtfont[] =
{
    { "init" ,          ROREG_FUNC(l_gtfont_init)},
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_gtfont( lua_State *L ) {
    luat_newlib2(L, reg_gtfont);
    return 1;
}
