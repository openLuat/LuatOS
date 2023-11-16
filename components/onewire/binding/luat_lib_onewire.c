/*
@module  onewire
@summary 单总线协议驱动
@version 1.0
@date    2023.11.16
@author  wendal
@tag     LUAT_USE_ONEWIRE
@demo    onewire
@usage
-- 本代码库尚处于开发阶段
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_onewire.h"

#define LUAT_LOG_TAG "onewire"
#include "luat_log.h"

static int l_onewire_open(lua_State *L)
{
    return 0;
}

static int l_onewire_close(lua_State *L)
{
    return 0;
}

/*
读取DS18B20
@api onewire.ds18b20(mode, pin, check)
@int 模式, 只能是 onewire.GPIO 或者 onewire.HW
@int GPIO模式对应GPIO编号, HW模式根据实际硬件来确定
@boolean 是否检查数据的CRC值
@return number 成功返回温度值,否则返回nil.单位 0.1摄氏度
@usage

-- GPIO模式,接 GPIO 9
local temp = onewire.ds18b20(onewire.GPIO, 9, true)
if temp then
    log.info("读取到的温度值", temp)
else
    log.info("读取失败")
end

*/
static int l_onewire_ds18b20(lua_State *L)
{
    luat_onewire_ctx_t ctx = {0};
    int ret = 0;
    ctx.mode = luaL_checkinteger(L, 1);
    ctx.id = luaL_checkinteger(L, 2);
    int check_crc = lua_toboolean(L, 3);
    // 初始化单总线
    ret = luat_onewire_setup(&ctx);
    if (ret)
    {
        luat_onewire_close(&ctx);
        LLOGW("setup失败 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        return 0;
    }
    // 复位设备
    ret = luat_onewire_reset(&ctx);
    // if (ret) {
    //     LLOGW("reset失败 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
    //     return 0;
    // }
    // 建立连接
    ret = luat_onewire_connect(&ctx);
    if (ret)
    {
        luat_onewire_close(&ctx);
        LLOGW("connect失败 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        return 0;
    }
    // 写入2字节的数据
    char wdata[] = {0xCC, 0x44}; /* skip rom */ /* convert */
    luat_onewire_write(&ctx, wdata, 2);

    // 再次复位
    luat_onewire_reset(&ctx);
    // 再次建立连接
    ret = luat_onewire_connect(&ctx);
    if (ret)
    {
        luat_onewire_close(&ctx);
        LLOGW("connect失败2 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        return 0;
    }

    wdata[1] = 0xCE;
    luat_onewire_write(&ctx, wdata, 2);

    uint8_t data[9] = {0};
    // 校验模式读9个字节, 否则读2个字节
    ret = luat_onewire_read(&ctx, (char*)data, check_crc ? 9 : 2);
    luat_onewire_close(&ctx); // 后续不需要读取的
    if (ret != 9)
    {
        luat_onewire_close(&ctx);
        LLOGW("read失败2 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        return 0;
    }

    if (check_crc)
    {
        // TODO 校验数据
    }

    uint8_t TL, TH;
    int32_t tem;
    int32_t val;

    TL = data[0];
    TH = data[1];

    if (TH > 7)
    {
        TH = ~TH;
        TL = ~TL;
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        val = -tem;
    }
    else
    {
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        val = tem;
    }
    lua_pushinteger(L, val);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_onewire[] =
    {
        {"ds18b20", ROREG_FUNC(l_onewire_ds18b20)},
        {"open", ROREG_FUNC(l_onewire_open)},
        {"close", ROREG_FUNC(l_onewire_close)},

        {"GPIO", ROREG_INT(1)},
        {"HW", ROREG_INT(2)},
        {NULL, ROREG_INT(0)}
    };

LUAMOD_API int luaopen_onewire(lua_State *L)
{
    luat_newlib2(L, reg_onewire);
    return 1;
}
