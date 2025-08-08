#include "luat_sms.h"
#include "luat_str.h"

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

void luat_sms_pdu_message_unpack(luat_sms_recv_msg_t *msg_info, uint8_t *pdu_data, int pdu_len)
{
    uint16_t pos = 0;
    uint8_t sca_len = pdu_data[pos];
    pos += 1;
    // sca
    uint8_t Sca[16] = {0};
    if (sca_len != 0x00)
    {
        memcpy(&pdu_data[1], Sca, sca_len);
        pos += sca_len;
    }

    // PDU Type
    uint8_t pdu_type = pdu_data[pos];
    pos += 1;

    // OA
    uint8_t OaLen = pdu_data[pos];
    pos += 1;

    // Oa Type
    uint8_t OaType = pdu_data[pos];
    pos += 1;

    uint8_t OaLen2 = 0;
    if (OaLen % 2 == 0)
    {
        OaLen2 = OaLen / 2;
    }
    else
    {
        OaLen2 = OaLen / 2 + 1;
    }

    // 手机号
    uint8_t Oa[20] = {0};
    memcpy(Oa, &pdu_data[pos], OaLen2);
    pos += OaLen2;

    uint8_t number[30] = {0};
    uint8_t onechar = 0;
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

    // PID
    uint8_t Pid = pdu_data[pos];
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

    uint8_t payload[160] = {0};
    uint8_t payload_len = pdu_data[pos];
    memcpy(payload, &pdu_data[pos], payload_len + 1);

    pos = 1;
    uint8_t user_data_len = 0;
    uint8_t udl = payload_len;
    uint8_t length = udl;
    uint8_t is_long_msg = 0;
    uint8_t user_total_len = 0;

    if (pdu_type & 0x40) // 是长短信
    {
        is_long_msg = 1;
    }

    uint8_t maxNum = 0;
    uint8_t seqNum = 0;
    uint8_t refNum = 0;

    uint8_t encode_type = parse_dcs_encode_type(Dcs);
    if (encode_type == LUAT_SMS_CODE_7BIT) // 7bit ASCII
    {
        uint16_t fill_bits = 0;
        if (is_long_msg)
        {
            uint8_t udhl = payload[pos];    // udh的长度
            refNum = payload[pos + 3];      // 参考序号
            seqNum = payload[pos + 5];      // 当前序号
            maxNum = payload[pos + 4];      // 消息总条数
            user_total_len = udhl + 1; // udh的总长度, 包括udlh
            if (0 != (user_total_len * 8) % 7)
            {
                fill_bits = 7 - (user_total_len * 8) % 7;
            }
            length -= ((user_total_len * 8) + fill_bits) / 7; /* 23.040 Figure 9.2.3.24(a) number of Septet in SM */
            pos = 1 + user_total_len;                      /* index point to SM */
        }
        user_data_len = (udl * 7) / 8 + ((udl * 7) % 8 == 0 ? 0 : 1);

        // 处理payload
        uint8_t *user_payload = (uint8_t *)luat_heap_malloc(160 + 1);

        luat_sms_decode_7bit_data(&payload[pos], user_data_len, user_payload, 160, fill_bits);

        length = luat_sms_gsm_to_ascii(user_payload, length);

        memcpy(msg_info->sms_buffer, user_payload, length);
        
        luat_heap_free(user_payload);
    }
    else if (encode_type == LUAT_SMS_CODE_UCS2) // ucs2
    {

        if (is_long_msg)
        {
            /* parse msg header */
            user_total_len = 1;
            user_total_len += payload[pos];  // udh的长度
            refNum = payload[pos + 3];      // 参考序号
            seqNum = payload[pos + 5];      // 当前序号
            maxNum = payload[pos + 4];      // 消息总条数
            pos += user_total_len;
        }
        else
        {
            user_total_len = 0;
        }
        uint8_t body_length = 0;         /* SM length */
        body_length = udl - user_total_len;
        /* code */
        luat_str_tohex(&payload[pos], body_length, msg_info->sms_buffer);
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
}


int luat_sms_pdu_packet(luat_sms_pdu_packet_t *packet)
{
    // 先处理一下电话号码
    uint8_t gateway_mode = 0;	//短信网关特殊处理
    uint8_t pos = 0;
    size_t phone_len = packet->phone_len;
    char phone_buff[32] = {0};
    if ((packet->phone_len >= 15) && !memcmp(packet->phone, "10", 2)) {
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
    uint8_t udhi[6] = {0x05, 0x00, 0x03, packet->refNum, packet->maxNum, packet->seqNum};
    memcpy(packet->pdu_buf + pos, udhi, 6);
    pos += 6;
    memcpy(packet->pdu_buf + pos, packet->payload_buf, packet->payload_len);
    pos += packet->payload_len;
    return pos;
}