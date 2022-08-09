
/*
@module  mobile
@summary 蜂窝网络
@version 1.0
@date    2022.8.9
*/
#include "luat_base.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "mobile"
#include "luat_log.h"

/**
获取或设置IMEI
@api mobile.imei(index, newvalue)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@string 新的IMEI. 不填就是获取IMEI, 填了就是设置IMEI, 是否支持设置取决于底层实现.
@return string 当前的IMEI值
 */
static int l_mobile_imei(lua_State* L) {
    return 0;
}

/**
获取或设置IMSI
@api mobile.imsi(index, newvalue)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@string 新的IMSI. 不填就是获取IMSI, 填了就是设置IMSI, 是否支持设置取决于底层实现.
@return string 当前的IMSI值
 */
static int l_mobile_imsi(lua_State* L) {
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mobile[] = {
    {"imei", ROREG_FUNC(l_mobile_imei)},
    {"imsi", ROREG_FUNC(l_mobile_imsi)},
    {NULL, ROREG_INT(0)}
};
