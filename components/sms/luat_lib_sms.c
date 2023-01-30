/*
@module  sms
@summary 短信
@version 1.0
@date    2022.12.08
@demo    sms
@tag LUAT_USE_SMS
@usage
-- 注意, Air780E/Air600E/Air780EG/Air780EG均不支持电信卡的短信!!
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_mobile.h"
#include "luat_timer.h"

void luat_str_fromhex(char* str, size_t len, char* buff) ;

#ifndef bool
#define bool uint8_t
#endif

#include "luat_sms.h"

#define LUAT_LOG_TAG "sms"
#include "luat_log.h"
static int lua_sms_ref = 0;
static int lua_sms_recv_long = 1;

typedef struct long_sms
{
    uint8_t refNum;
    uint8_t maxNum;
    uint8_t seqNum;
    char buff[1];
}long_sms_t;

#define LONG_SMS_CMAX (128)
static long_sms_t* lngbuffs[LONG_SMS_CMAX];
// static char* longsms = NULL;
// static int longsms_refNum = -1;


static void ucs2char(char* source, size_t size, char* dst2, size_t* outlen) {
    char buff[size + 2];
    memset(buff, 0, size + 2);
    luat_str_fromhex(source, size, buff);
    //LLOGD("sms %s", source);
    uint16_t* tmp = (uint16_t*)buff;
    char* dst = dst2;
    // size_t tmplen = origin_len / 2;
    // size_t dstoff = 0;
    uint16_t unicode = 0;
    size_t dstlen = 0;
    while (1) {
        unicode = *tmp ++;
        unicode = ((unicode >> 8) & 0xFF) + ((unicode & 0xFF) << 8);
        //LLOGD("unicode %04X", unicode);
        if (unicode == 0)
            break; // 终止了
        if (unicode <= 0x0000007F) {
            dst[dstlen++] = (unicode & 0x7F);
            continue;
        }
        if (unicode <= 0x000007FF) {
            dst[dstlen++]	= ((unicode >> 6) & 0x1F) | 0xC0;
		    dst[dstlen++] 	= (unicode & 0x3F) | 0x80;
            continue;
        }
        if (unicode <= 0x0000FFFF) {
            dst[dstlen++]	= ((unicode >> 12) & 0x0F) | 0xE0;
		    dst[dstlen++]	= ((unicode >>  6) & 0x3F) | 0x80;
		    dst[dstlen++]	= (unicode & 0x3F) | 0x80;
            //LLOGD("why? %02X %02X %02X", ((unicode >> 12) & 0x0F) | 0xE0, ((unicode >>  6) & 0x3F) | 0x80, (unicode & 0x3F) | 0x80);
            continue;
        }
        break;
    }
    *outlen = dstlen;
    //LLOGD("ucs2char %d", dstlen);
}

static void push_sms_args(lua_State* L, LUAT_SMS_RECV_MSG_T* sms, char* dst, size_t dstlen) {
    char phone[strlen(sms->phone_address) * 3 + 1];
    memset(phone, 0, strlen(sms->phone_address) * 3 + 1);
    size_t outlen = 0;
    memcpy(phone, sms->phone_address, strlen(sms->phone_address));
    if (strlen(phone) > 4 && phone[0] == '0' && phone[1] == '0' && strlen(phone) % 2 == 0) {
        // 看来是ucs编码了
        ucs2char(sms->phone_address, strlen(sms->phone_address), phone, &outlen);
        phone[outlen] = 0x00;
    }
    lua_pushstring(L, phone);


    if (dst == NULL) {
        luaL_Buffer buff;
        luaL_buffinit(L, &buff);
        for (size_t j = 0; j < sms->maxNum; j++)
        {
            for (size_t i = 0; i < LONG_SMS_CMAX; i++)
            {
                if (lngbuffs[i] && lngbuffs[i]->refNum == dstlen && lngbuffs[i]->seqNum == j + 1) {
                    luaL_addstring(&buff, lngbuffs[i]->buff);
                }
            }
        }
        luaL_pushresult(&buff);
    }
    else {
        lua_pushlstring(L, dst, dstlen);
    }
    // 添加元数据
    lua_newtable(L);

    // 长短信总数
    lua_pushinteger(L, sms->refNum);
    lua_setfield(L, -2, "refNum");
    // 当前序号
    lua_pushinteger(L, sms->seqNum);
    lua_setfield(L, -2, "seqNum");
    // 当前序号
    lua_pushinteger(L, sms->maxNum);
    lua_setfield(L, -2, "maxNum");

    // 时间信息
    lua_pushinteger(L, sms->time.year);
    lua_setfield(L, -2, "year");
    lua_pushinteger(L, sms->time.month);
    lua_setfield(L, -2, "mon");
    lua_pushinteger(L, sms->time.day);
    lua_setfield(L, -2, "day");
    lua_pushinteger(L, sms->time.hour);
    lua_setfield(L, -2, "hour");
    lua_pushinteger(L, sms->time.minute);
    lua_setfield(L, -2, "min");
    lua_pushinteger(L, sms->time.second);
    lua_setfield(L, -2, "sec");
    lua_pushinteger(L, sms->time.tz_sign == '+' ? sms->time.tz : - sms->time.tz);
    lua_setfield(L, -2, "tz");

}


static int l_sms_recv_handler(lua_State* L, void* ptr) {
    LUAT_SMS_RECV_MSG_T* sms = ((LUAT_SMS_RECV_MSG_T*)ptr);
    // char buff[280+2] = {0};
    size_t dstlen = strlen(sms->sms_buffer);
    char tmpbuff[140*3+2] = {0};
    char *dst = tmpbuff;

    LLOGD("dcs %d | %d | %d | %d", sms->dcs_info.alpha_bet, sms->dcs_info.dcs, sms->dcs_info.msg_class, sms->dcs_info.type);

    if (sms->dcs_info.alpha_bet == 0) {
        memcpy(dst, sms->sms_buffer, strlen(sms->sms_buffer));
    }
    else {
        ucs2char(sms->sms_buffer, strlen(sms->sms_buffer), dst, &dstlen);
        dst[dstlen] = 0;
    }

    if (sms->maxNum > 0 && lua_sms_recv_long) {
        int index = -1;
        for (size_t i = 0; i < LONG_SMS_CMAX; i++)
        {
            if (lngbuffs[i] == NULL) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            LLOGE("too many long-sms!!");
            goto exit;
        }
        lngbuffs[index] = luat_heap_malloc(sizeof(long_sms_t) + dstlen);
        if (lngbuffs[index] == NULL) {
            LLOGE("out of memory when malloc long sms buff");
            goto exit;
        }
        lngbuffs[index]->maxNum = sms->maxNum;
        lngbuffs[index]->seqNum = sms->seqNum;
        lngbuffs[index]->refNum = sms->refNum;
        memcpy(lngbuffs[index]->buff, dst, dstlen);
        lngbuffs[index]->buff[dstlen] = 0x00;
        size_t counter = (sms->maxNum + 1) *  sms->maxNum / 2;
        for (size_t i = 0; i < LONG_SMS_CMAX; i++)
        {
            if (lngbuffs[i] == NULL || lngbuffs[i]->refNum != sms->refNum) {
                continue;
            }
            counter -= lngbuffs[i]->seqNum;
        }
        if (counter != 0) {
            LLOGI("long-sms, wait more frags %d/%d", sms->seqNum, sms->maxNum);
            goto exit;
        }
        LLOGI("long-sms is ok");
        dst = NULL;
        dstlen = sms->refNum;
    }

    // 先发系统消息
    lua_getglobal(L, "sys_pub");
    if (lua_isnil(L, -1)) {
        luat_heap_free(sms);
        return 0;
    }
/*
@sys_pub sms
收到短信
SMS_INC
@string 手机号
@string 短信内容，UTF8编码
@usage
--使用的例子，可多行
-- 接收短信, 支持多种方式, 选一种就可以了
-- 1. 设置回调函数
--sms.setNewSmsCb( function(phone,sms)
    log.info("sms",phone,sms)
end)
-- 2. 订阅系统消息
--sys.subscribe("SMS_INC", function(phone,sms)
    log.info("sms",phone,sms)
end)
*/
    lua_pushliteral(L, "SMS_INC");
    push_sms_args(L, sms, dst, dstlen);
    lua_call(L, 4, 0);

    // 如果有回调函数, 就调用
    if (lua_sms_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, lua_sms_ref);
        if (lua_isfunction(L, -1)) {
            push_sms_args(L, sms, dst, dstlen);
            lua_call(L, 3, 0);
        }
    }
    // 清理长短信的缓冲,如果有的话
    for (size_t i = 0; i < 16; i++)
    {
        if (lngbuffs[i] && lngbuffs[i]->refNum == sms->refNum) {
            luat_heap_free(lngbuffs[i]);
            lngbuffs[i] = NULL;
        }
    }

