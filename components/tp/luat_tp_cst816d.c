#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp_reg.h"

#define LUAT_LOG_TAG "cst816d"
#include "luat_log.h"

/* I2C address (main operating mode) */
#define CST816D_ADDRESS     (0x15)

/* Register addresses */
#define CST816D_REG_DATA    (0x00)  /* 1-byte addr; returns 3 hdr + N*6 point bytes */
#define CST816D_REG_INFO    (0xAA)  /* chip_type(B0), project_id(B1), fw_ver(B2), rsv(B3) */
#define CST816D_REG_SLEEP   (0xE503)/* 2-byte addr; write-only deep-sleep command */

/* Data layout inside CST816D_REG_DATA response */
#define CST816D_HDR_BYTES   (3)     /* 3 header bytes before point records */
#define CST816D_PT_BYTES    (6)     /* bytes per touch-point record */
#define CST816D_TOUCH_MAX   (2)     /* max simultaneous contacts reported */
#define CST816D_READ_LEN    (CST816D_HDR_BYTES + CST816D_PT_BYTES * CST816D_TOUCH_MAX)

/*
 * Touch-point record layout (relative to start of record):
 *   byte 0 : [7]reserved [6:5]event (0=down, 1=lift) [4]reserved [3:0]x_high
 *   byte 1 : x_low
 *   byte 2 : [7:4]finger_id  [3:0]y_high
 *   byte 3 : y_low
 *   byte 4-5: pressure / reserved (unused)
 */

static uint8_t cst816d_init_state = 0;

/* Per-finger tracking state */
static int16_t pre_x[CST816D_TOUCH_MAX];
static int16_t pre_y[CST816D_TOUCH_MAX];
static int16_t pre_w[CST816D_TOUCH_MAX];
static uint8_t s_tp_down[CST816D_TOUCH_MAX];

static uint8_t read_buff[CST816D_READ_LEN];

static int luat_tp_irq_cb(int pin, void *args) {
    if (cst816d_init_state == 0)
        return -1;
    luat_tp_config_t *cfg = (luat_tp_config_t *)args;
    luat_tp_irq_enable(cfg, 0);
    luat_rtos_message_send(cfg->task_handle, 1, args);
    return 0;
}

static void cst816d_touch_up(luat_tp_data_t *data, int8_t id) {
    if (s_tp_down[id]) {
        s_tp_down[id] = 0;
        data[id].event = TP_EVENT_TYPE_UP;
    } else {
        data[id].event = TP_EVENT_TYPE_NONE;
    }
    data[id].timestamp    = luat_mcu_ticks();
    data[id].width        = pre_w[id];
    data[id].x_coordinate = pre_x[id];
    data[id].y_coordinate = pre_y[id];
    data[id].track_id     = id;
    pre_x[id] = -1;
    pre_y[id] = -1;
    pre_w[id] = -1;
}

static void cst816d_touch_down(luat_tp_data_t *data, int8_t id, int16_t x, int16_t y) {
    data[id].event = s_tp_down[id] ? TP_EVENT_TYPE_MOVE : TP_EVENT_TYPE_DOWN;
    s_tp_down[id]         = 1;
    data[id].timestamp    = luat_mcu_ticks();
    data[id].width        = 0;
    data[id].x_coordinate = x;
    data[id].y_coordinate = y;
    data[id].track_id     = id;
    pre_x[id] = x;
    pre_y[id] = y;
    pre_w[id] = 0;
}

/* Parse point-data bytes (starting after the 3-byte header).
 *
 * CST816D reports UP by setting event_flag=1 in the per-point byte while
 * touch_num may still be >0.  We MUST check event_flag for each point;
 * relying on touch_num alone misses the UP and leaves the state machine stuck,
 * causing continuous MOVE events after release.
 */
static void cst816d_read_point(uint8_t *input_buff, luat_tp_data_t *buf, uint8_t touch_num) {
    uint8_t i;
    uint8_t cur_id_mask = 0;  /* bitmask of finger IDs seen this frame (for fallback UP) */

    if (touch_num == 0) {
        /* No contacts reported — generate UP or NONE for every finger slot.
         * Calling unconditionally ensures stale UP events are overwritten with
         * NONE on the following frame, preventing continuous UP callbacks. */
        for (i = 0; i < CST816D_TOUCH_MAX; i++)
            cst816d_touch_up(buf, (int8_t)i);
        return;
    }

    for (i = 0; i < touch_num; i++) {
        uint8_t *p = input_buff + i * CST816D_PT_BYTES;
        uint8_t event_flag = (p[0] >> 6) & 0x03; /* 0=down/move, 1=lift */
        int8_t  read_id    = (p[2] >> 4) & 0x0F;
        int16_t input_x    = ((uint16_t)(p[0] & 0x0F) << 8) | p[1];
        int16_t input_y    = ((uint16_t)(p[2] & 0x0F) << 8) | p[3];

        if (read_id >= CST816D_TOUCH_MAX) {
            LLOGE("touch ID %d out of range", read_id);
            continue;
        }
        cur_id_mask |= (uint8_t)(1u << read_id);

        if (event_flag == 1) {
            /* Hardware-reported lift */
            cst816d_touch_up(buf, read_id);
        } else {
            /* Active contact: DOWN on first contact, MOVE if already down */
            cst816d_touch_down(buf, read_id, input_x, input_y);
        }
    }

    /* Fallback: generate UP/NONE for any finger absent from this frame */
    for (i = 0; i < CST816D_TOUCH_MAX; i++) {
        if (!(cur_id_mask & (1u << i)))
            cst816d_touch_up(buf, (int8_t)i);
    }
}

