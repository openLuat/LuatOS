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
#include "luat_str.h"
#include "luat_sms.h"

#ifndef bool
#define bool    uint8_t
#endif

#define LUAT_LOG_TAG "sms"
#include "luat_log.h"
static int lua_sms_ref = 0;
static int lua_sms_report_ref = 0;
static int lua_sms_recv_long = 1;

typedef struct long_sms
{
    uint16_t refNum;
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
static uint8_t g_sms_msg_refs[LONG_SMS_CMAX];  // 每段的 MR (Message Reference)
static uint8_t g_sms_msg_ref_count = 0;         // 已确认的段数


static int l_long_sms_send_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);

    uint8_t is_success = msg->arg1;
    uint8_t rp_cause = msg->arg2 & 0xFF;
    uint16_t error_code = (msg->arg2 >> 8) & 0xFFFF;
    uint8_t msg_ref = (msg->arg2 >> 24) & 0xFF;

    if (long_sms_send_idp)
    {
        lua_pushboolean(L, is_success);
        luat_cbcwait(L, long_sms_send_idp, 1);
        long_sms_send_idp = 0;
    }

/*
@sys_pub sms
短信发送结果
SMS_SENT
@result boolean 发送结果，成功为true, 失败为false
@number rp_cause RP-Cause错误码(3GPP TS 24.011), 0=成功, 1=空号, 30=未知用户, 50=未开通服务(停机)
@string rp_cause_str RP-Cause描述字符串
@number msg_ref 最后一段的消息参考号, 用于匹配后续的SMS_REPORT回执消息
@number error_code SDK错误码(0=成功, 300=设备故障, 330=短信中心未知, 332=无网络服务, 333=网络超时, 500=未知错误)
@table msg_refs 所有段的消息参考号列表, 如{10,11,12}, 短信为单段时{5}; 用于匹配每段短信的SMS_REPORT回执
@usage
sys.subscribe("SMS_SENT", function(result, rp_cause, rp_cause_str, msg_ref, error_code, msg_refs)
    log.info("sms send", result, rp_cause, rp_cause_str, msg_ref, error_code)
    if msg_refs then
        for i, ref in ipairs(msg_refs) do
            log.info("sms send", "段", i, "msg_ref", ref)
        end
    end
end)
*/
    lua_getglobal(L, "sys_pub");
    lua_pushliteral(L, "SMS_SENT");
    lua_pushboolean(L, is_success);
    lua_pushinteger(L, rp_cause);
    char rp_cause_str[40] = {0};
    luat_sms_rpcause_to_string(rp_cause, rp_cause_str, sizeof(rp_cause_str));
    lua_pushstring(L, rp_cause_str);
    lua_pushinteger(L, msg_ref);
    lua_pushinteger(L, error_code);
    // 推送 msg_refs 表
    lua_newtable(L);
    for (int i = 0; i < g_sms_msg_ref_count; i++) {
        lua_pushinteger(L, g_sms_msg_refs[i]);
        lua_seti(L, -2, i + 1);
    }
    lua_call(L, 7, 0);
    g_s_sms_pdu_packet.maxNum = 0;
    return 0;
}