exit:
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
@return bool 成功返回true,否则返回false或nil
@usgae
-- 短信号码支持2种形式
-- +XXYYYYYYY 其中XX代表国家代码, 中国是86, 推荐使用这种
-- YYYYYYYYY  直接填目标号码, 例如10010, 10086, 或者国内的手机号码
log.info("sms", sms.send("+8613416121234", "Hi, LuatOS - " .. os.date()))
*/
static int l_sms_send(lua_State *L) {
    size_t phone_len = 0;
    size_t payload_len = 0;
    const char* phone = luaL_checklstring(L, 1, &phone_len);
    const char* payload = luaL_checklstring(L, 2, &payload_len);
    int ret = 0;
    char phone_buff[32] = {0};

    if (payload_len == 0) {
        LLOGI("sms is emtry");
        return 0;
    }
    if (payload_len > 140) {
        LLOGI("sms is too long %d", payload_len);
        return 0;
    }
    int pdu_mode = 0;
    for (size_t i = 0; i < payload_len; i++)
    {
        if (payload[i] & 0x80) {
            LLOGD("found non-ASCII char, using PDU mode");
            pdu_mode = 1;
            break;
        }
    }

    
    if (phone_len < 3 || phone_len > 29) {
        LLOGI("phone is too short or too long!! %d", phone_len);
        return 0;
    }
    // +8613416121234
    if (pdu_mode) { // PDU模式下, 必须带上国家代码
        if (phone[0] == '+') {
            memcpy(phone_buff, phone + 1, phone_len - 1);
        }
        // 13416121234
        else if (phone[0] != '8' && phone[1] != '6') {
            phone_buff[0] = '8';
            phone_buff[1] = '6';
            memcpy(phone_buff + 2, phone, phone_len);
        }
        else {
            memcpy(phone_buff, phone, phone_len);
        }
    }
    else {
        if (phone[0] == '+') {
            memcpy(phone_buff, phone + 3, phone_len - 3);
        }
        else if (phone[0] == '8' && phone[1] == '6') {
            memcpy(phone_buff, phone+2, phone_len - 2);
        }
        else {
            memcpy(phone_buff, phone, phone_len);
        }
    }
    
    
    phone_len = strlen(phone_buff);
    phone = phone_buff;
    LLOGD("phone %s", phone);
    if (pdu_mode) {
        char pdu[280 + 100] = {0};
        // 首先, 填充PDU头部
        strcat(pdu, "00"); // 使用内置短信中心,暂时不可设置
        strcat(pdu, "01"); // 仅收件信息, 不传保留时间
        strcat(pdu, "00"); // TP-MR, 固定填0
        sprintf_(pdu + strlen(pdu), "%02X", phone_len); // 电话号码长度
        strcat(pdu, "91"); // 目标地址格式
        // 手机方号码
        for (size_t i = 0; i < phone_len; i+=2)
        {
            if (i == (phone_len - 1) && phone_len % 2 != 0) {
                pdu[strlen(pdu)] = 'F';
                pdu[strlen(pdu)] = phone[i];
            }
            else {
                pdu[strlen(pdu)] = phone[i+1];
                pdu[strlen(pdu)] = phone[i];
            }
        }
        strcat(pdu, "00"); // 协议标识(TP-PID) 是普通GSM类型，点到点方式
        strcat(pdu, "08"); // 编码格式, UCS编码
        size_t pdu_len_offset = strlen(pdu);
        strcat(pdu, "00"); // 这是预留的, 填充数据会后更新成正确的值
        uint16_t unicode = 0;
        size_t pdu_userdata_len = 0;
        for (size_t i = 0; i < payload_len; i++)
        {
            // 首先是不是单字节
            if (payload[i] & 0x80) {
                // 非ASCII编码
                if (payload[i] && 0xE0) { // 1110xxxx 10xxxxxx 10xxxxxx
                    unicode = ((payload[i] & 0x0F) << 12) + ((payload[i+1] & 0x3F) << 6) + (payload[i+2] & 0x3F);
                    //LLOGD("unicode %04X %02X%02X%02X", unicode, payload[i], payload[i+1], payload[i+2]);
                    sprintf_(pdu + strlen(pdu), "%02X%02X", (unicode >> 8) & 0xFF, unicode & 0xFF);
                    i+=2;
                    pdu_userdata_len += 2;
                    continue;
                }
                if (payload[i] & 0xC0) { // 110xxxxx 10xxxxxx
                    unicode = ((payload[i] & 0x1F) << 6) + (payload[i+1] & 0x3F);
                    //LLOGD("unicode %04X %02X%02X", unicode, payload[i], payload[i+1]);
                    sprintf_(pdu + strlen(pdu), "%02X%02X", (unicode >> 8) & 0xFF, unicode & 0xFF);
                    i++;
                    pdu_userdata_len += 2;
                    continue;
                }
                LLOGD("bad UTF8 string");
                break;
            }
            // 单个ASCII字符, 但需要扩展到2位
            else {
                // ASCII编码
                strcat(pdu, "00");
                sprintf_(pdu + strlen(pdu), "%02X", payload[i]);
                pdu_userdata_len += 2;
                continue;
            }
        }
        // 修正pdu长度
        char tmp[3] = {0};
        sprintf_(tmp, "%02X", pdu_userdata_len);
        memcpy(pdu + pdu_len_offset, tmp, 2);

        // 打印PDU数据, 调试用
        LLOGD("PDU %s", pdu);
        payload = pdu;
        payload_len = strlen(pdu);
        phone = "";
        ret = luat_sms_send_msg(pdu, "", 1, 54);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
    }
    else {
        ret = luat_sms_send_msg(payload, phone, 0, 0);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
    }
    LLOGD("sms ret %d", ret);
    return 1;
}

