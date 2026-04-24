
#include "luat_base.h"
#include "luat_sms.h"
#include "luat_str.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "sms"
#include "luat_log.h"

static bool sms_debug_enable = 0;

/*
 * ASCII 到 GSM7 的正向映射表，索引为 ASCII 码 (0x00-0x7F)。
 * 0xFF = 不可编码。
 * (val & 0x80) != 0 表示扩展字符，需 2 个 septet (ESC + 低 7 位为扩展表索引)。
 * 其余值为 GSM7 basic 字符码。
 */
static const uint8_t ascii_to_gsm7[128] = {
/*00*/ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, /* 0x00-0x07 */
/*08*/ 0xFF, 0xFF, 0x0A, 0xFF, 0xFF, 0x0D, 0xFF, 0xFF, /* 0x08-0x0F  LF CR */
/*10*/ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, /* 0x10-0x17 */
/*18*/ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, /* 0x18-0x1F */
/*20*/ 0x20, 0x21, 0x22, 0x23, 0x02, 0x25, 0x26, 0x27, /* SP ! " # $ % & ' */
/*28*/ 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, /* ( ) * + , - . / */
/*30*/ 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, /* 0-7 */
/*38*/ 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, /* 8 9 : ; < = > ? */
/*40*/ 0x00, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, /* @ A B C D E F G */
/*48*/ 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, /* H I J K L M N O */
/*50*/ 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, /* P Q R S T U V W */
/*58*/ 0x58, 0x59, 0x5A, 0x80|0x3C, 0x80|0x2F, 0x80|0x3E, 0x80|0x14, 0x11, /* X Y Z [ \ ] ^ _ */
/*60*/ 0xFF, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, /* ` a b c d e f g */
/*68*/ 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, /* h i j k l m n o */
/*70*/ 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, /* p q r s t u v w */
/*78*/ 0x78, 0x79, 0x7A, 0x80|0x28, 0x80|0x40, 0x80|0x29, 0x80|0x3D, 0xFF  /* x y z { | } ~ DEL */
};

int luat_sms_check_7bit(const char *str, size_t len)
{
    int septets = 0;
    for (size_t i = 0; i < len; i++) {
        uint8_t c = (uint8_t)str[i];
        if (c >= 0x80) return -1;
        uint8_t gsm = ascii_to_gsm7[c];
        if (gsm == 0xFF) return -1;
        septets += (gsm & 0x80) ? 2 : 1;  /* 扩展字符占 2 个 septet */
    }
    return septets;
}

int luat_sms_encode_7bit_septets(const char *str, size_t len, uint8_t *dst, size_t dst_len)
{
    int out = 0;
    for (size_t i = 0; i < len; i++) {
        uint8_t c = (uint8_t)str[i];
        if (c >= 0x80) return -1;
        uint8_t gsm = ascii_to_gsm7[c];
        if (gsm == 0xFF) return -1;
        if (gsm & 0x80) {
            if (out + 2 > (int)dst_len) return -1;
            dst[out++] = 0x1B;          /* ESC */
            dst[out++] = gsm & 0x7F;    /* 扩展表索引 */
        } else {
            if (out + 1 > (int)dst_len) return -1;
            dst[out++] = gsm;
        }
    }
    return out;
}

