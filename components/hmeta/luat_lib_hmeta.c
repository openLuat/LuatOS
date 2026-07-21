/*
@module  hmeta
@summary 硬件元数据
@version 1.0
@date    2022.01.11
@demo    hmeta
@tag LUAT_USE_HMETA
@usage
-- 本库开发中
--[[
    这个库的作用是展示当前硬件的能力, 例如:
1. 有多少GPIO, 各GPIO默认模式是什么, 是否支持上拉/下拉
2. 有多少I2C,支持哪些速率
3. 有多少SPI,支持哪些速率和模式
4. 扩展属性, 例如区分Air780E和Air600E

]]
*/
#include "luat_base.h"
#include "luat_hmeta.h"

/*
获取模组名称
@api hmeta.model()
@return string 若能识别到,返回模组类型, 否则会是nil
@usage
sys.taskInit(function()
    while 1 do
        sys.wait(3000)
        -- hmeta识别底层模组类型的
        -- 不同的模组可以使用相同的bsp,但根据封装的不同,根据内部数据仍可识别出具体模块
        log.info("hmeta", hmeta.model())
        log.info("bsp",   rtos.bsp())
    end
end)
*/
static int l_hmeta_model(lua_State *L) {
    char buff[40] = {0};
    luat_hmeta_model_name(buff);
    if (strlen(buff)) {
        lua_pushstring(L, buff);
    }
    else {
        lua_pushnil(L);
    }
    return 1;
}

/*
获取模组的硬件版本号
@api hmeta.hwver()
@return string 若能识别到,返回模组类型, 否则会是nil
@usage
sys.taskInit(function()
    while 1 do
        sys.wait(3000)
        -- hmeta识别底层模组类型的
        -- 不同的模组可以使用相同的bsp,但根据封装的不同,根据内部数据仍可识别出具体模块
        log.info("hmeta", hmeta.model(), hmeta.hwver())
        log.info("bsp",   rtos.bsp())
    end
end)
*/
static int l_hmeta_hwver(lua_State *L) {
    char buff[40] = {0};
    luat_hmeta_hwversion(buff);
    if (strlen(buff)) {
        lua_pushstring(L, buff);
    }
    else {
        lua_pushnil(L);
    }
    return 1;
}

/*
获取原始芯片型号
@api hmeta.chip()
@return string 若能识别到,返回芯片类型, 否则会是nil
@usage
-- 若底层正确实现, 这个函数总会返回值
-- 本函数于 2024.12.5 新增
*/
static int l_hmeta_chip(lua_State *L) {
    char buff[16] = {0};
    luat_hmeta_chip(buff);
    if (strlen(buff)) {
        lua_pushstring(L, buff);
    }
    else {
        lua_pushnil(L);
    }
    return 1;
}

/*
获取模组muid
@api hmeta.muid()
@return string 模组muid, 32字节的字符串,如果不支持, 会返回空字符串.
@usage
local muid = hmeta.muid()
print("muid", muid)
*/
int l_hmeta_muid(lua_State* L) {
	char muid[34] = {0};
	luat_hmeta_muid(muid, 33);
	// LLOGD("muid %s", muid);
	lua_pushstring(L, muid);
    return 1;
}

/*
获取模组的识别id
@api hmeta.devid()
@return string 模组识别id,总是可见字符组成
@usage
-- 对于4G模组, devid就是IMEI
-- 对于WiFi模组, devid就是MAC地址
-- 对于MCU模组, 与生产流程有关
-- 本函数于2026.7.18新增
*/
static int l_hmeta_devid(lua_State* L) {
	char devid[34] = {0};
	luat_hmeta_devid(devid, 33);
	// LLOGD("devid %s", devid);
	lua_pushstring(L, devid);
    return 1;
}

extern int l_mcu_unique_id(lua_State* L);


#include "rotable2.h"
static const rotable_Reg_t reg_hmeta[] =
{
    { "model" ,           ROREG_FUNC(l_hmeta_model)},
    { "hwver" ,           ROREG_FUNC(l_hmeta_hwver)},
    { "chip" ,            ROREG_FUNC(l_hmeta_chip)},
	{ "devid",            ROREG_FUNC(l_hmeta_devid)},
	{ "muid",         	  ROREG_FUNC(l_hmeta_muid)},
    { "unique_id",        ROREG_FUNC(l_mcu_unique_id)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_hmeta( lua_State *L ) {
    luat_newlib2(L, reg_hmeta);
    return 1;
}