/**
设置新SMS的回调函数
@api sms.setNewSmsCb(func)
@function 回调函数, 3个参数, num, txt, metas
@return nil 传入是函数就能成功,无返回值
@usage

sms.setNewSmsCb(function(num, txt, metas)
    -- num 手机号码
    -- txt 文本内容
    -- metas 短信的元数据,例如发送的时间,长短信编号
    -- 注意, 长短信会自动合并成一条txt
    log.info("sms", num, txt, metas and json.encode(metas) or "")
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

/**
设置长短信的自动合并功能
@api sms.autoLong(mode)
@bool 是否自动合并,true为自动合并,为默认值
@return bool 设置后的值
@usage
-- 禁用长短信的自动合并, 一般不需要禁用
sms.autoLong(false)
 */
static int l_sms_auto_long(lua_State *L) {
    if (lua_isboolean(L, 1)) {
        lua_sms_recv_long = lua_toboolean(L, 1);
    }
    else if (lua_isinteger(L, 1))
    {
        lua_sms_recv_long = lua_toboolean(L, 1);
    }
    lua_pushboolean(L, lua_sms_recv_long == 0 ? 0 : 1);
    return 1;
}

/**
清除长短信缓存
@api sms.clearLong()
@return int 清理掉的片段数量
@usage
sms.clearLong()
 */
static int l_sms_clear_long(lua_State *L) {
    int counter = 0;
    for (size_t i = 0; i < LONG_SMS_CMAX; i++)
    {
        if (lngbuffs[i]) {
            counter ++;
            luat_heap_free(lngbuffs[i]);
            lngbuffs[i] = NULL;
        }
    }
    lua_pushinteger(L, counter);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_sms[] =
{
    { "send",           ROREG_FUNC(l_sms_send)},
    { "setNewSmsCb",    ROREG_FUNC(l_sms_cb)},
    { "autoLong",       ROREG_FUNC(l_sms_auto_long)},
    { "clearLong",      ROREG_FUNC(l_sms_clear_long)},
	{ NULL,             ROREG_INT(0)}
};


LUAMOD_API int luaopen_sms( lua_State *L ) {
    luat_newlib2(L, reg_sms);
    return 1;
}
