#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_airlink_rpc.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_mem.h"

#include "drv_gpio.pb.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

// RPC id shared with exec handler and lib binding
#define AIRLINK_DRV_RPC_ID_GPIO  0x0100

// C (0-based) → proto enum (1-based), 0 maps to UNSPECIFIED
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

// Build a GpioSetupRequest from old luat_gpio_t (legacy API)
static void gpio_t_to_setup_req(const luat_gpio_t* gpio, drv_gpio_GpioSetupRequest* out) {
    memset(out, 0, sizeof(*out));
    out->pin      = (uint32_t)gpio->pin;
    out->has_mode = true;
    out->mode     = c_mode_to_proto(gpio->mode);
    out->has_pull = true;
    out->pull     = c_pull_to_proto(gpio->pull);
    if (gpio->mode == Luat_GPIO_IRQ) {
        out->has_irq_type = true;
        out->irq_type     = c_irq_to_proto(gpio->irq);
        out->has_irq_enable = true;
        out->irq_enable     = true;
    }
}

// Build a GpioSetupRequest from new luat_gpio_cfg_t
static void gpio_cfg_to_setup_req(const luat_gpio_cfg_t* cfg, drv_gpio_GpioSetupRequest* out) {
    memset(out, 0, sizeof(*out));
    out->pin      = (uint32_t)cfg->pin;
    out->has_mode = true;
    out->mode     = c_mode_to_proto(cfg->mode);
    out->has_pull = true;
    out->pull     = c_pull_to_proto(cfg->pull);
    if (cfg->mode == Luat_GPIO_OUTPUT) {
        out->has_init_level = true;
        out->init_level     = c_level_to_proto(cfg->output_level);
    }
    if (cfg->mode == Luat_GPIO_IRQ) {
        out->has_irq_type = true;
        out->irq_type     = c_irq_to_proto(cfg->irq_type);
        out->has_irq_enable = true;
        out->irq_enable     = true;
    }
}

int luat_airlink_drv_gpio_setup(luat_gpio_t* gpio) {
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_gpio_GpioRpcRequest req = drv_gpio_GpioRpcRequest_init_zero;
        req.which_payload = drv_gpio_GpioRpcRequest_setup_tag;
        gpio_t_to_setup_req(gpio, &req.payload.setup);
        // fire-and-forget NOTIFY: preserves non-blocking raw-path semantics
        return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_GPIO,
                                          drv_gpio_GpioRpcRequest_fields, &req);
    }
    // --- raw byte path (original) ---
    // LLOGD("执行GPIO配置指令!!! pin %d mode %d pull %d", gpio->pin, gpio->mode, gpio->pull);
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_gpio_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x300, sizeof(luat_gpio_t) + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, gpio, sizeof(luat_gpio_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_gpio_open(luat_gpio_cfg_t* gpio) {
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
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
    // raw byte path: new API → falls back to luat_airlink_drv_gpio_setup via legacy struct
    luat_gpio_t legacy = {0};
    legacy.pin  = gpio->pin;
    legacy.mode = gpio->mode;
    legacy.pull = gpio->pull;
    legacy.irq  = gpio->irq_type;
    return luat_airlink_drv_gpio_setup(&legacy);
}

int luat_airlink_drv_gpio_set(int pin, int level) {
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_gpio_GpioRpcRequest req = drv_gpio_GpioRpcRequest_init_zero;
        req.which_payload         = drv_gpio_GpioRpcRequest_write_tag;
        req.payload.write.pin     = (uint32_t)pin;
        req.payload.write.level   = c_level_to_proto(level);
        // fire-and-forget NOTIFY: preserves non-blocking raw-path semantics
        return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_GPIO,
                                          drv_gpio_GpioRpcRequest_fields, &req);
    }
    // --- raw byte path (original) ---
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 2 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x301, 2 + 8) ;
    if (cmd == NULL) { 
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = (uint8_t)pin;
    data[1] = (uint8_t)level;
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

luat_rtos_semaphore_t g_drv_gpio_sem;
uint64_t g_drv_gpio_input_level = 0;
int luat_airlink_drv_gpio_get(int pin, int* val) {
    int ret = 0;
    if (pin >= 128) {
        pin -= 128;
    }
    if (pin >= 64) {
        LLOGE("invaild pin %d/%d", pin, pin + 128);
        *val = 0;
        return 0;
    }

    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
        drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
        req.which_payload      = drv_gpio_GpioRpcRequest_read_tag;
        req.payload.read.pin   = (uint32_t)pin;
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

    // --- raw byte path (original) ---
    uint32_t version;
    memcpy(&version, &g_airlink_ext_dev_info.wifi.version, 4);
    if (version < 9) {
        LLOGE("wifi version < 9, not support gpio.get");
        *val = 0;
        return 0;
    }
    uint64_t seq_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x302, 1 + 8) ;
    if (cmd == NULL) {
        LLOGE("out of memory when gpio.get");
        return 0;
    }
    if (g_drv_gpio_sem == NULL) {
        luat_rtos_semaphore_create(&g_drv_gpio_sem, 0);
        luat_rtos_semaphore_take(g_drv_gpio_sem, 100);
    }
    memcpy(cmd->data, &seq_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = (uint8_t)pin;
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    // LLOGI("g_drv_gpio_sem take");
    ret = luat_rtos_semaphore_take(g_drv_gpio_sem, 100);
    // LLOGI("g_drv_gpio_sem take %d", ret);
    uint64_t tmp = pin;
    LLOGD("g_drv_gpio_input_level %d %08X", pin, g_drv_gpio_input_level);
    LLOGD("g_drv_gpio_input_level %d is %d", pin, (g_drv_gpio_input_level >> tmp) & 1);
    *val = (g_drv_gpio_input_level >> tmp) & 1;
    if (ret) {
        LLOGW("gpio.get timeout!! pin %d", pin);
    }
    return ret;
}

int luat_airlink_drv_gpio_driver_yhm27xx(uint32_t Pin, uint8_t ChipID, uint8_t RegAddress, uint8_t IsRead, uint8_t *Data) 
{
    uint8_t Pin_id = Pin;
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x304, 5 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = Pin_id;
    data[1] = ChipID;
    data[2] = RegAddress;
    data[3] = IsRead;
    data[4] = *Data;

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_gpio_driver_yhm27xx_reqinfo(uint8_t Pin, uint8_t ChipID)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 2 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x305, 2 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = Pin;
    data[1] = ChipID;

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

