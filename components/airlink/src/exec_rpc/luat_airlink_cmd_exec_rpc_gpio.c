/*
 * AirLink GPIO nanopb RPC exec handler (服务端)
 *
 * 将 GpioRpcRequest 分发到对应的 luat_gpio_* 函数，填写 GpioRpcResponse。
 * proto enum 值 = C 宏值 + 1（0 保留给 UNSPECIFIED），转换时减 1。
 *
 * IRQ 通路: 从机 ISR → queue → task → nanopb NOTIFY → 主机 dispatch → luat_gpio_irq_default
 */

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_EXEC_GPIO

#include "luat_airlink_rpc.h"
#include "luat_gpio.h"
#include "luat_rtos.h"
#include "luat_mcu.h"
#include "drv_gpio.pb.h"

#define LUAT_LOG_TAG "airlink.rpc.gpio"
#include "luat_log.h"

#define AIRLINK_RPC_ID_GPIO  0x0100

/* ------------------------------------------------------------------ */
/* 从机侧: IRQ 回调 → queue → task → NOTIFY                              */
/* ------------------------------------------------------------------ */

static luat_rtos_queue_t      rpc_gpio_irq_queue;
static luat_rtos_task_handle  rpc_gpio_irq_task_handle;

/* ISR 上下文: 读 pin 电平, 投递到队列 (不可在 ISR 中分配内存/发 NOTIFY) */
static int rpc_gpio_irq_cb(int pin, void* args) {
    luat_event_t event = {0};
    event.id     = 1;
    event.param1 = (uint32_t)pin;
    event.param2 = (uint32_t)luat_gpio_get(pin);
    luat_rtos_queue_send(rpc_gpio_irq_queue, &event, sizeof(event), 0);
    return 0;
}

