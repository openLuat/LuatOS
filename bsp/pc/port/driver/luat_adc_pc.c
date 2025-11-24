#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include <stdlib.h>
#include "luat_mock.h"
#include "luat_adc.h"

int luat_adc_open(int pin, void* args) {
    (void)args;
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(int);
    ctx.req_data = (char*)&pin;
    memcpy(ctx.key, "adc.open", strlen("adc.open"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_adc_read(int pin, int* val, int* val2) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(int);
    ctx.req_data = (char*)&pin;
    memcpy(ctx.key, "adc.read", strlen("adc.read"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(val, ctx.resp_data, sizeof(int));
      memcpy(val2, ctx.resp_data + sizeof(int), sizeof(int));
      return 0;
    }
    #endif
    if (pin == LUAT_ADC_CH_CPU) {
      *val = 45000;
      *val2 = 45000;
    }
    else if (pin == LUAT_ADC_CH_VBAT) {
      *val = 4120;
      *val2 = 4120;
    }
    else {
      *val = -1;
      *val2 = -1;
    }
    return 0;
}
int luat_adc_close(int pin) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(int);
    ctx.req_data = (char*)&pin;
    memcpy(ctx.key, "adc.close", strlen("adc.close"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_adc_global_config(int tp, int val) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    int tmp[2] = {tp, val};
    ctx.req_len = sizeof(int) * 2;
    ctx.req_data = (char*)&tmp;
    memcpy(ctx.key, "adc.global_config", strlen("adc.global_config"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}
