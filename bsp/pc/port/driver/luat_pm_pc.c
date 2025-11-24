#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include <stdlib.h>
#include "luat_mock.h"
#include "luat_wdt.h"

int luat_pm_request(int mode) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(int);
    ctx.req_data = (char*)&mode;
    memcpy(ctx.key, "pm.request", strlen("pm.request"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_pm_release(int mode) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(int);
    ctx.req_data = (char*)&mode;
    memcpy(ctx.key, "pm.release", strlen("pm.release"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}


int luat_pm_dtimer_start(int id, size_t timeout) {
    (void)id;
    (void)timeout;
    return -1;
}

int luat_pm_dtimer_stop(int id) {
    (void)id;
    return 0;
}

int luat_pm_dtimer_check(int id) {
    (void)id;
    return 0;
}

int luat_pm_last_state(int *lastState, int *rtcOrPad) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    memcpy(ctx.key, "pm.lastState", strlen("pm.lastState"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(lastState, ctx.resp_data, sizeof(int));
      memcpy(lastState, ctx.resp_data + sizeof(int), sizeof(int));
      return 0;
    }
    #endif
    return 0;
}


int luat_pm_force(int mode) {
    return luat_pm_request(mode);
}


int luat_pm_check(void) {
    return 0;
}


int luat_pm_dtimer_list(size_t* count, size_t* list) {
    *count = 0;
    (void)list;
    return 0;
}


int luat_pm_dtimer_wakeup_id(int* id) {
    (void)id;
    return 0;
}


int luat_pm_poweroff(void) {
    exit(0);
    return 0;
}


int luat_pm_reset(void) {
    exit(0);
    return 0;
}


int luat_pm_power_ctrl(int id, uint8_t val) {
    (void)id;
    (void)val;
    return 0;
}


int luat_pm_get_poweron_reason(void) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    memcpy(ctx.key, "pm.reason", strlen("pm.reason"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0; // 暂时就0吧
}

int luat_pm_iovolt_ctrl(int id, int val) {
    (void)id;
    (void)val;
    return 0;
}

int luat_pm_wakeup_pin(int pin, int val) {
    (void)pin;
    (void)val;
    return -1;
}

int luat_pm_set_power_mode(uint8_t mode, uint8_t sub_mode) {
    (void)mode;
    (void)sub_mode;
    return 0;
}

uint32_t luat_pm_dtimer_remain(int id){
	return 0;
}

