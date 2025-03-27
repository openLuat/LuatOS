
/*
@module  adc
@summary 模数转换
@version 1.0
@date    2020.07.03
@demo adc
@tag LUAT_USE_ADC
@usage

-- 本库可读取硬件adc通道, 也支持读取CPU温度和VBAT供电电源(若模块支持的话)

-- 读取CPU温度, 单位为0.001摄氏度, 是内部温度, 非环境温度
adc.open(adc.CH_CPU)
local temp = adc.get(adc.CH_CPU)
adc.close(adc.CH_CPU)

-- 读取VBAT供电电压, 单位为mV
adc.open(adc.CH_VBAT)
local vbat = adc.get(adc.CH_VBAT)
adc.close(adc.CH_VBAT)

-- 物理ADC通道请查阅adc.get或者adc.read的注释
*/
#include "luat_base.h"
#include "luat_adc.h"

/**
打开adc通道
@api adc.open(id)
@int 通道id,与具体设备有关,通常从0开始
@return boolean 打开结果
@usage
-- 打开adc通道4,并读取
if adc.open(4) then
    log.info("adc", adc.read(4)) -- 返回值有2个, 原始值和计算值,通常只需要后者
    log.info("adc", adc.get(4))  -- 返回值有1个, 仅计算值
end
adc.close(4) -- 若需要持续读取, 则不需要close, 功耗会高一点.
 */
static int l_adc_open(lua_State *L) {
    if (luat_adc_open(luaL_checkinteger(L, 1), NULL) == 0) {
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/**
设置ADC的测量范围，注意这个和具体芯片有关，目前只支持air105/Air780EXXX系列
@api adc.setRange(range)
@int range参数,与具体设备有关,比如air105填adc.ADC_RANGE_1_8和adc.ADC_RANGE_3_6
@return nil
@usage
-- 本函数要在调用adc.open之前就调用, 之后调用无效!!!

-- 关闭air105内部分压
adc.setRange(adc.ADC_RANGE_1_8)
-- 打开air105内部分压
adc.setRange(adc.ADC_RANGE_3_6)


-- Air780EXXX支持多种，但是建议用以下2种
adc.setRange(adc.ADC_RANGE_MIN) -- 关闭分压
adc.setRange(adc.ADC_RANGE_MAX) -- 启用分压
 */
static int l_adc_set_range(lua_State *L) {
	luat_adc_global_config(ADC_SET_GLOBAL_RANGE, luaL_checkinteger(L, 1));
	return 0;
}

/**
读取adc通道
@api adc.read(id)
@int 通道id,与具体设备有关,通常从0开始
@return int 原始值,一般没用,可以直接抛弃
@return int 从原始值换算得出的实际值，通常单位是mV
@usage
-- 打开adc通道2,并读取
if adc.open(2) then
    -- 这里使用的是adc.read会返回2个值, 推荐走adc.get函数,直接取实际值
    log.info("adc", adc.read(2))
end
adc.close(2)
 */
static int l_adc_read(lua_State *L) {
    int val = 0xFF;
    int val2 = 0xFF;
    if (luat_adc_read(luaL_checkinteger(L, 1), &val, &val2) == 0) {
        lua_pushinteger(L, val);
        lua_pushinteger(L, val2);
        return 2;
    }
    else {
        lua_pushinteger(L, 0xFF);
        return 1;
    }
}

/**
获取adc计算值
@api adc.get(id)
@int 通道id,与具体设备有关,通常从0开始
@return int 单位通常是mV, 部分通道会返回温度值,单位千分之一摄氏度. 若读取失败,会返回-1
@usage
-- 本API 在 2022.10.01后编译的固件可用
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.get(2))
end
adc.close(2) -- 按需关闭
 */
static int l_adc_get(lua_State *L) {
    int val = 0xFF;
    int val2 = 0xFF;
    if (luat_adc_read(luaL_checkinteger(L, 1), &val, &val2) == 0) {
        lua_pushinteger(L, val2);
    }
    else {
        lua_pushinteger(L, -1);
    }
    return 1;
}

/**
关闭adc通道
@api adc.close(id)
@int 通道id,与具体设备有关,通常从0开始
@usage
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.read(2))
end
adc.close(2)
 */
static int l_adc_close(lua_State *L) {
    luat_adc_close(luaL_checkinteger(L, 1));
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_adc[] =
{
    { "open" ,           ROREG_FUNC(l_adc_open)},
	{ "setRange" ,       ROREG_FUNC(l_adc_set_range)},
    { "read" ,           ROREG_FUNC(l_adc_read)},
    { "get" ,            ROREG_FUNC(l_adc_get)},
    { "close" ,          ROREG_FUNC(l_adc_close)},
	//@const ADC_RANGE_3_6 number air105的ADC分压电阻开启，范围0~3.76V
	{ "ADC_RANGE_3_6",   ROREG_INT(1)},
	//@const ADC_RANGE_1_8 number air105的ADC分压电阻关闭，范围0~1.88V
	{ "ADC_RANGE_1_8",   ROREG_INT(0)},
	//@const ADC_RANGE_3_8 number air780E开启ADC0,1分压电阻，范围0~3.8V，将要废弃，不建议使用
	{ "ADC_RANGE_3_8",   ROREG_INT(LUAT_ADC_AIO_RANGE_3_8)},
	//@const ADC_RANGE_1_2 number air780E关闭ADC0,1分压电阻，范围0~1.2V，将要废弃，不建议使用
	{ "ADC_RANGE_1_2",   ROREG_INT(0)},
	//@const ADC_RANGE_MAX number ADC开启内部分压后所能到达最大量程，由具体芯片决定
	{ "ADC_RANGE_MAX",   ROREG_INT(LUAT_ADC_AIO_RANGE_MAX)},
	//@const ADC_RANGE_MIN number ADC关闭内部分压后所能到达最大量程，由具体芯片决定
	{ "ADC_RANGE_MIN",   ROREG_INT(0)},
    //@const CH_CPU number CPU内部温度的通道id
    { "CH_CPU",          ROREG_INT(LUAT_ADC_CH_CPU)},
    //@const CH_VBAT number VBAT供电电压的通道id
    { "CH_VBAT",         ROREG_INT(LUAT_ADC_CH_VBAT)},

    //@const T1 number ADC1 (如存在多个adc可利用此常量使用多ADC 例如 adc.open(ADC1+2) 打开ADC1 channel 2)
    { "T1",             ROREG_INT(16)},
    //@const T2 number ADC2 (如存在多个adc可利用此常量使用多ADC 例如 adc.open(ADC2+3) 打开ADC2 channel 3)
    { "T2",             ROREG_INT(32)},
	{ NULL,              ROREG_INT(0) }
};

LUAMOD_API int luaopen_adc( lua_State *L ) {
    luat_newlib2(L, reg_adc);
    return 1;
}
