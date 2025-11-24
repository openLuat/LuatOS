#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include <stdlib.h>
#include "luat_mock.h"
#include "luat_wdt.h"

int luat_wdt_init(size_t timeout) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(size_t);
    ctx.req_data = (char*)&timeout;
    memcpy(ctx.key, "wdt.init", strlen("wdt.init"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_wdt_set_timeout(size_t timeout) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    ctx.req_len = sizeof(size_t);
    ctx.req_data = (char*)&timeout;
    memcpy(ctx.key, "wdt.set_timeout", strlen("wdt.set_timeout"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_wdt_feed(void) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    memcpy(ctx.key, "wdt.feed", strlen("wdt.feed"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}

int luat_wdt_close(void) {
    #ifdef LUAT_USE_MOCKAPI
    int ret = 0;
    luat_mock_ctx_t ctx = {0};
    memcpy(ctx.key, "wdt.close", strlen("wdt.close"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len >= sizeof(int)) {
      memcpy(&ret, ctx.resp_data, sizeof(int));
      return ret;
    }
    #endif
    return 0;
}