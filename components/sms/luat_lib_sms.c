/*
@module  sms
@summary 短信
@version 1.0
@date    2022.12.08
@demo    sms
@tag LUAT_USE_SMS
@usage
-- 注意, Air780E/Air600E/Air780EG/Air780EG均不支持电信卡的短信!!
-- 本库尚在开发中, 暂不可用
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_mobile.h"

void luat_str_fromhex(char* str, size_t len, char* buff) ;

#ifndef bool
#define bool uint8_t
#endif

#include "luat_sms.h"

#define LUAT_LOG_TAG "sms"
#include "luat_log.h"
static int lua_sms_ref = 0;

static int l_sms_recv_handler(lua_State* L, void* ptr) {
    LUAT_SMS_RECV_MSG_T* sms = ((LUAT_SMS_RECV_MSG_T*)ptr);
    char buff[200] = {0};

    LLOGD("dcs %d | %d | %d | %d", sms->dcs_info.alpha_bet, sms->dcs_info.dcs, sms->dcs_info.msg_class, sms->dcs_info.type);

    if (sms->dcs_info.alpha_bet == 0) {
        memcpy(buff, sms->sms_buffer, strlen(sms->sms_buffer) + 1);
    }
    else {
        luat_str_fromhex(sms->sms_buffer, strlen(sms->sms_buffer), buff);
        LLOGD("sms %s buff %s", sms->sms_buffer, buff);
    }
    // 先发系统消息
    lua_getglobal(L, "sys_pub");
    if (lua_isnil(L, -1)) {
        luat_heap_free(sms);
        return 0;
    }
    lua_pushliteral(L, "SMS_INC");
    lua_pushstring(L, sms->phone_address);
    lua_pushstring(L, buff);
    lua_call(L, 3, 0);

    // 如果有回调函数, 就调用
    if (lua_sms_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, lua_sms_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushstring(L, sms->phone_address);
            lua_pushstring(L, buff);
            lua_call(L, 2, 0);
        }
    }
    luat_heap_free(sms);
    return 0;
}

void luat_sms_recv_cb(uint32_t event, void *param)
{
    LUAT_SMS_RECV_MSG_T* sms = ((LUAT_SMS_RECV_MSG_T*)param);
    rtos_msg_t msg = {0};
    if (event != 0) {
        return;
    }
    LUAT_SMS_RECV_MSG_T* tmp = luat_heap_malloc(sizeof(LUAT_SMS_RECV_MSG_T));
    if (tmp == NULL) {
        LLOGE("out of memory when malloc sms content");
        return;
    }
    memcpy(tmp, sms, sizeof(LUAT_SMS_RECV_MSG_T));
    msg.handler = l_sms_recv_handler;
    msg.ptr = tmp;
    luat_msgbus_put(&msg, 0);
}

/*
发送短信
@api sms.send(phone, msg)
@string 电话号码,必填
@string 短信内容,必填
@return bool 成功返回true,否则返回false
@usgae
log.info("sms", sms.send("13416121234", "Hi, LuatOS - " .. os.date()))
*/
static int l_sms_send(lua_State *L) {
    size_t payload_len = 0;
    const char* dst = luaL_checkstring(L, 1);
    const char* payload = luaL_checklstring(L, 2, &payload_len);
    // 暂时只支持非PDU短信
    int ret = luat_sms_send_msg(payload, dst, 0, 0);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/**
设置新SMS的回调函数
@api sms.setNewSmsCb(func)
@function 回调函数, 3个参数, num, txt, datetime
@return nil 传入是函数就能成功,无返回值
@usage

sms.setNewSmsCb(function(num, txt, datetime)
    -- num 手机号码
    -- txt 文本内容
    -- datetime 发送时间,当前为nil,暂不支持
    log.info("sms", num, txt, datetime)
end)
 */
static int l_sms_cb(lua_State *L) {
    if (lua_sms_ref) {
        luaL_unref(L, LUA_REGISTRYINDEX, lua_sms_ref);
        lua_sms_ref = 0;
    }
    if (lua_isfunction(L, 1)) {
        lua_sms_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_sms[] =
{
    { "send",      ROREG_FUNC(l_sms_send)},
    { "setNewSmsCb", ROREG_FUNC(l_sms_cb)},
	{ NULL,          ROREG_INT(0)}
};


LUAMOD_API int luaopen_sms( lua_State *L ) {
    luat_newlib2(L, reg_sms);
    return 1;
}
