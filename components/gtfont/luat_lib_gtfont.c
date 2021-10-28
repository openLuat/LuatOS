#include "luat_base.h"
#include "luat_spi.h"

#include "GT5SLCD2E_1A.h"
#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

extern luat_spi_device_t* gt_spi_dev;

static int l_gtfont_init(lua_State* L) {
    if (gt_spi_dev == NULL) {
        gt_spi_dev = lua_touserdata(L, 1);
    }
    return 0;
}

static VECFONT_ST fst;

static int l_gtfont_test(lua_State* L) {
    fst.fontCode = luaL_checkinteger(L, 1);
    fst.type = luaL_checkinteger(L, 2);
    fst.size = luaL_checkinteger(L, 3);
    fst.thick = luaL_checkinteger(L, 4);
    LLOGD("fontCode %04X type %02X size %02X thick %02X", fst.fontCode, fst.type, fst.size, fst.thick);
    int w = get_font_st(&fst);
    LLOGD("get_font_st ret %02X", w);

    // TODO 按位显示出来

    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_gtfont[] =
{
    { "init" ,          l_gtfont_init , 0},
    { "test" ,          l_gtfont_test , 0},
	{ NULL,             NULL ,        0}
};

LUAMOD_API int luaopen_gtfont( lua_State *L ) {
    luat_newlib(L, reg_gtfont);
    return 1;
}
