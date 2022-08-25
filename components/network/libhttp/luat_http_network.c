#include "luat_base.h"
#include "luat_http.h"
#include "luat_network_adapter.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

static int32_t luat_http_cb(void *pData, void *pParam) {
    OS_EVENT *event = (OS_EVENT *)data;
    luat_http_ctx_t *ctx = (luat_http_ctx_t *)pParam;
    network_ctrl_t *nc = (network_ctrl_t *)ctx->network;

    switch (event->ID)
    {
    case EV_NW_RESULT_LINK:
        LLOGD("http cb EV_NW_RESULT_LINK %d", event->Param1);
        break;
    case EV_NW_RESULT_CONNECT:
        LLOGD("http cb EV_NW_RESULT_CONNECT %d", event->Param1);
        break;
    case EV_NW_RESULT_CLOSE:
        LLOGD("http cb EV_NW_RESULT_CLOSE %d", event->Param1);
        break;
    case EV_NW_RESULT_TX:
        LLOGD("http cb EV_NW_RESULT_TX %d", event->Param1);
        break;
    case EV_NW_RESULT_EVENT:
        LLOGD("http cb EV_NW_RESULT_EVENT %d", event->Param1);
        break;

    default:
        break;
    }
    network_wait_event(nc, NULL, 0, NULL);
    return 0;
}

static int http_thread_main(void* args) {
    luat_http_ctx_t *ctx = (luat_http_ctx_t *)args;
    network_ctrl_t *nc = (network_ctrl_t *)ctx->network;
    if(network_connect(nc, ctx->host, strlen(ctx->host), NULL, ctx->port, 0) < 0){
        network_close(nc, 0);
        return -1;
    }
    return 0;
}

int luat_http_send(luat_http_ctx_t *ctx, http_cb cb) {
    int adapter_index = network_get_last_register_adapter();
    network_ctrl_t *nc = network_alloc_ctrl(adapter_index);
    if (nc == NULL) {
        LLOGW("network alloc fail");
        return -1;
    }
    ctx->network = nc;
    network_init_ctrl(nc, NULL, luat_http_cb, ctx);

    network_set_base_mode(nc, 1, 15000, 0, 0, 0, 0);
	network_set_local_port(nc, 0);
	network_deinit_tls(nc);

    luat_thread_t t = {
        .entry = http_thread_main,
        .name = "httpc",
        .stack_buff = NULL,
        .stack_size = 4096,
        .network = ctx
    };
    int ret = luat_thread_start(&t);
    LLOGD("http thread start ret %d", ret);
    return ret;
}