static void push_sms_args(lua_State* L, luat_sms_recv_msg_t* sms, char* dst, size_t dstlen) {
    char phone[sizeof(sms->phone_address) * 3 + 1] = {0};
    memset(phone, 0, strlen(sms->phone_address) * 3 + 1);
    size_t outlen = 0;
    memcpy(phone, sms->phone_address, strlen(sms->phone_address));
    if (strlen(phone) > 4 && phone[0] == '0' && phone[1] == '0' && strlen(phone) % 2 == 0) {
        // 看来是ucs编码了
        luat_str_ucs2_to_char(sms->phone_address, strlen(sms->phone_address), phone, &outlen);
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
    luat_sms_recv_msg_t* sms = ((luat_sms_recv_msg_t*)ptr);
    // char buff[280+2] = {0};
    size_t dstlen = strlen(sms->sms_buffer);
    char *dst = luat_heap_malloc(dstlen + 2);
    if (dst == NULL) {
        LLOGE("out of memory when malloc sms buff");
        luat_heap_free(sms);
        return 0;
    }
    memset(dst, 0, dstlen + 2);

    LLOGD("dcs %d | %d | %d | %d", sms->dcs_info.alpha_bet, sms->dcs_info.dcs, sms->dcs_info.msg_class, sms->dcs_info.type);

    if (sms->dcs_info.alpha_bet == 0) {
        memcpy(dst, sms->sms_buffer, strlen(sms->sms_buffer));
    }
    else {
        luat_str_ucs2_to_char(sms->sms_buffer, strlen(sms->sms_buffer), dst, &dstlen);
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
    if (dst) {
        luat_heap_free(dst);
    }
    luat_heap_free(sms);
    return 0;
}

static int l_sms_report_handler(lua_State* L, void* ptr) {
    luat_sms_recv_msg_t* sms = (luat_sms_recv_msg_t*)ptr;
    char status_str[32] = {0};
    luat_sms_status_to_string(sms->status, status_str, sizeof(status_str));

    char phone[sizeof(sms->phone_address) + 1] = {0};
    memcpy(phone, sms->phone_address, sizeof(sms->phone_address));

    lua_getglobal(L, "sys_pub");
    if (lua_isnil(L, -1)) {
        luat_heap_free(sms);
        return 0;
    }
/*
@sys_pub sms
短信回执(状态报告)
SMS_REPORT
@number msg_ref 消息参考号, 用于匹配发送的短信
@number status 状态码, 0=成功送达, 其他为失败(3GPP TS 23.040 9.2.3.15)
@string status_str 状态描述, 如 "SUCCESS"/"FAILED_TEMP_*"/"FAILED_PERM_*"
@string phone 接收方手机号
@string discharge_time 送达/失败时间, 格式 "YY-MM-DD HH:MM:SS"
@usage
sys.subscribe("SMS_REPORT", function(msg_ref, status, status_str, phone, discharge_time)
    log.info("sms report", msg_ref, status, status_str, phone, discharge_time)
end)
*/
    lua_pushliteral(L, "SMS_REPORT");
    lua_pushinteger(L, sms->msg_ref);
    lua_pushinteger(L, sms->status);
    lua_pushstring(L, status_str);
    lua_pushstring(L, phone);
    lua_pushstring(L, sms->discharge_time);
    lua_call(L, 6, 0);

    if (lua_sms_report_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, lua_sms_report_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, sms->msg_ref);
            lua_pushinteger(L, sms->status);
            lua_pushstring(L, status_str);
            lua_pushstring(L, phone);
            lua_pushstring(L, sms->discharge_time);
            lua_call(L, 5, 0);
        }
    }

    luat_heap_free(sms);
    return 0;
}

void luat_sms_recv_cb(uint32_t event, void *param)
{
    luat_sms_recv_msg_t* sms = ((luat_sms_recv_msg_t*)param);
    rtos_msg_t msg = {0};

    if (sms->msg_type == LUAT_SMS_MSG_STATUS_REPORT || event == 1 || event == 2) {
        luat_sms_recv_msg_t* tmp = luat_heap_malloc(sizeof(luat_sms_recv_msg_t));
        if (tmp == NULL) {
            LLOGE("out of memory when malloc sms report");
            return;
        }
        memcpy(tmp, sms, sizeof(luat_sms_recv_msg_t));
        msg.handler = l_sms_report_handler;
        msg.ptr = tmp;
        luat_msgbus_put(&msg, 0);
        return;
    }

    if (event != 0) {
        return;
    }
    luat_sms_recv_msg_t* tmp = luat_heap_malloc(sizeof(luat_sms_recv_msg_t));
    if (tmp == NULL) {
        LLOGE("out of memory when malloc sms content");
        return;
    }
    memcpy(tmp, sms, sizeof(luat_sms_recv_msg_t));
    msg.handler = l_sms_recv_handler;
    msg.ptr = tmp;
    luat_msgbus_put(&msg, 0);
}

