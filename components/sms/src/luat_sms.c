#include "luat_sms.h"


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


void ucs2char(char* source, size_t size, char* dst2, size_t* outlen) {
    char buff[size + 2];
    memset(buff, 0, size + 2);
    luat_str_fromhex(source, size, buff);
    uint16_t* tmp = (uint16_t*)buff;
    char* dst = dst2;
    uint16_t unicode = 0;
    size_t dstlen = 0;
    while (1) {
        unicode = *tmp ++;
        unicode = ((unicode >> 8) & 0xFF) + ((unicode & 0xFF) << 8);
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
            continue;
        }
        break;
    }
    *outlen = dstlen;
}

int utf82ucs2(char* source, size_t source_len, char* dst, size_t dstlen, size_t* outlen) {
    uint16_t unicode = 0;
    size_t tmplen = 0;
    for (size_t i = 0; i < source_len; i++)
    {
        if(tmplen >= dstlen) {
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