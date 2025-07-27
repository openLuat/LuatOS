/*
@module  sms
@summary 短信
@version 1.0
@date    2022.12.08
@demo    sms
@tag LUAT_USE_SMS
@usage
-- 注意, Air780E/Air600E/Air780EG/Air780EG均不支持电信卡的短信!!
-- 意思是, 当上述模块搭配电信SIM卡, 无法从模块发出短信, 也无法在模块接收短信
-- 如果是联通卡或者移动卡, 均可收取短信, 但实名制的卡才能发送短信
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_mobile.h"
#include "luat_timer.h"
#include "luat_rtos.h"

void luat_str_fromhex(char* str, size_t len, char* buff) ;

#include "luat_sms.h"

#ifndef bool
#define bool    uint8_t
#endif

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

typedef struct long_sms_send
{
    size_t payload_len;
    uint8_t *payload;
}long_sms_send_t;



#define LONG_SMS_CMAX (128)

static long_sms_t* lngbuffs[LONG_SMS_CMAX];
static luat_sms_pdu_packet_t g_s_sms_pdu_packet = {0};
static long_sms_send_t g_s_sms_send = {0};
static uint8_t ref_idx = 254;
static uint64_t long_sms_send_idp = 0;



static int32_t l_long_sms_send_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (msg->arg1)
    {
        lua_pushboolean(L, 0);
    }
    else
    {
        lua_pushboolean(L, 1);
    }
    luat_cbcwait(L, long_sms_send_idp, 1);
    long_sms_send_idp = 0;
    g_s_sms_pdu_packet.maxNum = 0;             // 通过sms.sendLong发送的短信，需要在回调里确定发送结束
    return 0;
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

void luat_sms_send_cb(int ret)
{
    // 当前没有短信在发送，应该不会产生这个回调吧?
    if (!g_s_sms_pdu_packet.maxNum) {
        return;
    }
    rtos_msg_t msg = {
        .handler = l_long_sms_send_callback,
        .arg1 = 0,
        .arg2 = 0
    };
    // 发送失败
    if (ret) {
        // 长短信发送失败
        if (long_sms_send_idp) {
            msg.arg1 = 1;
            luat_msgbus_put(&msg, 0);
        } else {
            // 通过sms.send发送的短信，这里可以直接判断发送结束
            g_s_sms_pdu_packet.maxNum = 0;
        }
        if (g_s_sms_send.payload != NULL) {
            luat_heap_free(g_s_sms_send.payload);
            g_s_sms_send.payload = NULL;
        }
        return;
    }
    LLOGE("long sms callback seqNum = %d", g_s_sms_pdu_packet.seqNum);
    // 全部短信发送完成
    if (g_s_sms_pdu_packet.seqNum == g_s_sms_pdu_packet.maxNum) {
        if (long_sms_send_idp) {
            msg.arg1 = 0;
            luat_msgbus_put(&msg, 0);
        } else {
            g_s_sms_pdu_packet.maxNum = 0;
        }

        if (g_s_sms_send.payload != NULL) {
            luat_heap_free(g_s_sms_send.payload);
            g_s_sms_send.payload = NULL;
        }
        return;
    }

    // 长短信继续发送
    g_s_sms_pdu_packet.seqNum++;
    // 最后一包
    if (g_s_sms_send.payload_len - (g_s_sms_pdu_packet.seqNum - 1) * LUAT_SMS_LONG_MSG_PDU_SIZE <= LUAT_SMS_LONG_MSG_PDU_SIZE) {
        memcpy(g_s_sms_pdu_packet.payload_buf, g_s_sms_send.payload + (g_s_sms_pdu_packet.seqNum - 1) * LUAT_SMS_LONG_MSG_PDU_SIZE, g_s_sms_send.payload_len - (g_s_sms_pdu_packet.seqNum - 1) * LUAT_SMS_LONG_MSG_PDU_SIZE);
        g_s_sms_pdu_packet.payload_len = g_s_sms_send.payload_len - (g_s_sms_pdu_packet.seqNum - 1) * LUAT_SMS_LONG_MSG_PDU_SIZE ;
    } else {
        // 继续发送
        memcpy(g_s_sms_pdu_packet.payload_buf, g_s_sms_send.payload + (g_s_sms_pdu_packet.seqNum - 1) * LUAT_SMS_LONG_MSG_PDU_SIZE, LUAT_SMS_LONG_MSG_PDU_SIZE);
        g_s_sms_pdu_packet.payload_len = LUAT_SMS_LONG_MSG_PDU_SIZE;
    }
    
    int len = luat_sms_pdu_packet(&g_s_sms_pdu_packet);
    ret = luat_sms_send_msg_v2(g_s_sms_pdu_packet.pdu_buf, len);
    // 发送失败了
    if (ret) {
        // 长短信接口
        if(long_sms_send_idp) {
            msg.arg1 = 0;
            luat_msgbus_put(&msg, 0);
        } else {
            g_s_sms_pdu_packet.maxNum = 0;
        }
        if (g_s_sms_send.payload != NULL) {
            luat_heap_free(g_s_sms_send.payload);
            g_s_sms_send.payload = NULL;
        }
    }
    return;
}

/*
异步发送短信
@api sms.send(phone, msg, auto_phone_fix)
@string 电话号码,必填
@string 短信内容,必填
@bool   是否自动处理电话号号码的格式,默认是按短信内容和号码格式进行自动判断, 设置为false可禁用
@return bool 成功返回true,否则返回false或nil
@usgae
-- 短信号码支持2种形式
-- +XXYYYYYYY 其中XX代表国家代码, 中国是86, 推荐使用这种
-- YYYYYYYYY  直接填目标号码, 例如10010, 10086, 或者国内的手机号码
log.info("sms", sms.send("+8613416121234", "Hi, LuatOS - " .. os.date()))

-- 直接使用目标号码, 不做任何自动化处理. 2023.09.21新增
log.info("sms", sms.send("85513416121234", "Hi, LuatOS - " .. os.date()), false)
*/
static int l_sms_send(lua_State *L) {
    size_t phone_len = 0;
    size_t payload_len = 0;
    const char* phone = luaL_checklstring(L, 1, &phone_len);
    const char* payload = luaL_checklstring(L, 2, &payload_len);
    int auto_phone = 1;
    if (lua_isboolean(L, 3) && !lua_toboolean(L, 3)) {
        auto_phone = 0;
    }
    
    int ret = 0;

    // 当前有其他地方在发送短信
    if (g_s_sms_pdu_packet.maxNum) {
        LLOGE("sms is busy");
        return 0;
    }

    if (payload_len == 0) {
        LLOGE("sms is empty");
        return 0;
    }
    
    if (phone_len < 3 || phone_len > 29) {
        LLOGE("phone is too short or too long!! %d", phone_len);
        return 0;
    }

    size_t outlen = 0;
    uint8_t *ucs2_buf = NULL;
    ucs2_buf = (uint8_t *)luat_heap_malloc(payload_len * 3);
    if (ucs2_buf == NULL)
    {
        LLOGE("out of memory");
        return 0;
    }
    memset(ucs2_buf, 0x00, payload_len * 3);

    ret = utf82ucs2(payload, payload_len, ucs2_buf, payload_len * 3, &outlen);

    if (ret) {
        LLOGE("utf82ucs2 encode fail");
        goto SMS_FAIL;
    }

    memset(&g_s_sms_send, 0x00, sizeof(long_sms_send_t));
    memset(&g_s_sms_pdu_packet, 0x00, sizeof(luat_sms_pdu_packet_t));

    // 短短信
    if (outlen <= LUAT_SMS_SHORT_MSG_PDU_SIZE) {
        g_s_sms_pdu_packet.maxNum = 1;
        memcpy(g_s_sms_pdu_packet.payload_buf, ucs2_buf , outlen);
        g_s_sms_pdu_packet.payload_len = outlen;
    } else {
        // 长短信
        ref_idx = (ref_idx + 1) % 255;
        g_s_sms_pdu_packet.maxNum = (outlen + LUAT_SMS_LONG_MSG_PDU_SIZE - 1) / LUAT_SMS_LONG_MSG_PDU_SIZE;
        g_s_sms_pdu_packet.refNum = ref_idx;
        memcpy(g_s_sms_pdu_packet.payload_buf, ucs2_buf , LUAT_SMS_LONG_MSG_PDU_SIZE);
        g_s_sms_pdu_packet.payload_len = LUAT_SMS_LONG_MSG_PDU_SIZE;
    }

    g_s_sms_pdu_packet.auto_phone = auto_phone;
    g_s_sms_pdu_packet.phone_len = phone_len;
    g_s_sms_pdu_packet.phone = phone;
    g_s_sms_pdu_packet.seqNum = 1;

    g_s_sms_send.payload = ucs2_buf;
    g_s_sms_send.payload_len = outlen;

    int len = luat_sms_pdu_packet(&g_s_sms_pdu_packet);
    LLOGW("pdu len %d", len);
    ret = luat_sms_send_msg_v2(g_s_sms_pdu_packet.pdu_buf, len);
    if (!ret) {
        lua_pushboolean(L, ret == 0);
        return 1;
    }
SMS_FAIL:
    g_s_sms_pdu_packet.maxNum = 0;
    g_s_sms_send.payload = NULL;
    if(ucs2_buf != NULL) {
        luat_heap_free(ucs2_buf);
    }
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
同步发送短信
@api sms.sendLong(phone, msg, auto_phone_fix).wait()
@string 电话号码,必填
@string 短信内容,必填
@bool   是否自动处理电话号号码的格式,默认是按短信内容和号码格式进行自动判断, 设置为false可禁用
@return bool 异步等待结果 成功返回true, 否则返回false或nil
@usgae
sys.taskInit(function()
    local str = string.rep("1234567890", 50)
    sys.waitUntil("IP_READY")
    -- 发送500bytes的短信
    sms.sendLong("+8613416121234", str).wait()
end)
*/
static int l_long_sms_send(lua_State *L) {
    size_t phone_len = 0;
    size_t payload_len = 0;
    uint8_t *ucs2_buf = NULL;
    const char* phone = luaL_checklstring(L, 1, &phone_len);
    const char* payload = luaL_checklstring(L, 2, &payload_len);
    int auto_phone = 1;
    if (lua_isboolean(L, 3) && !lua_toboolean(L, 3)) {
        auto_phone = 0;
    }
    // 当前有其他地方在发送短信
    if (g_s_sms_pdu_packet.maxNum) {
        LLOGE("sms is busy");
        lua_pushboolean(L, 0);
        luat_pushcwait_error(L,1);
        return 1;
    }

    // 当前有其他地方在用sms.sendLong发送短信
    if (long_sms_send_idp) {
        lua_pushboolean(L, 0);
        luat_pushcwait_error(L,1);
        return 1;
    }

    if (payload_len == 0) {
        LLOGE("sms is empty");
        goto SMS_FAIL;
    }

    if (phone_len < 3 || phone_len > 29) {
        LLOGE("phone is too short or too long!! %d", phone_len);
        goto SMS_FAIL;
    }

    size_t outlen = 0;
    ucs2_buf = (uint8_t *)luat_heap_malloc(payload_len * 3);
    if (ucs2_buf == NULL)
    {
        LLOGE("out of memory");
        goto SMS_FAIL;
    }

    memset(ucs2_buf, 0x00, payload_len * 3);

    int ret = utf82ucs2(payload, payload_len, ucs2_buf, payload_len * 3, &outlen);

    if (ret) {
        LLOGE("utf8 to ucs2 fail ret");
        goto SMS_FAIL;
    }

    memset(&g_s_sms_send, 0x00, sizeof(long_sms_send_t));
    memset(&g_s_sms_pdu_packet, 0x00, sizeof(luat_sms_pdu_packet_t));


    // 短短信
    if (outlen <= LUAT_SMS_SHORT_MSG_PDU_SIZE) {
        g_s_sms_pdu_packet.maxNum = 1;
        memcpy(g_s_sms_pdu_packet.payload_buf, ucs2_buf , outlen);
        g_s_sms_pdu_packet.payload_len = outlen;
    } else {
        // 长短信
        ref_idx = (ref_idx + 1) % 255;
        g_s_sms_pdu_packet.maxNum = (outlen + LUAT_SMS_LONG_MSG_PDU_SIZE - 1) / LUAT_SMS_LONG_MSG_PDU_SIZE;
        g_s_sms_pdu_packet.refNum = ref_idx;
        memcpy(g_s_sms_pdu_packet.payload_buf, ucs2_buf , LUAT_SMS_LONG_MSG_PDU_SIZE);
        g_s_sms_pdu_packet.payload_len = LUAT_SMS_LONG_MSG_PDU_SIZE;
    }

    long_sms_send_idp = luat_pushcwait(L);
    
    g_s_sms_pdu_packet.auto_phone = auto_phone;
    g_s_sms_pdu_packet.phone_len = phone_len;
    g_s_sms_pdu_packet.phone = phone;
    g_s_sms_pdu_packet.seqNum = 1;

    g_s_sms_send.payload = ucs2_buf;
    g_s_sms_send.payload_len = outlen;

    char buf[400] = {0};
    char tmp[3] = {0};

    int len = luat_sms_pdu_packet(&g_s_sms_pdu_packet);
    LLOGE("pdu len %d", len);
    for (int i = 0; i < len; i++)
    {
        sprintf(tmp, "%02X", g_s_sms_pdu_packet.pdu_buf[i]);
        strcat(buf, tmp);
    }
    LLOGE("pdu buf %s", buf);
    ret = luat_sms_send_msg_v2(g_s_sms_pdu_packet.pdu_buf, len);
    if (!ret) {
        return 1;
    }
    LLOGE("sms send task create failed");
SMS_FAIL:
    long_sms_send_idp = 0;
    g_s_sms_pdu_packet.maxNum = 0;
    g_s_sms_send.payload = NULL;
    if(ucs2_buf != NULL) {
        luat_heap_free(ucs2_buf);
    }
    lua_pushboolean(L, 0);
    luat_pushcwait_error(L, 1);
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
    { "sendLong",       ROREG_FUNC(l_long_sms_send)},
	{ NULL,             ROREG_INT(0)}
};


LUAMOD_API int luaopen_sms( lua_State *L ) {
    luat_newlib2(L, reg_sms);
    return 1;
}
