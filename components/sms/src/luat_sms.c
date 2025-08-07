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