static void luat_sms_send_done(uint8_t is_success, uint16_t error_code, uint8_t rp_cause, uint8_t msg_ref)
{
    uint32_t packed = ((uint32_t)msg_ref << 24) | ((uint32_t)error_code << 8) | rp_cause;
    rtos_msg_t msg = {
        .handler = l_long_sms_send_callback,
        .arg1 = is_success,
        .arg2 = packed
    };
    luat_msgbus_put(&msg, 0);
    if (g_s_sms_send.payload != NULL) {
        luat_heap_free(g_s_sms_send.payload);
        g_s_sms_send.payload = NULL;
    }
}


void luat_sms_send_cb(int ret)
{
    uint8_t rp_cause = 0, tp_cause = 0, msg_ref = 0;
    luat_sms_get_last_send_result(&rp_cause, &tp_cause, &msg_ref);

    // 当前没有短信在发送，应该不会产生这个回调吧?
    if (!g_s_sms_pdu_packet.maxNum) {
        return;
    }

    // 记录本段的 msg_ref
    if (g_s_sms_pdu_packet.seqNum > 0 && g_s_sms_pdu_packet.seqNum <= LONG_SMS_CMAX) {
        g_sms_msg_refs[g_s_sms_pdu_packet.seqNum - 1] = msg_ref;
        g_sms_msg_ref_count = g_s_sms_pdu_packet.seqNum;
    }

    // 发送失败
    if (ret) {
        luat_sms_send_done(0, (uint16_t)ret, rp_cause, msg_ref);
        return;
    }
    // 全部短信发送完成
    if (g_s_sms_pdu_packet.seqNum == g_s_sms_pdu_packet.maxNum) {
        luat_sms_send_done(1, 0, rp_cause, msg_ref);
        return;
    }

    // 长短信继续发送
    g_s_sms_pdu_packet.seqNum++;
    if (g_s_sms_pdu_packet.dcs == LUAT_SMS_CODE_7BIT) {
        /* 7-bit 续发 */
        size_t septet_offset = (size_t)(g_s_sms_pdu_packet.seqNum - 1) * LUAT_SMS_LONG_MSG_7BIT_CHARS;
        size_t remaining = g_s_sms_send.payload_len - septet_offset;
        size_t seg_chars = remaining < LUAT_SMS_LONG_MSG_7BIT_CHARS ? remaining : LUAT_SMS_LONG_MSG_7BIT_CHARS;
        int packed = luat_sms_pack_7bit(g_s_sms_send.payload + septet_offset, seg_chars, g_s_sms_pdu_packet.payload_buf, sizeof(g_s_sms_pdu_packet.payload_buf), 1);
        if (packed < 0) {
            luat_sms_send_done(0, 0, rp_cause, msg_ref);
            return;
        }
        g_s_sms_pdu_packet.payload_len = (size_t)packed;
        g_s_sms_pdu_packet.udl = 7 + seg_chars;
    } else {
        /* UCS2 续发 */
        size_t byte_offset = (size_t)(g_s_sms_pdu_packet.seqNum - 1) * LUAT_SMS_LONG_MSG_PDU_SIZE;
        size_t remaining = g_s_sms_send.payload_len - byte_offset;
        size_t seg_bytes = remaining < LUAT_SMS_LONG_MSG_PDU_SIZE ? remaining : LUAT_SMS_LONG_MSG_PDU_SIZE;
        memcpy(g_s_sms_pdu_packet.payload_buf, g_s_sms_send.payload + byte_offset, seg_bytes);
        g_s_sms_pdu_packet.payload_len = seg_bytes;
        g_s_sms_pdu_packet.udl = seg_bytes + 6;
    }
    int len = luat_sms_pdu_packet(&g_s_sms_pdu_packet);
    ret = luat_sms_send_msg_v2(g_s_sms_pdu_packet.pdu_buf, len);
    // 发送失败
    if (ret) {
        luat_sms_send_done(0, (uint16_t)ret, rp_cause, msg_ref);
    }
    return;
}

