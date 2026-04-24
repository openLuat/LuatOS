/*
 * AirLink GPIO nanopb RPC exec handler (服务端)
 *
 * 将 GpioRpcRequest 分发到对应的 luat_gpio_* 函数，填写 GpioRpcResponse。
 * proto enum 值 = C 宏值 + 1（0 保留给 UNSPECIFIED），转换时减 1。
 */

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC

#include "luat_airlink_rpc.h"
#include "luat_gpio.h"
#include "drv_gpio.pb.h"

#define LUAT_LOG_TAG "airlink.rpc.gpio"
#include "luat_log.h"

#define AIRLINK_RPC_ID_GPIO  0x0100

// proto enum (1-based) → C 宏 (0-based) 转换辅助
static inline int proto_mode_to_c(drv_gpio_GpioMode m) {
    return (m > 0) ? (int)(m - 1) : Luat_GPIO_INPUT;
}
static inline int proto_pull_to_c(drv_gpio_GpioPull p) {
    return (p > 0) ? (int)(p - 1) : Luat_GPIO_DEFAULT;
}
static inline int proto_level_to_c(drv_gpio_GpioLevel l) {
    return (l > 0) ? (int)(l - 1) : Luat_GPIO_LOW;
}
static inline int proto_irq_to_c(drv_gpio_GpioIrqType t) {
    return (t > 0) ? (int)(t - 1) : Luat_GPIO_RISING;
}
static inline drv_gpio_GpioLevel c_level_to_proto(int level) {
    return (level == Luat_GPIO_HIGH) ? drv_gpio_GpioLevel_GPIO_LEVEL_HIGH
                                     : drv_gpio_GpioLevel_GPIO_LEVEL_LOW;
}

static void set_result_ok(drv_gpio_GpioResult* r) {
    r->has_code = true;
    r->code = drv_gpio_GpioResultCode_GPIO_RES_OK;
}
static void set_result_fail(drv_gpio_GpioResult* r, int os_err) {
    r->has_code = true;
    r->code = drv_gpio_GpioResultCode_GPIO_RES_FAIL;
    r->has_os_errno = true;
    r->os_errno = os_err;
}

static int gpio_rpc_handler(uint16_t rpc_id,
                             const void* req_raw, void* resp_raw,
                             void* userdata) {
    const drv_gpio_GpioRpcRequest* req  = (const drv_gpio_GpioRpcRequest*)req_raw;
    drv_gpio_GpioRpcResponse*      resp = (drv_gpio_GpioRpcResponse*)resp_raw;

    resp->has_req_id = true;
    resp->req_id     = req->req_id;
    int ret = 0;

    switch (req->which_payload) {
    case drv_gpio_GpioRpcRequest_setup_tag: {
        const drv_gpio_GpioSetupRequest* s = &req->payload.setup;
        luat_gpio_cfg_t cfg = {0};
        luat_gpio_set_default_cfg(&cfg);
        cfg.pin  = (int)s->pin;
        cfg.mode = proto_mode_to_c(s->has_mode ? s->mode : drv_gpio_GpioMode_GPIO_MODE_INPUT);
        cfg.pull = proto_pull_to_c(s->has_pull ? s->pull : drv_gpio_GpioPull_GPIO_PULL_DEFAULT);
        if (cfg.mode == Luat_GPIO_OUTPUT) {
            cfg.output_level = proto_level_to_c(s->has_init_level ? s->init_level
                                                                   : drv_gpio_GpioLevel_GPIO_LEVEL_LOW);
        }
        if (cfg.mode == Luat_GPIO_IRQ && s->has_irq_type) {
            cfg.irq_type = proto_irq_to_c(s->irq_type);
        }
        ret = luat_gpio_open(&cfg);
        resp->which_payload = drv_gpio_GpioRpcResponse_setup_tag;
        if (ret == 0) set_result_ok(&resp->payload.setup.result);
        else          set_result_fail(&resp->payload.setup.result, ret);
        break;
    }
    case drv_gpio_GpioRpcRequest_close_tag: {
        luat_gpio_close((int)req->payload.close.pin);
        resp->which_payload = drv_gpio_GpioRpcResponse_close_tag;
        set_result_ok(&resp->payload.close.result);
        break;
    }
    case drv_gpio_GpioRpcRequest_write_tag: {
        const drv_gpio_GpioWriteRequest* w = &req->payload.write;
        ret = luat_gpio_set((int)w->pin, proto_level_to_c(w->level));
        resp->which_payload = drv_gpio_GpioRpcResponse_write_tag;
        if (ret == 0) set_result_ok(&resp->payload.write.result);
        else          set_result_fail(&resp->payload.write.result, ret);
        break;
    }
    case drv_gpio_GpioRpcRequest_read_tag: {
        int level = luat_gpio_get((int)req->payload.read.pin);
        resp->which_payload = drv_gpio_GpioRpcResponse_read_tag;
        if (level < 0) {
            set_result_fail(&resp->payload.read.result, level);
        } else {
            set_result_ok(&resp->payload.read.result);
            resp->payload.read.has_level = true;
            resp->payload.read.level     = c_level_to_proto(level);
        }
        break;
    }
    case drv_gpio_GpioRpcRequest_set_pull_tag: {
        const drv_gpio_GpioSetPullRequest* sp = &req->payload.set_pull;
        ret = luat_gpio_ctrl((int)sp->pin, LUAT_GPIO_CMD_SET_PULL_MODE,
                             proto_pull_to_c(sp->pull));
        resp->which_payload = drv_gpio_GpioRpcResponse_set_pull_tag;
        if (ret == 0) set_result_ok(&resp->payload.set_pull.result);
        else          set_result_fail(&resp->payload.set_pull.result, ret);
        break;
    }
    case drv_gpio_GpioRpcRequest_set_irq_tag: {
        const drv_gpio_GpioSetIrqRequest* si = &req->payload.set_irq;
        int irq_mode = proto_irq_to_c(si->has_irq_type ? si->irq_type
                                                        : drv_gpio_GpioIrqType_GPIO_IRQ_RISING);
        ret = luat_gpio_ctrl((int)si->pin, LUAT_GPIO_CMD_SET_IRQ_MODE, irq_mode);
        resp->which_payload = drv_gpio_GpioRpcResponse_set_irq_tag;
        if (ret == 0) set_result_ok(&resp->payload.set_irq.result);
        else          set_result_fail(&resp->payload.set_irq.result, ret);
        break;
    }
    default:
        LLOGW("gpio_rpc: 未知 which_payload=%d", (int)req->which_payload);
        return -1;
    }
    return 0;
}

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_gpio_reg = {
    .rpc_id         = AIRLINK_RPC_ID_GPIO,
    .active         = 1,
    .req_desc       = drv_gpio_GpioRpcRequest_fields,
    .req_size       = sizeof(drv_gpio_GpioRpcRequest),
    .resp_desc      = drv_gpio_GpioRpcResponse_fields,
    .resp_size      = sizeof(drv_gpio_GpioRpcResponse),
    .handler        = gpio_rpc_handler,
    .notify_handler = NULL,
    .userdata       = NULL,
};

#endif /* LUAT_USE_AIRLINK_RPC */
