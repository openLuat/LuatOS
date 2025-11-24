#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include <stdlib.h>
#include "luat_mock.h"
#include "luat_pwm.h"

int luat_pwm_open(int channel, size_t period, size_t pulse, int pnum) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    luat_pwm_conf_t conf = {
      .channel = channel,
      .period = period,
      .pulse = pulse,
      .pnum = pnum
    };
    ctx.req_len = sizeof(luat_pwm_conf_t);
    ctx.req_data = (char*)&conf;
    memcpy(ctx.key, "pwm.open", strlen("pwm.open"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
  return 0;
}

int luat_pwm_setup(luat_pwm_conf_t* conf) {

    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(luat_pwm_conf_t);
    ctx.req_data = (char*)conf;
    memcpy(ctx.key, "pwm.setup", strlen("pwm.setup"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_pwm_capture(int channel,int freq) {
  return -1;
}

int luat_pwm_close(int channel) {

    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(int);
    ctx.req_data = (char*)&channel;
    memcpy(ctx.key, "pwm.close", strlen("pwm.close"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_pwm_update_dutycycle(int channel, size_t pulse) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    int tmp[2] = {channel, pulse};
    ctx.req_len = sizeof(tmp);
    ctx.req_data = (char*)tmp;
    memcpy(ctx.key, "pwm.update_dutycycle", strlen("pwm.update_dutycycle"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