static int tp_cst816d_read(luat_tp_config_t *cfg, luat_tp_data_t *tp_data) {
    uint8_t touch_num = 0;
    memset(read_buff, 0, sizeof(read_buff));
    tp_i2c_read_reg8(cfg, CST816D_REG_DATA, read_buff, sizeof(read_buff), 0);

    touch_num = read_buff[2];
    if (touch_num > CST816D_TOUCH_MAX)
        touch_num = 0;

    cst816d_read_point(read_buff + CST816D_HDR_BYTES, tp_data, touch_num);
    return touch_num;
}

static void tp_cst816d_read_done(luat_tp_config_t *cfg) {
    luat_tp_irq_enable(cfg, 1);
}

static int tp_cst816d_sleep(luat_tp_config_t *cfg) {
    /* Deep-sleep command: write 2-byte register address 0xE5 0x03, no data */
    return tp_i2c_write_reg16(cfg, CST816D_REG_SLEEP, NULL, 0);
}

static int tp_cst816d_hw_reset(luat_tp_config_t *cfg) {
    if (cfg->pin_rst != LUAT_GPIO_NONE) {
        luat_gpio_set(cfg->pin_rst, Luat_GPIO_LOW);
        luat_rtos_task_sleep(11);
        luat_gpio_set(cfg->pin_rst, Luat_GPIO_HIGH);
    }
    return 0;
}

static int tp_cst816d_init(luat_tp_config_t *cfg) {
    uint8_t buf[4] = {0};
    cfg->address = CST816D_ADDRESS;

    /* Reset per-finger state — static arrays persist across Lua re-starts */
    memset(s_tp_down, 0, sizeof(s_tp_down));
    memset(pre_x, 0xFF, sizeof(pre_x));  /* 0xFFFF = -1 sentinel */
    memset(pre_y, 0xFF, sizeof(pre_y));
    memset(pre_w, 0xFF, sizeof(pre_w));

    /* Configure RST and INT as outputs, both high */
    luat_gpio_mode(cfg->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
    luat_gpio_mode(cfg->pin_int, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
    luat_gpio_set(cfg->pin_rst, Luat_GPIO_HIGH);
    luat_gpio_set(cfg->pin_int, Luat_GPIO_HIGH);

    /* Hardware reset then wait for firmware boot */
    tp_cst816d_hw_reset(cfg);
    luat_rtos_task_sleep(50);

    /* Read chip information (chip_type, project_id, fw_ver) */
    if (tp_i2c_read_reg8(cfg, CST816D_REG_INFO, buf, 4, 0)) {
        LLOGE("read chip info failed (I2C NAK)");
        return -1;
    }
    LLOGI("CST816D chip_type=0x%02X project_id=0x%02X fw_ver=0x%02X",
          buf[0], buf[1], buf[2]);

    /* Configure INT as falling-edge interrupt */
    cfg->int_type = Luat_GPIO_FALLING;
    luat_gpio_t gpio = {0};
    gpio.pin      = cfg->pin_int;
    gpio.mode     = Luat_GPIO_IRQ;
    gpio.pull     = Luat_GPIO_PULLUP;
    gpio.irq      = cfg->int_type;
    gpio.irq_cb   = luat_tp_irq_cb;
    gpio.irq_args = cfg;
    luat_gpio_setup(&gpio);

    cst816d_init_state = 1;
    return 0;
}

static int tp_cst816d_deinit(luat_tp_config_t *cfg) {
    cst816d_init_state = 0;
    if (cfg->pin_int != LUAT_GPIO_NONE)
        luat_gpio_close(cfg->pin_int);
    if (cfg->pin_rst != LUAT_GPIO_NONE)
        luat_gpio_close(cfg->pin_rst);
    return 0;
}

luat_tp_opts_t tp_config_cst816d = {
    .name      = "cst816d",
    .init      = tp_cst816d_init,
    .deinit    = tp_cst816d_deinit,
    .read      = tp_cst816d_read,
    .read_done = tp_cst816d_read_done,
    .sleep     = tp_cst816d_sleep,
};
