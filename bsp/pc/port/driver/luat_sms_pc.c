#include "luat_base.h"
#include "luat_sms.h"

#define  LUAT_LOG_TAG "sms"
#include "luat_log.h"

int luat_sms_send_msg_v2(uint8_t *pdu_data, size_t pdu_len) {
    LLOGE("sms send pdu not support in pc env, yet %p %d", pdu_data, pdu_len);
    return -1;
}
