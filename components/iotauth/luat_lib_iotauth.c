// IoT鉴权函数, 用于生成各种云平台的参数

#include "luat_base.h"
#include "luat_crypto.h"

static int l_iotauth_aliyun(lua_State *L) {
    return 0;
}

static int l_iotauth_onenet(lua_State *L) {
    return 0;
}

static int l_iotauth_iotda(lua_State *L) {
    return 0;
}

static int l_iotauth_qcloud(lua_State *L) {
    return 0;
}

static int l_iotauth_tuya(lua_State *L) {
    return 0;
}

static int l_iotauth_baidu(lua_State *L) {
    return 0;
}

static int l_iotauth_aws(lua_State *L) {
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_iotauth[] =
{
    { "aliyun" ,          ROREG_FUNC(l_iotauth_aliyun)},
    { "onenet" ,          ROREG_FUNC(l_iotauth_onenet)},
    { "iotda" ,           ROREG_FUNC(l_iotauth_iotda)},
    { "qcloud" ,          ROREG_FUNC(l_iotauth_qcloud)},
    { "tuya" ,            ROREG_FUNC(l_iotauth_tuya)},
    { "baidu" ,           ROREG_FUNC(l_iotauth_baidu)},
    { "aws" ,             ROREG_FUNC(l_iotauth_aws)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_iotauth( lua_State *L ) {
    luat_newlib2(L, reg_iotauth);
    return 1;
}