/*
 * 公共编码+打包辅助函数，供 l_sms_send 和 l_long_sms_send 共用。
 * 执行编码（7-bit 或 UCS2）并填充 g_s_sms_send 和 g_s_sms_pdu_packet。
 * 成功返回 0；失败返回 -1，此时两个全局结构体均已重置为 0。
 */
static int sms_encode_and_pack(const char *payload, size_t payload_len)
{
    uint8_t *sms_buf = NULL;
    size_t outlen = 0;
    int is_7bit = 0;

    memset(&g_s_sms_send, 0x00, sizeof(long_sms_send_t));
    memset(&g_s_sms_pdu_packet, 0x00, sizeof(luat_sms_pdu_packet_t));
    memset(g_sms_msg_refs, 0, sizeof(g_sms_msg_refs));
    g_sms_msg_ref_count = 0;

    sms_buf = (uint8_t *)luat_heap_malloc(payload_len * 3);
    if (sms_buf == NULL) {
        LLOGE("out of memory");
        return -1;
    }
    memset(sms_buf, 0x00, payload_len * 3);

    int septet_count = luat_sms_check_7bit(payload, payload_len);
    if (septet_count >= 0) {
        /* 可以用 GSM 7-bit 编码 */
        is_7bit = 1;
        int n = luat_sms_encode_7bit_septets(payload, payload_len, sms_buf, payload_len * 2 + 2);
        if (n < 0) {
            LLOGE("7bit encode fail");
            luat_heap_free(sms_buf);
            return -1;
        }
        outlen = (size_t)n;
        g_s_sms_pdu_packet.dcs = LUAT_SMS_CODE_7BIT;
    } else {
        /* 回落到 UCS2 编码 */
        int ret = luat_str_utf8_to_ucs2(payload, payload_len, sms_buf, payload_len * 3, &outlen);
        if (ret) {
            LLOGE("utf8 to ucs2 fail");
            luat_heap_free(sms_buf);
            return -1;
        }
        g_s_sms_pdu_packet.dcs = LUAT_SMS_CODE_UCS2;
    }

    if (g_s_sms_pdu_packet.dcs == LUAT_SMS_CODE_7BIT) {
        if (outlen <= LUAT_SMS_SHORT_MSG_7BIT_CHARS) {
            /* 7-bit 短短信 */
            g_s_sms_pdu_packet.maxNum = 1;
            int packed = luat_sms_pack_7bit(sms_buf, outlen, g_s_sms_pdu_packet.payload_buf, sizeof(g_s_sms_pdu_packet.payload_buf), 0);
            g_s_sms_pdu_packet.payload_len = (size_t)packed;
            g_s_sms_pdu_packet.udl = outlen;
        } else {
            /* 7-bit 长短信 */
            ref_idx = (ref_idx + 1) % 255;
            g_s_sms_pdu_packet.maxNum = (outlen + LUAT_SMS_LONG_MSG_7BIT_CHARS - 1) / LUAT_SMS_LONG_MSG_7BIT_CHARS;
            g_s_sms_pdu_packet.refNum = ref_idx;
            int packed = luat_sms_pack_7bit(sms_buf, LUAT_SMS_LONG_MSG_7BIT_CHARS, g_s_sms_pdu_packet.payload_buf, sizeof(g_s_sms_pdu_packet.payload_buf), 1);
            g_s_sms_pdu_packet.payload_len = (size_t)packed;
            g_s_sms_pdu_packet.udl = 7 + LUAT_SMS_LONG_MSG_7BIT_CHARS;
        }
    } else {
        if (outlen <= LUAT_SMS_SHORT_MSG_PDU_SIZE) {
            /* UCS2 短短信 */
            g_s_sms_pdu_packet.maxNum = 1;
            memcpy(g_s_sms_pdu_packet.payload_buf, sms_buf, outlen);
            g_s_sms_pdu_packet.payload_len = outlen;
            g_s_sms_pdu_packet.udl = outlen;
        } else {
            /* UCS2 长短信 */
            ref_idx = (ref_idx + 1) % 255;
            g_s_sms_pdu_packet.maxNum = (outlen + LUAT_SMS_LONG_MSG_PDU_SIZE - 1) / LUAT_SMS_LONG_MSG_PDU_SIZE;
            g_s_sms_pdu_packet.refNum = ref_idx;
            memcpy(g_s_sms_pdu_packet.payload_buf, sms_buf, LUAT_SMS_LONG_MSG_PDU_SIZE);
            g_s_sms_pdu_packet.payload_len = LUAT_SMS_LONG_MSG_PDU_SIZE;
            g_s_sms_pdu_packet.udl = LUAT_SMS_LONG_MSG_PDU_SIZE + 6;
        }
    }

    g_s_sms_send.payload = sms_buf;
    g_s_sms_send.payload_len = outlen;
    return 0;
}

