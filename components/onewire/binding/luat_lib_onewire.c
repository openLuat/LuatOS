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

static const uint8_t crc8_maxim[256] = {
    0, 94, 188, 226, 97, 63, 221, 131, 194, 156, 126, 32, 163, 253, 31, 65,
    157, 195, 33, 127, 252, 162, 64, 30, 95, 1, 227, 189, 62, 96, 130, 220,
    35, 125, 159, 193, 66, 28, 254, 160, 225, 191, 93, 3, 128, 222, 60, 98,
    190, 224, 2, 92, 223, 129, 99, 61, 124, 34, 192, 158, 29, 67, 161, 255,
    70, 24, 250, 164, 39, 121, 155, 197, 132, 218, 56, 102, 229, 187, 89, 7,
    219, 133, 103, 57, 186, 228, 6, 88, 25, 71, 165, 251, 120, 38, 196, 154,
    101, 59, 217, 135, 4, 90, 184, 230, 167, 249, 27, 69, 198, 152, 122, 36,
    248, 166, 68, 26, 153, 199, 37, 123, 58, 100, 134, 216, 91, 5, 231, 185,
    140, 210, 48, 110, 237, 179, 81, 15, 78, 16, 242, 172, 47, 113, 147, 205,
    17, 79, 173, 243, 112, 46, 204, 146, 211, 141, 111, 49, 178, 236, 14, 80,
    175, 241, 19, 77, 206, 144, 114, 44, 109, 51, 209, 143, 12, 82, 176, 238,
    50, 108, 142, 208, 83, 13, 239, 177, 240, 174, 76, 18, 145, 207, 45, 115,
    202, 148, 118, 40, 171, 245, 23, 73, 8, 86, 180, 234, 105, 55, 213, 139,
    87, 9, 235, 181, 54, 104, 138, 212, 149, 203, 41, 119, 244, 170, 72, 22,
    233, 183, 85, 11, 136, 214, 52, 106, 43, 117, 151, 201, 74, 20, 246, 168,
    116, 42, 200, 150, 21, 75, 169, 247, 182, 232, 10, 84, 215, 137, 107, 53};

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
    luat_os_entry_cri();
    ret = luat_onewire_setup(&ctx);
    if (ret)
    {
        LLOGW("setup失败 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        goto exit;
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
        LLOGW("connect失败 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        goto exit;
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
        LLOGW("connect失败2 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        goto exit;
    }

    wdata[1] = 0xBE;
    luat_onewire_write(&ctx, wdata, 2);

    uint8_t data[9] = {0};
    // 校验模式读9个字节, 否则读2个字节
    ret = luat_onewire_read(&ctx, (char*)data, check_crc ? 9 : 2);
    luat_onewire_close(&ctx); // 后续不需要读取的
    if (ret != 9)
    {
        LLOGW("read失败2 mode %d id %d ret %d", ctx.mode, ctx.id, ret);
        goto exit;
    }

    if (check_crc)
    {
        uint8_t crc = 0;
        for (size_t i = 0; i < 8; i++){
            crc = crc8_maxim[crc ^ data[i]];
        }
        if (crc != data[8]) {
            LLOGD("crc %02X %02X", crc, data[8]);
            goto exit;
        }
    }

    uint8_t TL, TH;
    int32_t tem;
    int32_t val;

    TL = data[0];
    TH = data[1];

    // LLOGD("读出的数据");
    // LLOGDUMP(data, 9);

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
    luat_os_exit_cri();
    return 1;
exit:
    luat_onewire_close(&ctx); // 清理并关闭
    luat_os_exit_cri();
    return 0;
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