/* 任务上下文: 从队列取出事件, 编码 GpioIrqEvent 并通过 NOTIFY 发给主机 */
__AIRLINK_CODE_IN_RAM__ static int rpc_gpio_irq_cb_task(void* param) {
    luat_event_t event = {0};
    luat_rtos_task_sleep(2);

    while (1) {
        event.id = 0;
        luat_rtos_queue_recv(rpc_gpio_irq_queue, &event, sizeof(event), LUAT_WAIT_FOREVER);
        if (event.id != 1) continue;

        int pin   = (int)event.param1;
        int level = (int)event.param2;

        // 构造 GpioRpcResponse { irq_event { pin, level, tick_ms } } 作为 NOTIFY
        drv_gpio_GpioRpcResponse msg = drv_gpio_GpioRpcResponse_init_zero;
        msg.req_id = 0;
        msg.which_payload = drv_gpio_GpioRpcResponse_irq_event_tag;
        msg.payload.irq_event.pin          = (uint32_t)(pin + 128); // 物理 pin → 虚拟 pin
        msg.payload.irq_event.has_level    = true;
        msg.payload.irq_event.level        = (level == 1) ? drv_gpio_GpioLevel_GPIO_LEVEL_HIGH
                                                          : drv_gpio_GpioLevel_GPIO_LEVEL_LOW;
        msg.payload.irq_event.has_tick_ms  = true;
        msg.payload.irq_event.tick_ms      = luat_mcu_tick64_ms();

        LLOGW("rpc gpio irq notify pin=%d level=%d", pin, level);

        int mode = luat_airlink_current_mode_get();
        luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_RPC_ID_GPIO,
                                   drv_gpio_GpioRpcResponse_fields, &msg);
    }
    return 0;
}

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
        if (cfg.pin >= 128) cfg.pin -= 128;
        cfg.mode = proto_mode_to_c(s->has_mode ? s->mode : drv_gpio_GpioMode_GPIO_MODE_INPUT);
        cfg.pull = proto_pull_to_c(s->has_pull ? s->pull : drv_gpio_GpioPull_GPIO_PULL_DEFAULT);
        if (cfg.mode == Luat_GPIO_OUTPUT) {
            cfg.output_level = proto_level_to_c(s->has_init_level ? s->init_level
                                                                   : drv_gpio_GpioLevel_GPIO_LEVEL_LOW);
        }
        if (cfg.mode == Luat_GPIO_IRQ && s->has_irq_type) {
            cfg.irq_type = proto_irq_to_c(s->irq_type);
        }
        if (cfg.mode == Luat_GPIO_IRQ) {
            // 创建 IRQ 基础设施 (首次, 仅从机侧生效)
            if (rpc_gpio_irq_queue == NULL) {
                luat_rtos_queue_create(&rpc_gpio_irq_queue, 1 * 1024, sizeof(luat_event_t));
            }
            if (rpc_gpio_irq_task_handle == NULL) {
                luat_rtos_task_create(&rpc_gpio_irq_task_handle, 1 * 1024, 55, "airlink",
                                      rpc_gpio_irq_cb_task, NULL, 1024);
            }
            cfg.irq_cb   = rpc_gpio_irq_cb;
            cfg.irq_args = NULL;
        }
        ret = luat_gpio_open(&cfg);
        LLOGW("gpio setup pin=%d mode=%d pull=%d irq_type=%d ret=%d", cfg.pin, cfg.mode, cfg.pull, cfg.irq_type, ret);
        resp->which_payload = drv_gpio_GpioRpcResponse_setup_tag;
        if (ret == 0) set_result_ok(&resp->payload.setup.result);
        else          set_result_fail(&resp->payload.setup.result, ret);
        break;
    }
    case drv_gpio_GpioRpcRequest_close_tag: {
        int pin = (int)req->payload.close.pin;
        if (pin >= 128) pin -= 128;
        luat_gpio_close(pin);
        resp->which_payload = drv_gpio_GpioRpcResponse_close_tag;
        set_result_ok(&resp->payload.close.result);
        break;
    }
    case drv_gpio_GpioRpcRequest_write_tag: {
        const drv_gpio_GpioWriteRequest* w = &req->payload.write;
        int pin = (int)w->pin;
        if (pin >= 128) pin -= 128;
        ret = luat_gpio_set(pin, proto_level_to_c(w->level));
        resp->which_payload = drv_gpio_GpioRpcResponse_write_tag;
        if (ret == 0) set_result_ok(&resp->payload.write.result);
        else          set_result_fail(&resp->payload.write.result, ret);
        break;
    }
    case drv_gpio_GpioRpcRequest_read_tag: {
        int pin = (int)req->payload.read.pin;
        if (pin >= 128) pin -= 128;
        int level = luat_gpio_get(pin);
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
        int pin = (int)sp->pin;
        if (pin >= 128) pin -= 128;
        ret = luat_gpio_ctrl(pin, LUAT_GPIO_CMD_SET_PULL_MODE,
                             proto_pull_to_c(sp->pull));
        resp->which_payload = drv_gpio_GpioRpcResponse_set_pull_tag;
        if (ret == 0) set_result_ok(&resp->payload.set_pull.result);
        else          set_result_fail(&resp->payload.set_pull.result, ret);
        break;
    }
    case drv_gpio_GpioRpcRequest_set_irq_tag: {
        const drv_gpio_GpioSetIrqRequest* si = &req->payload.set_irq;
        int pin = (int)si->pin;
        if (pin >= 128) pin -= 128;
        int irq_mode = proto_irq_to_c(si->has_irq_type ? si->irq_type
                                                        : drv_gpio_GpioIrqType_GPIO_IRQ_RISING);
        ret = luat_gpio_ctrl(pin, LUAT_GPIO_CMD_SET_IRQ_MODE, irq_mode);
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

// NOTIFY 处理: 对端上报的 GPIO IRQ 事件 → 调用 luat_gpio_irq_default 触发 Lua 回调
static void gpio_rpc_notify_handler(uint16_t rpc_id, const void* msg, void* userdata) {
    const drv_gpio_GpioRpcResponse* resp = (const drv_gpio_GpioRpcResponse*)msg;
    if (resp->which_payload == drv_gpio_GpioRpcResponse_irq_event_tag) {
        int pin = (int)resp->payload.irq_event.pin;
        // proto level: GPIO_LEVEL_LOW=1, GPIO_LEVEL_HIGH=2 → C level: 0/1
        int level = (resp->payload.irq_event.level == drv_gpio_GpioLevel_GPIO_LEVEL_HIGH) ? 1 : 0;
        LLOGW("irq notify pin=%d level=%d", pin, level);
        luat_gpio_irq_default(pin, (void*)(intptr_t)level);
    }
}

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_gpio_reg = {
    .rpc_id         = AIRLINK_RPC_ID_GPIO,
    .active         = 1,
    .req_desc       = drv_gpio_GpioRpcRequest_fields,
    .req_size       = sizeof(drv_gpio_GpioRpcRequest),
    .resp_desc      = drv_gpio_GpioRpcResponse_fields,
    .resp_size      = sizeof(drv_gpio_GpioRpcResponse),
    .notify_desc    = drv_gpio_GpioRpcResponse_fields,
    .notify_size    = sizeof(drv_gpio_GpioRpcResponse),
    .handler        = gpio_rpc_handler,
    .notify_handler = gpio_rpc_notify_handler,
    .userdata       = NULL,
};

#endif /* LUAT_USE_AIRLINK_EXEC_GPIO */
