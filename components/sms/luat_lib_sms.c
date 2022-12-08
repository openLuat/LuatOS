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
#include "luat_sms.h"

#define LUAT_LOG_TAG "sms"
#include "luat_log.h"

/**
 * @brief SMS接收回调
 * 
 * @param event 事件类型
 * @param param 参数
 */
void luat_sms_recv_cb(uint32_t event, void *param)
{
    // 等待CSDK完成回调数据的改造后再实现
    // luat_sms_inc_t* inc = (luat_sms_inc_t*)param;
    // char buff[256] = {0};
	// LLOGD("sms event %d", event);
    // memcpy(buff, inc->SMSC, 255);
	// LLOGD("sms SMSC %s", buff);
    // memcpy(buff, inc->TPDU, 255);
	// LLOGD("sms TPDU %s", buff);
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

#include "rotable2.h"
static const rotable_Reg_t reg_sms[] =
{
    { "send",      ROREG_FUNC(l_sms_send)},
	{ NULL,          ROREG_INT(0)}
};


LUAMOD_API int luaopen_sms( lua_State *L ) {
    luat_newlib2(L, reg_sms);
    return 1;
}