/*
异步发送短信
@api sms.send(phone, msg, auto_phone_fix, need_report)
@string 电话号码,必填
@string 短信内容,必填
@bool   是否自动处理电话号号码的格式,默认是按短信内容和号码格式进行自动判断, 设置为false可禁用
@bool   是否请求短信回执(状态报告),默认false不请求,设为true时接收方成功接收后会收到SMS_REPORT消息
@return bool 成功返回true,否则返回false或nil
@usgae
-- 短信号码支持2种形式
-- +XXYYYYYYY 其中XX代表国家代码, 中国是86, 推荐使用这种
-- YYYYYYYYY  直接填目标号码, 例如10010, 10086, 或者国内的手机号码
log.info("sms", sms.send("+8613416121234", "Hi, LuatOS - " .. os.date()))

-- 直接使用目标号码, 不做任何自动化处理. 2023.09.21新增
log.info("sms", sms.send("85513416121234", "Hi, LuatOS - " .. os.date()), false)

-- 请求短信回执, 接收方成功接收后会收到 SMS_REPORT 消息
sms.send("+8613416121234", "Hi, LuatOS", true, true)
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
    uint8_t need_report = 0;
    if (lua_isboolean(L, 4) && lua_toboolean(L, 4)) {
        need_report = 1;
    }

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

    if (sms_encode_and_pack(payload, payload_len) < 0) {
        lua_pushboolean(L, 0);
        return 1;
    }

    g_s_sms_pdu_packet.auto_phone = auto_phone;
    g_s_sms_pdu_packet.phone_len = phone_len;
    g_s_sms_pdu_packet.phone = phone;
    g_s_sms_pdu_packet.seqNum = 1;
    g_s_sms_pdu_packet.srr = need_report;
    if (need_report)
        g_s_sms_pdu_packet.vp = 5; // 30分钟有效期, 超时后SMSC返回EXPIRED

    int len = luat_sms_pdu_packet(&g_s_sms_pdu_packet);
    LLOGD("pdu len %d", len);
    int ret = luat_sms_send_msg_v2(g_s_sms_pdu_packet.pdu_buf, len);
    if (!ret) {
        lua_pushboolean(L, 1);
        return 1;
    }
    // 发送失败，释放已分配的 payload
    if (g_s_sms_send.payload != NULL) {
        luat_heap_free(g_s_sms_send.payload);
        g_s_sms_send.payload = NULL;
    }
    g_s_sms_pdu_packet.maxNum = 0;
    lua_pushboolean(L, 0);
    return 1;
}

/*
同步发送短信
@api sms.sendLong(phone, msg, auto_phone_fix, need_report).wait()
@string 电话号码,必填
@string 短信内容,必填
@bool   是否自动处理电话号号码的格式,默认是按短信内容和号码格式进行自动判断, 设置为false可禁用
@bool   是否请求短信回执(状态报告),默认false不请求,设为true时接收方成功接收后会收到SMS_REPORT消息
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
    const char* phone = luaL_checklstring(L, 1, &phone_len);
    const char* payload = luaL_checklstring(L, 2, &payload_len);
    int auto_phone = 1;
    if (lua_isboolean(L, 3) && !lua_toboolean(L, 3)) {
        auto_phone = 0;
    }
    uint8_t need_report = 0;
    if (lua_isboolean(L, 4) && lua_toboolean(L, 4)) {
        need_report = 1;
    }

    // 当前有其他地方在发送短信
    if (g_s_sms_pdu_packet.maxNum) {
        LLOGE("sms is busy");
        lua_pushboolean(L, 0);
        luat_pushcwait_error(L, 1);
        return 1;
    }
    // 当前有其他地方在用sms.sendLong发送短信
    if (long_sms_send_idp) {
        lua_pushboolean(L, 0);
        luat_pushcwait_error(L, 1);
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

    if (sms_encode_and_pack(payload, payload_len) < 0) {
        goto SMS_FAIL;
    }

    long_sms_send_idp = luat_pushcwait(L);

    g_s_sms_pdu_packet.auto_phone = auto_phone;
    g_s_sms_pdu_packet.phone_len = phone_len;
    g_s_sms_pdu_packet.phone = phone;
    g_s_sms_pdu_packet.seqNum = 1;
    g_s_sms_pdu_packet.srr = need_report;
    if (need_report)
        g_s_sms_pdu_packet.vp = 5; // 30分钟有效期, 超时后SMSC返回EXPIRED

    {
        int len = luat_sms_pdu_packet(&g_s_sms_pdu_packet);
        LLOGD("pdu len %d", len);
        int ret = luat_sms_send_msg_v2(g_s_sms_pdu_packet.pdu_buf, len);
        if (!ret) {
            return 1;
        }
    }
SMS_FAIL:
    long_sms_send_idp = 0;
    g_s_sms_pdu_packet.maxNum = 0;
    if (g_s_sms_send.payload != NULL) {
        luat_heap_free(g_s_sms_send.payload);
        g_s_sms_send.payload = NULL;
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

/**
PDU短信解包
@api sms.unpack(pdu_data)
@string pdu_data PDU格式的短信数据(hex字符串)
@return table 解包后的短信内容
@usage
local pdu = "0491680010F50400069110102143650008024F60"
local phone, txt, metas = sms.unpack(pdu)
log.info("sms unpack", phone, txt, metas and json.encode(metas) or "")
*/
static int l_sms_pdu_unpack(lua_State *L) {
    size_t pdu_len = 0;
    const char* pdu_hex = luaL_checklstring(L, 1, &pdu_len);
    uint8_t* pdu_bin = NULL;
    size_t bin_len = 0;
    int ret = 0;
    luat_sms_recv_msg_t* sms = NULL;
    size_t i = 0;
    int hi = 0, lo = 0;

    if (pdu_len == 0 || pdu_hex == NULL) {
        LLOGE("pdu_data is empty");
        return 0;
    }

    /* 检查是否为 hex 字符串 (长度为偶数且全是 hex 字符) */
    if (pdu_len % 2 != 0) {
        LLOGE("pdu_data length must be even (hex string), got %d", pdu_len);
        return 0;
    }

    /* 分配二进制缓冲区 */
    bin_len = pdu_len / 2;
    pdu_bin = luat_heap_malloc(bin_len);
    if (pdu_bin == NULL) {
        LLOGE("out of memory when malloc pdu_bin");
        return 0;
    }

    /* hex 字符串转二进制 */
    for (i = 0; i < bin_len; i++) {
        hi = pdu_hex[i * 2];
        lo = pdu_hex[i * 2 + 1];
        
        /* 转换高4位 */
        if (hi >= '0' && hi <= '9') hi = hi - '0';
        else if (hi >= 'A' && hi <= 'F') hi = hi - 'A' + 10;
        else if (hi >= 'a' && hi <= 'f') hi = hi - 'a' + 10;
        else {
            LLOGE("invalid hex char at pos %d: 0x%02X", i * 2, hi);
            luat_heap_free(pdu_bin);
            return 0;
        }
        
        /* 转换低4位 */
        if (lo >= '0' && lo <= '9') lo = lo - '0';
        else if (lo >= 'A' && lo <= 'F') lo = lo - 'A' + 10;
        else if (lo >= 'a' && lo <= 'f') lo = lo - 'a' + 10;
        else {
            LLOGE("invalid hex char at pos %d: 0x%02X", i * 2 + 1, lo);
            luat_heap_free(pdu_bin);
            return 0;
        }
        
        pdu_bin[i] = (hi << 4) | lo;
    }

    LLOGD("PDU hex len=%d, bin len=%d", pdu_len, bin_len);

    sms = luat_heap_malloc(sizeof(luat_sms_recv_msg_t));
    if (sms == NULL) {
        LLOGE("out of memory when malloc sms unpack");
        luat_heap_free(pdu_bin);
        return 0;
    }
    memset(sms, 0x00, sizeof(luat_sms_recv_msg_t));

    ret = luat_sms_pdu_message_unpack(sms, pdu_bin, bin_len);
    luat_heap_free(pdu_bin);

    if (ret != 0) {
        LLOGE("sms pdu unpack fail %d", ret);
        luat_heap_free(sms);
        return 0;
    }

    /* 返回结果 */
    char* dst = luat_heap_malloc(strlen(sms->sms_buffer) + 2);
    size_t dstlen = 0;
    if (dst == NULL) {
        LLOGE("out of memory when malloc sms unpack tmpbuff");
        luat_heap_free(sms);
        return 0;
    }
    // 打印sms->dcs_info.alpha_bet和数据
    if (sms->dcs_info.alpha_bet == 0) {
        memcpy(dst, sms->sms_buffer, strlen(sms->sms_buffer));
        dstlen = strlen(sms->sms_buffer);
    }
    else {
        luat_str_ucs2_to_char(sms->sms_buffer, strlen(sms->sms_buffer), dst, &dstlen);
        dst[dstlen] = 0;
    }
    push_sms_args(L, sms, dst, dstlen);
    luat_heap_free(dst);
    luat_heap_free(sms);
    return 3;
}

