#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && defined(LUAT_USE_DRV_GPIO)

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "drv_gpio.pb.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

#define AIRLINK_DRV_RPC_ID_GPIO  0x0100

static inline drv_gpio_GpioMode c_mode_to_proto(int m) {
    return (drv_gpio_GpioMode)(m + 1);
}
static inline drv_gpio_GpioPull c_pull_to_proto(int p) {
    return (drv_gpio_GpioPull)(p + 1);
}
static inline drv_gpio_GpioLevel c_level_to_proto(int l) {
    return (l == Luat_GPIO_HIGH) ? drv_gpio_GpioLevel_GPIO_LEVEL_HIGH
                                 : drv_gpio_GpioLevel_GPIO_LEVEL_LOW;
}
static inline drv_gpio_GpioIrqType c_irq_to_proto(int t) {
    return (drv_gpio_GpioIrqType)(t + 1);
}

static void gpio_t_to_setup_req(const luat_gpio_t* gpio, drv_gpio_GpioSetupRequest* out) {
    memset(out, 0, sizeof(*out));
    int pin = gpio->pin;
    if (pin >= 128) pin -= 128;
    out->pin      = (uint32_t)pin;
    out->has_mode = true;
    out->mode     = c_mode_to_proto(gpio->mode);
    out->has_pull = true;
    out->pull     = c_pull_to_proto(gpio->pull);
    if (gpio->mode == Luat_GPIO_IRQ) {
        out->has_irq_type   = true;
        out->irq_type       = c_irq_to_proto(gpio->irq);
        out->has_irq_enable = true;
        out->irq_enable     = true;
    }
}

static void gpio_cfg_to_setup_req(const luat_gpio_cfg_t* cfg, drv_gpio_GpioSetupRequest* out) {
    memset(out, 0, sizeof(*out));
    int pin = cfg->pin;
    if (pin >= 128) pin -= 128;
    out->pin      = (uint32_t)pin;
    out->has_mode = true;
    out->mode     = c_mode_to_proto(cfg->mode);
    out->has_pull = true;
    out->pull     = c_pull_to_proto(cfg->pull);
    if (cfg->mode == Luat_GPIO_OUTPUT) {
        out->has_init_level = true;
        out->init_level     = c_level_to_proto(cfg->output_level);
    }
    if (cfg->mode == Luat_GPIO_IRQ) {
        out->has_irq_type   = true;
        out->irq_type       = c_irq_to_proto(cfg->irq_type);
        out->has_irq_enable = true;
        out->irq_enable     = true;
    }
}

int luat_airlink_drv_rpc_gpio_setup(luat_gpio_t* gpio) {
    int mode = luat_airlink_current_mode_get();
    drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
    drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
    req.which_payload = drv_gpio_GpioRpcRequest_setup_tag;
    gpio_t_to_setup_req(gpio, &req.payload.setup);
    int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_GPIO,
                                       drv_gpio_GpioRpcRequest_fields,  &req,
                                       drv_gpio_GpioRpcResponse_fields, &resp,
                                       1000);
    if (rc != 0) return rc;
    if (resp.which_payload != drv_gpio_GpioRpcResponse_setup_tag) return -10;
    if (resp.payload.setup.result.has_code &&
        resp.payload.setup.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
        return (int)resp.payload.setup.result.code;
    }
    return 0;
}

int luat_airlink_drv_rpc_gpio_open(luat_gpio_cfg_t* gpio) {
    int mode = luat_airlink_current_mode_get();
    drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
    drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
    req.which_payload = drv_gpio_GpioRpcRequest_setup_tag;
    gpio_cfg_to_setup_req(gpio, &req.payload.setup);
    int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_GPIO,
                                       drv_gpio_GpioRpcRequest_fields,  &req,
                                       drv_gpio_GpioRpcResponse_fields, &resp,
                                       1000);
    if (rc != 0) return rc;
    if (resp.which_payload != drv_gpio_GpioRpcResponse_setup_tag) return -10;
    if (resp.payload.setup.result.has_code &&
        resp.payload.setup.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
        return (int)resp.payload.setup.result.code;
    }
    return 0;
}

int luat_airlink_drv_rpc_gpio_set(int pin, int level) {
    if (pin >= 128) pin -= 128;
    int mode = luat_airlink_current_mode_get();
    drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
    drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
    req.which_payload       = drv_gpio_GpioRpcRequest_write_tag;
    req.payload.write.pin   = (uint32_t)pin;
    req.payload.write.level = c_level_to_proto(level);
    int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_GPIO,
                                       drv_gpio_GpioRpcRequest_fields,  &req,
                                       drv_gpio_GpioRpcResponse_fields, &resp,
                                       1000);
    if (rc != 0) return rc;
    if (resp.which_payload != drv_gpio_GpioRpcResponse_write_tag) return -10;
    if (resp.payload.write.result.has_code &&
        resp.payload.write.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
        return (int)resp.payload.write.result.code;
    }
    return 0;
}

int luat_airlink_drv_rpc_gpio_get(int pin, int* val) {
    /* Remap pin to 0-based physical range (same as raw path) */
    if (pin >= 128) pin -= 128;
    if (pin >= 64) {
        LLOGE("invalid pin %d", pin + 128);
        *val = 0;
        return 0;
    }
    int mode = luat_airlink_current_mode_get();
    drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
    drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
    req.which_payload    = drv_gpio_GpioRpcRequest_read_tag;
    req.payload.read.pin = (uint32_t)pin;
    int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_GPIO,
                                       drv_gpio_GpioRpcRequest_fields,  &req,
                                       drv_gpio_GpioRpcResponse_fields, &resp,
                                       1000);
    if (rc != 0) {
        LLOGW("gpio.get rpc failed pin %d rc %d", pin, rc);
        *val = 0;
        return rc;
    }
    if (resp.which_payload != drv_gpio_GpioRpcResponse_read_tag) {
        *val = 0;
        return -10;
    }
    if (resp.payload.read.result.has_code &&
        resp.payload.read.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
        *val = 0;
        return (int)resp.payload.read.result.code;
    }
    *val = resp.payload.read.has_level
         ? (resp.payload.read.level == drv_gpio_GpioLevel_GPIO_LEVEL_HIGH ? 1 : 0)
         : 0;
    return 0;
}

#endif /* LUAT_USE_AIRLINK_RPC_GPIO */