int luat_sms_pack_7bit(const uint8_t *septets, size_t char_count, uint8_t *packed, size_t packed_size, size_t bit_offset)
{
    size_t total_bits = bit_offset + char_count * 7;
    size_t byte_count = (total_bits + 7) / 8;
    if (byte_count > packed_size) return -1;
    memset(packed, 0, byte_count);
    for (size_t i = 0; i < char_count; i++) {
        uint8_t val = septets[i] & 0x7F;
        size_t bit_pos  = bit_offset + i * 7;
        size_t byte_idx = bit_pos / 8;
        size_t bit_idx  = bit_pos % 8;
        packed[byte_idx] |= (uint8_t)(val << bit_idx);
        if (bit_idx + 7 > 8) {
            packed[byte_idx + 1] |= (uint8_t)(val >> (8 - bit_idx));
        }
    }
    return (int)byte_count;
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

static int int2hex(uint8_t v)
{
    if (v <= 9)
        return v + '0';
    if (v >= 0x0A && v <= 0x0F)
        return v + 'A' - 10;
    return -1;
}

static uint8_t parse_dcs_class(uint8_t dcs)
{
    uint8_t class = dcs & 0x03;
    switch(class)
    {
        case 0: // class 0
            break;        
        case 1: // class 1
            break;
        case 2: // class 2
            break;
        case 3: // class 3
            break;
        default:
            break;
    }
    return class;
}

static uint8_t parse_dcs_encode_type(uint8_t dcs)
{
    uint8_t type = dcs & 0x0C;
    switch(type)
    {
        case LUAT_SMS_CODE_7BIT:
            break;        
        case LUAT_SMS_CODE_8BIT:
            break;
        case LUAT_SMS_CODE_UCS2:
            break;
        default:
            break;
    }
    return type;
}


static const uint8_t gsm_basic[] = 
{
/*         0     1     2     3     4     5     6     7     8     9     a     b     c     d     e     f */
/* 0 */ '@', '?', '$', '?', 'e', 'e', 'u', 'i', 'o', 'C', 0X0A, '?', '?', 0x0D, 'A', 'a',
/* 1 */ '?', '_', '?', '?', '?', '?', '?', '?', '?', '?', '?', '?', 'A', 'a', '?', 'E',
/* 2 */ ' ', '!', '"', '#', '?', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
/* 3 */ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?',
/* 4 */ '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
/* 5 */ 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'A', 'O', 'N', 'U', '?',
/* 6 */ '?', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
/* 7 */ 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'a', 'o', 'n', 'u', 'a'
};

static const uint8_t gsm_ext[] =
{
/*         0     1     2     3     4     5     6     7     8     9     a     b     c     d     e     f */
/* 0 */ '@', '?', '$', '?', 'e', 'e', 'u', 'i', 'o', 'C', 0X0A, '?', '?', 0x0D, 'A', 'a',
/* 1 */ '?', '_', '?', '?', '^', '?', '?', '?', '?', '?', '?', '?', 'A', 'a', '?', 'E',
/* 2 */ ' ', '!', '"', '#', '?', '%', '&', '\'', '{', '}', '*', '+', ',', '-', '.', '\\',
/* 3 */ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '[', '~', ']', '?',
/* 4 */ '|', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
/* 5 */ 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'A', 'O', 'N', 'U', '?',
/* 6 */ '?', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
/* 7 */ 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'a', 'o', 'n', 'u', 'a'
};

uint8_t luat_sms_gsm_to_ascii(uint8_t *gsm_data, uint8_t length)
{
    uint8_t out_len = 0;
    uint8_t gsm_idx = 0;

    for (gsm_idx = 0; gsm_idx < length; gsm_idx++)
    {
        if (gsm_data[gsm_idx] <= 127)
        {
            if (gsm_data[gsm_idx] == 0x1B)
            {
                gsm_data[out_len++] = gsm_ext[gsm_data[++gsm_idx]];
            }
            else
            {
                gsm_data[out_len++] = gsm_basic[gsm_data[gsm_idx]];
            }
        }
        else
        {
            return out_len;
        }
    }
    return out_len;
}

uint16_t luat_sms_decode_7bit_data(uint8_t *src, uint16_t src_len, uint8_t *dst, uint16_t dst_len, uint16_t shift_bits)
{
    uint16_t temp_index = 0, out_len = 0;
    uint8_t bits = 0;

    shift_bits %= 7;

    if (shift_bits == 1)
    {
        dst[out_len++] = src[temp_index] >> 1;
    }

    if (shift_bits != 0)
    {
        temp_index++;
    }
    else if ((temp_index < src_len) && (out_len < dst_len))
    {
        dst[out_len++] = (src[temp_index++] << bits) & 0x7F;
    }
    bits = (8 - shift_bits) % 7;
    while ((temp_index < src_len) && (out_len < dst_len))
    {
        dst[out_len] = (src[temp_index] << bits) & 0x7F;

        if (temp_index != 0)
        {
            dst[out_len] |= src[temp_index - 1] >> (8 - bits);
        }

        bits++;

        if (bits == 7)
        {
            bits = 0;
            out_len++;
            dst[out_len] = src[temp_index] >> 1;
        }

        temp_index++;
        out_len++;
    }
    return out_len;
}


int luat_sms_pdu_message_unpack(luat_sms_recv_msg_t *msg_info, uint8_t *pdu_data, int pdu_len)
{
    if (msg_info == NULL || pdu_data == NULL || pdu_len < 1)
    {
        return -1;
    }

    if (sms_debug_enable){
        // 打印PDU数据用于调试
        char pdu_debug[3 * 160] = {0};
        luat_str_tohex(pdu_data, pdu_len, pdu_debug);
        LLOGI("PDU Data: %s", pdu_debug);
    }

    uint16_t pos = 0;
    uint8_t sca_len = pdu_data[pos];
    pos += 1;

    // 边界检查
    if (pos + sca_len > pdu_len)
    {
        return -1;
    }

    // sca
    uint8_t Sca[16] = {0};
    if (sca_len != 0x00)
    {
        if (sca_len > sizeof(Sca))
        {
            return -1;
        }
        memcpy(Sca, &pdu_data[pos], sca_len);  // 修正: 源和目标顺序
        pos += sca_len;
    }

    // 边界检查
    if (pos + 2 > pdu_len)
    {
        return -1;
    }

    // PDU Type
    uint8_t pdu_type = pdu_data[pos];
    pos += 1;

    // OA
    uint8_t OaLen = pdu_data[pos];
    pos += 1;

    // 边界检查
    if (pos + 1 > pdu_len)
    {
        return -1;
    }

    // Oa Type
    uint8_t OaType = pdu_data[pos];
    pos += 1;

    uint8_t OaLen2 = (OaLen + 1) / 2;  // 简化计算

    // 边界检查
    if (OaLen2 > 20 || pos + OaLen2 > pdu_len)
    {
        return -1;
    }

    // 手机号
    uint8_t Oa[20] = {0};
    memcpy(Oa, &pdu_data[pos], OaLen2);
    pos += OaLen2;

    uint8_t number[30] = {0};

    if (((OaType >> 4) & 0x07) == 5) // 7bit编码的字符串
    {
        luat_sms_decode_7bit_data(Oa, OaLen2, number, sizeof(number), 0);
        luat_sms_gsm_to_ascii(number, OaLen2);
    }
    else // 其他类型，按照半字节交换处理
    {
        for (size_t i = 0; i < OaLen2; i++)
        {
            number[i * 2] = int2hex(Oa[i] & 0x0F);
            if(i == (OaLen2 - 1))
            {
                if (OaLen % 2 == 0)
                {
                    number[i * 2 + 1] = int2hex((Oa[i] & 0xF0) >> 4);
                }
            }
            else
            {
                number[i * 2 + 1] = int2hex((Oa[i] & 0xF0) >> 4);
            }
        }
    }

    // 边界检查: PID + DCS + SCTS(7 bytes)
    if (pos + 9 > pdu_len)
    {
        return -1;
    }

    // PID
    uint8_t Pid = pdu_data[pos];
    (void)Pid;  // 标记为已使用，避免编译警告
    pos += 1;

    // DCS
    uint8_t Dcs = pdu_data[pos];
    pos += 1;

    // Scts
    uint8_t Scts[7] = {0};
    memcpy(Scts, &pdu_data[pos], 7);
    pos += 7;

    // 解析Scts
    uint8_t year = ((Scts[0] & 0xF0) >> 4) + ((Scts[0] & 0x0F) * 10);
    uint8_t month = ((Scts[1] & 0xF0) >> 4) + ((Scts[1] & 0x0F) * 10);
    uint8_t day = ((Scts[2] & 0xF0) >> 4) + ((Scts[2] & 0x0F) * 10);
    uint8_t hour = ((Scts[3] & 0xF0) >> 4) + ((Scts[3] & 0x0F) * 10);
    uint8_t minute = ((Scts[4] & 0xF0) >> 4) + ((Scts[4] & 0x0F) * 10);
    uint8_t second = ((Scts[5] & 0xF0) >> 4) + ((Scts[5] & 0x0F) * 10);

    // 边界检查
    if (pos >= pdu_len)
    {
        return -1;
    }

    uint8_t payload[160] = {0};
    uint8_t payload_len = pdu_data[pos];  // 对于7bit是septet数，对于8bit/UCS2是字节数

    // 计算实际用户数据字节数 (需要根据DCS判断，但DCS已在前面读取)
    // 先读取剩余可用字节数
    uint16_t remaining_bytes = pdu_len - pos;  // 包含UDL本身

    // 边界检查: 至少要有UDL这1个字节
    if (remaining_bytes < 1)
    {
        return -1;
    }

    // 复制从UDL开始的所有剩余数据到payload
    uint16_t copy_len = remaining_bytes;
    if (copy_len > sizeof(payload))
    {
        copy_len = sizeof(payload);
    }
    memcpy(payload, &pdu_data[pos], copy_len);

    uint16_t payload_pos = 1;
    uint8_t user_data_len = 0;
    uint8_t udl = payload_len;
    uint8_t length = udl;
    uint8_t is_long_msg = 0;
    uint8_t user_total_len = 0;

    uint16_t refNum = 0;
    uint8_t maxNum = 0;
    uint8_t seqNum = 0;
    uint8_t udhl = 0;
    uint8_t iei = 0;

    // 检查是否是长短信 (UDHI标志 或 启发式检测UDH头)
    if (pdu_type & 0x40) // PDU Type设置了UDHI标志
    {
        is_long_msg = 1;
    }
    else if (copy_len >= 7) // 启发式检测: PDU Type未设置UDHI，但数据可能包含UDH
    {
        // 检查是否存在有效的concatenated SMS UDH
        // UDH格式: UDHL(1) + IEI(1) + IEDL(1) + IE_DATA(IEDL)
        uint8_t possible_udhl = payload[1];
        uint8_t possible_iei = payload[2];
        uint8_t possible_iedl = payload[3];
        
        // 标准concatenated SMS: IEI=0x00 (8-bit ref), IEDL=0x03
        // 或 IEI=0x08 (16-bit ref), IEDL=0x04
        if ((possible_udhl == 0x05 && possible_iei == 0x00 && possible_iedl == 0x03) ||
            (possible_udhl == 0x06 && possible_iei == 0x08 && possible_iedl == 0x04))
        {
            is_long_msg = 1;
            if (sms_debug_enable) {
                LLOGI("Detected UDH without UDHI flag set in PDU Type");
            }
        }
    }

    if (is_long_msg) // 是长短信，解析UDH
    {
        if (payload_pos >= copy_len)
        {
            return -1;
        }
        udhl = payload[payload_pos];    // udh的长度
        if (payload_pos + udhl + 1 > copy_len)
        {
            return -1;
        }
        iei = payload[payload_pos + 1]; // 信息元素标识
        if (udhl == 6 && iei == 0x08) // 参考序号2byte
        {
            refNum = (payload[payload_pos + 3] << 8) | payload[payload_pos + 4];      // 参考序号
            seqNum = payload[payload_pos + 6];      // 当前序号
            maxNum = payload[payload_pos + 5];      // 消息总条数
        }
        else
        {
            refNum = payload[payload_pos + 3];      // 参考序号
            seqNum = payload[payload_pos + 5];      // 当前序号
            maxNum = payload[payload_pos + 4];      // 消息总条数
        }
    }

    uint8_t encode_type = parse_dcs_encode_type(Dcs);

    if (encode_type == LUAT_SMS_CODE_7BIT) // 7bit ASCII
    {
        uint16_t fill_bits = 0;
        if (is_long_msg)
        {
            user_total_len = udhl + 1; // udh的总长度, 包括udlh
            if (0 != (user_total_len * 8) % 7)
            {
                fill_bits = 7 - (user_total_len * 8) % 7;
            }
            length -= ((user_total_len * 8) + fill_bits) / 7; /* 23.040 Figure 9.2.3.24(a) number of Septet in SM */
            payload_pos = 1 + user_total_len;                      /* index point to SM */
        }
        // 计算7bit编码的实际字节数
        user_data_len = (udl * 7 + 7) / 8;  // 向上取整
        
        // 确保不超出实际可用数据
        uint16_t available_data = (copy_len > payload_pos) ? (copy_len - payload_pos) : 0;
        if (user_data_len > available_data)
        {
            user_data_len = available_data;
        }

        // 处理payload
        uint8_t *user_payload = (uint8_t *)luat_heap_malloc(160 + 1);
        if (user_payload == NULL)
        {
            return -1;
        }
        memset(user_payload, 0, 160 + 1);

        luat_sms_decode_7bit_data(&payload[payload_pos], user_data_len, user_payload, 160, fill_bits);

        length = luat_sms_gsm_to_ascii(user_payload, length);

        memcpy(msg_info->sms_buffer, user_payload, length);
        msg_info->sms_buffer[length] = '\0';  // 添加字符串结束符
        
        luat_heap_free(user_payload);
    }
    else if (encode_type == LUAT_SMS_CODE_UCS2) // ucs2
    {
        if (is_long_msg)
        {
            user_total_len = udhl + 1;
            payload_pos += user_total_len;
        }
        else
        {
            user_total_len = 0;
        }
        uint8_t body_length = 0;         /* SM length */
        body_length = udl - user_total_len;
        
        // 边界检查
        uint16_t available_data = (copy_len > payload_pos) ? (copy_len - payload_pos) : 0;
        if (body_length > available_data)
        {
            body_length = available_data;
        }
        
        /* code */
        luat_str_tohex(&payload[payload_pos], body_length, (char*)msg_info->sms_buffer);
        msg_info->sms_buffer[body_length * 2] = '\0';  // 添加字符串结束符
        length = body_length * 2;  // 修正: hex字符串长度是原始字节数的2倍
    }
    else if(encode_type == LUAT_SMS_CODE_8BIT) // 8bit
    {
        if (is_long_msg)
        {
            user_total_len = udhl + 1;
            payload_pos += user_total_len;
            length = udl - user_total_len;
        }
        
        // 边界检查
        uint16_t available_data = (copy_len > payload_pos) ? (copy_len - payload_pos) : 0;
        if (length > available_data)
        {
            length = available_data;
        }
        
        memcpy(msg_info->sms_buffer, &payload[payload_pos], length);
        msg_info->sms_buffer[length] = '\0';  // 添加字符串结束符
    }

    msg_info->refNum = refNum;
    msg_info->maxNum = maxNum;
    msg_info->seqNum = seqNum;

    memcpy(msg_info->phone_address, number, OaLen2 * 2);

    msg_info->dcs_info.alpha_bet = encode_type;
    msg_info->sms_length = length;

    msg_info->time.year = year;
    msg_info->time.month = month;
    msg_info->time.day = day;
    msg_info->time.hour = hour;
    msg_info->time.minute = minute;
    msg_info->time.second = second;

    return 0;  // 修正: 添加返回值
}


int luat_sms_pdu_packet(luat_sms_pdu_packet_t *packet)
{
    uint8_t toa = 0x81;
    uint8_t pos = 0;
    size_t phone_len = packet->phone_len;
    char phone_buff[32] = {0};
    if ((packet->phone_len >= 15) && !memcmp(packet->phone, "10", 2)) {
    	memcpy(phone_buff, packet->phone, phone_len);
        toa = 0x81;
    }
    else if(packet->auto_phone)
    {
        if (phone_len > 0 && packet->phone[0] == '+') {
            memcpy(phone_buff, packet->phone + 1, phone_len - 1);
            phone_len -= 1;
            toa = 0x91;
        }
        else if (phone_len >= 2 && packet->phone[0] == '8' && packet->phone[1] == '6') {
            memcpy(phone_buff, packet->phone, phone_len);
            toa = 0x91;
        }
        else if (phone_len == 11 && packet->phone[0] == '1') {
            phone_buff[0] = '8';
            phone_buff[1] = '6';
            memcpy(phone_buff + 2, packet->phone, phone_len);
            phone_len += 2;
            toa = 0x91;
        }
        else {
            memcpy(phone_buff, packet->phone, phone_len);
            toa = 0x81;
        }
    } else {
        memcpy(phone_buff, packet->phone, phone_len);
        if (phone_len >= 2 && packet->phone[0] == '8' && packet->phone[1] == '6') {
            toa = 0x91;
        }
        else {
            toa = 0x81;
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
    packet->pdu_buf[pos++] = toa;
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
    packet->pdu_buf[pos++] = packet->dcs;
    if(packet->maxNum == 1)
    {
        packet->pdu_buf[pos++] = packet->udl ? (uint8_t)packet->udl : (uint8_t)packet->payload_len;
        memcpy(packet->pdu_buf + pos, packet->payload_buf, packet->payload_len);
        pos += packet->payload_len;
        return pos;
    }
    packet->pdu_buf[pos++] = packet->udl ? (uint8_t)packet->udl : (uint8_t)(packet->payload_len + 6);

    // 长短信
    // UDHI
    // 0: UDHL,    固定 0x05 
    // 1: IEI,     固定 0X00
    // 2: IEDL,    固定 
    // 3: Reference NO 消息参考序号
    // 4: Maximum   NO 消息总条数
    // 5: Current   NO 当前短信序号
    // uint8_t udhi[6] = {0x05, 0x00, 0x03, 0x00, 0x00, 0x00};
    uint8_t udhi[6] = {0x05, 0x00, 0x03, packet->refNum, packet->maxNum, packet->seqNum};
    memcpy(packet->pdu_buf + pos, udhi, 6);
    pos += 6;
    memcpy(packet->pdu_buf + pos, packet->payload_buf, packet->payload_len);
    pos += packet->payload_len;
    return pos;
}

int luat_sms_set_debug(bool debug)
{
    sms_debug_enable = debug;
    if (debug)
        LLOGI("SMS debug enabled");
    else
        LLOGI("SMS debug disabled");
    return 0;
}