/**
设置短信模块的调试模式
@api sms.debug(enable)
@bool enable 是否启用调试模式,true为启用,false为禁用
@return nil 无返回值
@usage
-- 启用短信调试模式,会输出更多日志信息
sms.debug(true)
-- 禁用短信调试模式
sms.debug(false)
 */
static int l_sms_set_debug(lua_State *L) {
    bool enable = lua_toboolean(L, 1) == 1 ? 1 : 0;
    luat_sms_set_debug(enable);
    return 0;
}

/**
设置短信回执(状态报告)回调函数
@api sms.setReportCb(func)
@function 回调函数, 5个参数: msg_ref, status, status_str, phone, discharge_time
@return nil 传入是函数就能成功,无返回值
@usage
sms.setReportCb(function(msg_ref, status, status_str, phone, discharge_time)
    -- msg_ref:        消息参考号(number), 用于匹配发送的短信
    -- status:         状态码(number), 0=成功送达
    -- status_str:     状态描述(string), 如 "SUCCESS"/"FAILED_TEMP_*"/"FAILED_PERM_*"
    -- phone:          接收方手机号(string)
    -- discharge_time: 送达/失败时间(string), 格式 "YY-MM-DD HH:MM:SS"
    log.info("sms report", msg_ref, status, status_str, phone, discharge_time)
end)
 */
static int l_sms_set_report_cb(lua_State *L) {
    if (lua_sms_report_ref) {
        luaL_unref(L, LUA_REGISTRYINDEX, lua_sms_report_ref);
        lua_sms_report_ref = 0;
    }
    if (lua_isfunction(L, 1)) {
        lua_sms_report_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_sms[] =
{
    { "send",           ROREG_FUNC(l_sms_send)},
    { "setNewSmsCb",    ROREG_FUNC(l_sms_cb)},
    { "autoLong",       ROREG_FUNC(l_sms_auto_long)},
    { "clearLong",      ROREG_FUNC(l_sms_clear_long)},
    { "sendLong",       ROREG_FUNC(l_long_sms_send)},
    { "unpack",         ROREG_FUNC(l_sms_pdu_unpack)},
    { "setReportCb",    ROREG_FUNC(l_sms_set_report_cb)},
    { "debug",          ROREG_FUNC(l_sms_set_debug)},
	{ NULL,             ROREG_INT(0)}
};


LUAMOD_API int luaopen_sms( lua_State *L ) {
    luat_newlib2(L, reg_sms);
    return 1;
}
