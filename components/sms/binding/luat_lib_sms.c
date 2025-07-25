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

typedef struct 
{
    size_t phone_len;           // 电话号码长度
    size_t payload_len;          // 待编码的数据长度
    const char *phone;          // 电话号码
    uint8_t pdu_buf[320];       // 组包后的PDU短信
    uint8_t payload_buf[200];    // 编码后的短信数据
    uint8_t auto_phone;         // 是否自动处理电话号码
    uint8_t maxNum;             // 短信最大条数， 长短信用
    uint8_t seqNum;             // 当前短信序号
}luat_sms_pdu_packet_t;

#define LONG_SMS_CMAX (128)
static long_sms_t* lngbuffs[LONG_SMS_CMAX];
// static char* longsms = NULL;
// static int longsms_refNum = -1;

enum{
	SMS_EVENT_SEND_RET = 0,
};
luat_rtos_task_handle sms_send_task_handle = NULL;
typedef struct long_sms_send
{
    size_t payload_len;
    size_t phone_len;
    const char *phone;
    uint8_t *payload;
    uint8_t auto_phone;
}long_sms_send_t;

static uint8_t idx = 254;

static uint64_t long_sms_send_idp;


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

static int utf82ucs2(char* source, size_t source_len, char* dst, size_t dstlen, size_t* outlen) {
    uint16_t unicode = 0;
    size_t tmplen = 0;
    for (size_t i = 0; i < source_len; i++)
    {
        if(tmplen >= dstlen) {
            LLOGE("tmplen >= dstlen index: %d, tmplen: %d, dstlen: %d", i, tmplen, dstlen);
            return -1;
        }
        // 首先是不是单字节
        if (source[i] & 0x80) {
            // 非ASCII编码
            if (source[i] && 0xE0) { // 1110xxxx 10xxxxxx 10xxxxxx
                unicode = ((source[i] & 0x0F) << 12) + ((source[i+1] & 0x3F) << 6) + (source[i+2] & 0x3F);
                dst[tmplen++] = (unicode >> 8) & 0xFF;
                dst[tmplen++] = unicode & 0xFF;
                i+=2;
                continue;
            }
            if (source[i] & 0xC0) { // 110xxxxx 10xxxxxx
                unicode = ((source[i] & 0x1F) << 6) + (source[i+1] & 0x3F);
                dst[tmplen++] = (unicode >> 8) & 0xFF;
                dst[tmplen++] = unicode & 0xFF;
                i++;
                continue;
            }
            LLOGE("bat utf8 string");
            return -1;
        }
        // 单个ASCII字符, 但需要扩展到2位
        else {
            // ASCII编码
            dst[tmplen++] = 0x00;
            dst[tmplen++] = source[i];
            continue;
        }
    }
    *outlen = tmplen;
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
    if(long_sms_send_idp) {
        LLOGE("send cb: %d", ret);
        luat_rtos_event_send(sms_send_task_handle, SMS_EVENT_SEND_RET, ret, 0, 0, 0);
    }
}

