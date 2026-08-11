#include "luat_base.h"
#include "luat_sms.h"

#define  LUAT_LOG_TAG "sms"
#include "luat_log.h"

int luat_sms_send_msg_v2(uint8_t *pdu_data, size_t pdu_len) {
    LLOGE("sms send pdu not support in pc env, yet %p %d", pdu_data, pdu_len);
    return -1;
}

void luat_sms_get_last_send_result(uint8_t *rp_cause, uint8_t *tp_cause, uint8_t *msg_ref) {

}