/*
发送短信
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
    char phone_buff[32] = {0};

    if (payload_len == 0) {
        LLOGE("sms is emtry");
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
    if (ret != 0) {
        LLOGE("utf82ucs2 encode fail");
        luat_heap_free(ucs2_buf);
        return 0;
    }

    if(outlen > 140)
    {
        LLOGE("sms is too long %d > 140", outlen);
        luat_heap_free(ucs2_buf);
        return 0;
    }
    luat_sms_pdu_packet_t pdu_packet = {0};
    memcpy(pdu_packet.payload_buf, ucs2_buf, outlen);
    luat_heap_free(ucs2_buf);
    pdu_packet.auto_phone = auto_phone;
    pdu_packet.payload_len = outlen;
    pdu_packet.maxNum = 1;
    pdu_packet.phone_len = phone_len;
    pdu_packet.phone = phone;
    int len = luat_sms_pdu_packet(&pdu_packet);
    LLOGW("pdu len %d", len);
    ret = luat_sms_send_msg_v2(pdu_packet.pdu_buf, len);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    LLOGD("sms ret %d", ret);
    return 1;
}

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
    return 0;
}

static int hex2int(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return -1;
}




//buf PDU缓冲区, phone 电话号码, payload 信息内容, phone_len 电话号码长度, payload_len 信息内容长度, auto_phone 是否自动处理电话号码, is_long 是否长短信, maxNum 最大条数, seqNum 当前序号
int luat_sms_pdu_packet(luat_sms_pdu_packet_t *packet)
{
    // 先处理一下电话号码
    uint8_t gateway_mode = 0;	//短信网关特殊处理
    uint8_t pos = 0;
    size_t phone_len = packet->phone_len;
    char phone_buff[32] = {0};
    if ((packet->phone_len >= 15) && !memcmp(packet->phone, "10", 2)) {
    	LLOGI("sms gateway mode");
    	gateway_mode = 1;
    	memcpy(phone_buff, packet->phone, phone_len);
    }
    else
    {
        if (packet->auto_phone) {
            if (packet->phone[0] == '+') {
                memcpy(phone_buff, packet->phone + 1, phone_len - 1);
                phone_len -= 1;
            }
            // 13416121234
            else if (packet->phone[0] != '8' && packet->phone[1] != '6') {
                phone_buff[0] = '8';
                phone_buff[1] = '6';
                memcpy(phone_buff + 2, packet->phone, phone_len);
                phone_len += 2;
            }
            else {
                memcpy(phone_buff, packet->phone, phone_len);
            }
        }
        else {
            memcpy(phone_buff, packet->phone, phone_len);
        }
    }

    packet->pdu_buf[pos++] = 0x00;
    if(packet->maxNum == 1)
    {
        packet->pdu_buf[pos++] = 0x01;
    }
    else
    {
        packet->pdu_buf[pos++] = 0x41;
    }
    packet->pdu_buf[pos++] = 0x00;
    packet->pdu_buf[pos++] = phone_len;
    packet->pdu_buf[pos++] = gateway_mode ? 0x81 : 0x91;
    uint8_t one_char = 0;
    for (size_t i = 0; i < phone_len; i+=2)
    {
        if (i == (phone_len - 1) && phone_len % 2 != 0) {
            one_char = hex2int('F') << 4;
            one_char |= (0x0F & hex2int(phone_buff[i]));
            packet->pdu_buf[pos++] = one_char; 
        }
        else {
            one_char = hex2int(phone_buff[i+1]) << 4;
            one_char |= (0x0F & hex2int(phone_buff[i]));
            packet->pdu_buf[pos++] = one_char;
        }
    }

    packet->pdu_buf[pos++] = 0x00;
    packet->pdu_buf[pos++] = 0x08;
    if(packet->maxNum == 1)
    {
        packet->pdu_buf[pos++] = packet->payload_len;
        memcpy(packet->pdu_buf + pos, packet->payload_buf, packet->payload_len);
        pos += packet->payload_len;
        return pos;
    }
    packet->pdu_buf[pos++] = packet->payload_len + 6;

    // 长短信
    // UDHI
    // 0: UDHL,    固定 0x05 
    // 1: IEI,     固定 0X00
    // 2: IEDL,    固定 
    // 3: Reference NO 消息参考序号
    // 4: Maximum   NO 消息总条数
    // 5: Current   NO 当前短信序号
    // uint8_t udhi[6] = {0x05, 0x00, 0x03, 0x00, 0x00, 0x00};
    uint8_t udhi[6] = {0x05, 0x00, 0x03, idx, packet->maxNum, packet->seqNum};
    memcpy(packet->pdu_buf + pos, udhi, 6);
    pos += 6;
    memcpy(packet->pdu_buf + pos, packet->payload_buf, packet->payload_len);
    pos += packet->payload_len;
    return pos;
}

void long_sms_send_task(void *params)
{
    long_sms_send_t *args = (long_sms_send_t*)params;
    int ret = 0;
    uint8_t is_done = 0; 
    uint8_t is_error = 0;
    rtos_msg_t msg = {
        .handler = l_long_sms_send_callback,
        .arg1 = 0,
        .arg2 = 0
    };
    size_t outlen = args->payload_len;
    uint16_t pducnt = (outlen + 133) / 134;
    idx = (idx  + 1) % 255;
    luat_event_t event = {0};
    uint16_t i = 0;
    uint16_t sn = 1;
    char tmp[3] = {0};
    luat_sms_pdu_packet_t pdu_packet = {0};
    pdu_packet.auto_phone = args->auto_phone;
    pdu_packet.maxNum = pducnt;
    pdu_packet.phone_len = args->phone_len;
    pdu_packet.phone = args->phone;
    while(1)
    {
        if (outlen - i <= 134) {
            memcpy(pdu_packet.payload_buf, args->payload + i, outlen - i);
            pdu_packet.payload_len = (outlen - i);
            is_done = 1;
        } else {
            memcpy(pdu_packet.payload_buf, args->payload + i, 134);
            pdu_packet.payload_len = 134;
            i += 134;
        }
        pdu_packet.seqNum = sn;
        int pos = luat_sms_pdu_packet(&pdu_packet);
        sn++;
        ret = luat_sms_send_msg_v2(pdu_packet.pdu_buf, pos);
        if (ret) {
            LLOGE("long sms send fail:%d", ret);
            is_error = 1;
            break;
        }
        ret = luat_rtos_event_recv(sms_send_task_handle, 0, &event, NULL, 30000); // 30s没收到,则认为发送失败
        if (ret || event.id != SMS_EVENT_SEND_RET || event.param1 != 0) {
            // 异常
            LLOGE("long sms except:%d, %d", ret, event.param1);
            is_error = 1;
            break;
        }
        if (is_done) {
            break;
        }
    }

LONG_SMS_DONE:
    msg.arg1 = is_error;
    luat_msgbus_put(&msg, 0);
    if(args->payload != NULL)
    {
        luat_heap_free(args->payload);
        args->payload = NULL;
    }
    if (args != NULL)
    {
        luat_heap_free(args);
        args = NULL;
    }
    luat_rtos_task_delete(sms_send_task_handle);
}

/*
发送长短信(每段PDU发送超时时间30s)
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
    uint8_t *ucs2buf = NULL;
    long_sms_send_t *args = NULL;
    const char* phone = luaL_checklstring(L, 1, &phone_len);
    const char* payload = luaL_checklstring(L, 2, &payload_len);
    int auto_phone = 1;
    if (lua_isboolean(L, 3) && !lua_toboolean(L, 3)) {
        auto_phone = 0;
    }

    if (long_sms_send_idp) {
        lua_pushboolean(L, 0);
        luat_pushcwait_error(L,1);
        return 1;
    }

    if (payload_len == 0) {
        LLOGE("sms is emtry");
        goto SMS_FAIL;
    }

    if (phone_len < 3 || phone_len > 29) {
        LLOGE("phone is too short or too long!! %d", phone_len);
        goto SMS_FAIL;
    }

    size_t outlen = 0;
    ucs2buf = (uint8_t *)luat_heap_malloc(payload_len * 3);
    if (ucs2buf == NULL)
    {
        LLOGE("out of memory");
        goto SMS_FAIL;
    }

    memset(ucs2buf, 0x00, payload_len * 3);

    int ret = utf82ucs2(payload, payload_len, ucs2buf, payload_len * 3, &outlen);

    if (ret || outlen <= 140)
    {
        LLOGE("utf8 to ucs2 fail ret: %d, or ucs2 len is too short len: %d", ret, outlen);
        goto SMS_FAIL;
    }

    args = luat_heap_malloc(sizeof(long_sms_send_t));
    if (NULL == args) {
        LLOGE("out of memory");
        goto SMS_FAIL;
    }
    memset(args, 0x00, sizeof(long_sms_send_t));
    args->payload = ucs2buf;
    args->payload_len = outlen;
    args->phone = phone;
    args->phone_len = phone_len;
    args->auto_phone = auto_phone;
    long_sms_send_idp = luat_pushcwait(L);
    ret = luat_rtos_task_create(&sms_send_task_handle, 10 * 1024, 10, "sms_send_task", long_sms_send_task, (void*)args, 10);
    if (!ret) {
        return 1;
    }
    LLOGE("sms send task create failed");
SMS_FAIL:
    long_sms_send_idp = 0;
    if(ucs2buf != NULL) {
        luat_heap_free(ucs2buf);
    }
    if (args != NULL) {
        luat_heap_free(args);
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
    { "sendLong",      ROREG_FUNC(l_long_sms_send)},
	{ NULL,             ROREG_INT(0)}
};


LUAMOD_API int luaopen_sms( lua_State *L ) {
    luat_newlib2(L, reg_sms);
    return 1;
}
