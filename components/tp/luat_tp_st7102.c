#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp_reg.h"

#define LUAT_LOG_TAG "st7102"
#include "luat_log.h"

/* I2C address (7-bit), touch side of the ST7102 TDDI */
#define ST7102_ADDRESS              (0x55)
#define ST7102_CHIP_ID_CODE         (0x83)

/* Register addresses (16-bit) */
#define ST7102_REG_FW_VERSION       (0x0000)
#define ST7102_REG_STATUS           (0x0001)
#define ST7102_REG_DEVICE_CONTROL   (0x0002)
#define ST7102_REG_X_RESOLUTION     (0x0005)
#define ST7102_REG_MAX_TOUCHES      (0x0009)
#define ST7102_REG_FW_REVISION      (0x000C)
#define ST7102_REG_TOUCH_INFO       (0x0010)
#define ST7102_REG_CHIP_ID          (0x00F4)

/* Status register 0x0001, low nibble is device status, 0 means normal */
#define ST7102_STATUS_MASK          (0x0F)
#define ST7102_STATUS_NORMAL        (0x00)

/* Device control register 0x0002, bit0 power reset, bit1 power down, bit2 proximity enable */
#define ST7102_CTRL_POWER_DOWN      (0x02)

/* Touch frame read from ST7102_REG_TOUCH_INFO */
#define ST7102_INFO_BYTES           (4)
#define ST7102_POINT_BYTES          (7)
#define ST7102_CKSUM_BYTES          (1)
#define ST7102_READ_LEN(touches)    (ST7102_INFO_BYTES + ST7102_POINT_BYTES * (touches) + ST7102_CKSUM_BYTES)
#define ST7102_READ_LEN_MAX         (ST7102_READ_LEN(LUAT_TP_TOUCH_MAX))

/* Advanced touch info 0x0010 */
#define ST7102_INFO_RST_CHIP        (0x80)

/* Point record, 7 bytes each from 0x0014 */
#define ST7102_POINT_VALID          (0x80)
#define ST7102_POINT_XY_HIGH        (0x3F)

/* Resolution registers hold 14-bit values */
#define ST7102_RES_HIGH_MASK        (0x3F)

/* Timing */
#define ST7102_RESET_LOW_MS         (10)
#define ST7102_RESET_WAIT_MS        (200)
#define ST7102_STATUS_RETRY         (20)
#define ST7102_STATUS_RETRY_MS      (5)

/*
 * Point record layout (offset from the start of the record):
 *   byte 0 : [7]valid [6]reserved [5:0]x[13:8]
 *   byte 1 : x[7:0]
 *   byte 2 : [7:6]reserved [5:0]y[13:8]
 *   byte 3 : y[7:0]
 *   byte 4 : touch area
 *   byte 5 : touch intensity
 *   byte 6 : reserved
 */

static uint8_t st7102_init_state = 0;
static uint8_t st7102_max_touches = LUAT_TP_TOUCH_MAX;

/* Per-finger tracking state */
static int16_t pre_x[LUAT_TP_TOUCH_MAX];
static int16_t pre_y[LUAT_TP_TOUCH_MAX];
static int16_t pre_w[LUAT_TP_TOUCH_MAX];
static uint8_t s_tp_down[LUAT_TP_TOUCH_MAX];

static uint8_t read_buff[ST7102_READ_LEN_MAX];

static int luat_tp_irq_cb(int pin, void *args) {
    if (st7102_init_state == 0)
        return -1;
    luat_tp_config_t *cfg = (luat_tp_config_t *)args;
    luat_tp_irq_enable(cfg, 0);
    luat_rtos_message_send(cfg->task_handle, 1, args);
    return 0;
}

static void st7102_touch_up(luat_tp_data_t *data, int8_t id) {
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

static void st7102_touch_down(luat_tp_data_t *data, int8_t id, int16_t x, int16_t y, int16_t w) {
    data[id].event = s_tp_down[id] ? TP_EVENT_TYPE_MOVE : TP_EVENT_TYPE_DOWN;
    s_tp_down[id]         = 1;
    data[id].timestamp    = luat_mcu_ticks();
    data[id].width        = w;
    data[id].x_coordinate = x;
    data[id].y_coordinate = y;
    data[id].track_id     = id;
    pre_x[id] = x;
    pre_y[id] = y;
    pre_w[id] = w;
}

static void st7102_reset_state(void) {
    uint8_t i;
    memset(s_tp_down, 0, sizeof(s_tp_down));
    for (i = 0; i < LUAT_TP_TOUCH_MAX; i++) {
        pre_x[i] = -1;
        pre_y[i] = -1;
        pre_w[i] = -1;
    }
}

static void st7102_all_up(luat_tp_data_t *data) {
    uint8_t i;
    for (i = 0; i < LUAT_TP_TOUCH_MAX; i++)
        st7102_touch_up(data, (int8_t)i);
}

static int st7102_hw_reset(luat_tp_config_t *cfg) {
    if (cfg->pin_rst == LUAT_GPIO_NONE)
        return 0;
    luat_gpio_set(cfg->pin_rst, Luat_GPIO_LOW);
    luat_rtos_task_sleep(ST7102_RESET_LOW_MS);
    luat_gpio_set(cfg->pin_rst, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(ST7102_RESET_WAIT_MS);
    return 0;
}

/*
 * 读寄存器：寄存器地址 2 字节大端，地址写完后用重复起始读数据。
 * 硬件 I2C 走 luat_i2c_transfer 一次传输完成；
 * 软件 I2C 走 i2c_soft_send 不发停止位，再 i2c_soft_recv。
 */
static int st7102_read_reg(luat_tp_config_t *cfg, uint16_t reg, uint8_t *buff, size_t len) {
    uint8_t addr[2];
    int ret;

    addr[0] = (uint8_t)(reg >> 8);
    addr[1] = (uint8_t)(reg & 0xff);

    if (cfg->soft_i2c != NULL) {
        i2c_soft_send(cfg->soft_i2c, cfg->address, (char *)addr, sizeof(addr), 0);
        ret = i2c_soft_recv(cfg->soft_i2c, cfg->address, (char *)buff, len);
    } else {
        ret = luat_i2c_transfer(cfg->i2c_id, cfg->address, addr, sizeof(addr), buff, len);
    }
    if (ret < 0) {
        LLOGE("read 0x%04X failed %d", reg, ret);
        return -1;
    }
    return 0;
}

static int st7102_write_reg(luat_tp_config_t *cfg, uint16_t reg, uint8_t *buff, size_t len) {
    if (tp_i2c_write_reg16(cfg, reg, buff, len) < 0) {
        LLOGE("write 0x%04X failed", reg);
        return -1;
    }
    return 0;
}

/* Device control register is read-modify-write, only bit0/bit1/bit2 are defined */
static int st7102_ctrl_update(luat_tp_config_t *cfg, uint8_t mask, uint8_t value) {
    uint8_t ctrl = 0;
    if (st7102_read_reg(cfg, ST7102_REG_DEVICE_CONTROL, &ctrl, 1))
        return -1;
    ctrl = (uint8_t)((ctrl & (uint8_t)~mask) | (value & mask));
    return st7102_write_reg(cfg, ST7102_REG_DEVICE_CONTROL, &ctrl, 1);
}

static int st7102_wait_normal(luat_tp_config_t *cfg) {
    uint8_t status = 0;
    uint8_t retry;

    for (retry = 0; retry < ST7102_STATUS_RETRY; retry++) {
        if (st7102_read_reg(cfg, ST7102_REG_STATUS, &status, 1) == 0) {
            if ((status & ST7102_STATUS_MASK) == ST7102_STATUS_NORMAL)
                return 0;
        }
        luat_rtos_task_sleep(ST7102_STATUS_RETRY_MS);
    }
    LLOGW("device status 0x%02X not normal, keep going", status);
    return 0;
}

/* Parse the point records starting at 0x0014, returns the current contact count */
static uint8_t st7102_read_point(uint8_t *input_buff, luat_tp_data_t *buf) {
    uint8_t i;
    uint8_t touch_count = 0;
    uint8_t *p = input_buff;
    for (i = 0; i < st7102_max_touches; i++) {
        if (*p & ST7102_POINT_VALID) {
            int16_t x = (int16_t)((((uint16_t)(p[0] & ST7102_POINT_XY_HIGH)) << 8) | p[1]);
            int16_t y = (int16_t)((((uint16_t)(p[2] & ST7102_POINT_XY_HIGH)) << 8) | p[3]);
            st7102_touch_down(buf, (int8_t)i, x, y, (int16_t)p[4]);
            touch_count++;
        } else {
            st7102_touch_up(buf, (int8_t)i);
        }
        p += ST7102_POINT_BYTES;
    }
    return touch_count;
}

static int tp_st7102_read(luat_tp_config_t *cfg, luat_tp_data_t *tp_data) {
    uint8_t read_len = ST7102_READ_LEN(st7102_max_touches);
    memset(read_buff, 0, sizeof(read_buff));

    if (st7102_read_reg(cfg, ST7102_REG_TOUCH_INFO, read_buff, read_len))
        return -1;

    if (read_buff[0] & ST7102_INFO_RST_CHIP) {
        /* Firmware requested a chip reset, drop every contact then restart it */
        st7102_all_up(tp_data);
        st7102_hw_reset(cfg);
        return 0;
    }

    return st7102_read_point(read_buff + ST7102_INFO_BYTES, tp_data);
}

static void tp_st7102_read_done(luat_tp_config_t *cfg) {
    luat_tp_irq_enable(cfg, 1);
}

static int tp_st7102_sleep(luat_tp_config_t *cfg) {
    if (st7102_ctrl_update(cfg, ST7102_CTRL_POWER_DOWN, ST7102_CTRL_POWER_DOWN))
        return -1;
    luat_tp_irq_enable(cfg, 0);
    return 0;
}

static int tp_st7102_wakeup(luat_tp_config_t *cfg) {
    if (st7102_ctrl_update(cfg, ST7102_CTRL_POWER_DOWN, 0))
        return -1;
    luat_rtos_task_sleep(ST7102_RESET_WAIT_MS);
    luat_tp_irq_enable(cfg, 1);
    return 0;
}

static int tp_st7102_init(luat_tp_config_t *cfg) {
    uint8_t buf[4] = {0};
    uint8_t chip_id = 0;
    uint8_t fw_version = 0;
    uint8_t max_touches = 0;
    uint16_t x_res = 0;
    uint16_t y_res = 0;

    cfg->address = ST7102_ADDRESS;
    if (cfg->pin_int == LUAT_GPIO_NONE) {
        LLOGE("pin_int is required");
        return -1;
    }

    /* 初始化 I2C 总线：硬件 I2C 配引脚复用和速率，软件 I2C 配引脚 */
    if (cfg->soft_i2c != NULL) {
        if (i2c_soft_setup(cfg->soft_i2c)) {
            LLOGE("soft i2c setup failed");
            return -1;
        }
    } else {
        if (luat_i2c_setup(cfg->i2c_id, I2C_SPEED_FAST)) {
            LLOGE("i2c%d setup failed", cfg->i2c_id);
            return -1;
        }
    }

    st7102_reset_state();

    /* Reset pin as output high, interrupt pin as input */
    if (cfg->pin_rst != LUAT_GPIO_NONE) {
        luat_gpio_mode(cfg->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
        luat_gpio_set(cfg->pin_rst, Luat_GPIO_HIGH);
    }
    luat_gpio_mode(cfg->pin_int, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

    st7102_hw_reset(cfg);
    st7102_wait_normal(cfg);

    /* Chip ID 只用于打印，读到 0x00 也正常，不拿它判断芯片在不在位 */
    st7102_read_reg(cfg, ST7102_REG_CHIP_ID, &chip_id, 1);

    /* 最大触点数读不到就用默认值 */
    if (st7102_read_reg(cfg, ST7102_REG_MAX_TOUCHES, &max_touches, 1))
        max_touches = 0;
    if (max_touches == 0 || max_touches > LUAT_TP_TOUCH_MAX) {
        LLOGW("max touches %d out of range, use %d", max_touches, LUAT_TP_TOUCH_MAX);
        max_touches = LUAT_TP_TOUCH_MAX;
    }
    st7102_max_touches = max_touches;

    /* 分辨率读不回来就说明总线没通 */
    if (st7102_read_reg(cfg, ST7102_REG_X_RESOLUTION, buf, 4))
        return -1;
    x_res = (uint16_t)((((uint16_t)(buf[0] & ST7102_RES_HIGH_MASK)) << 8) | buf[1]);
    y_res = (uint16_t)((((uint16_t)(buf[2] & ST7102_RES_HIGH_MASK)) << 8) | buf[3]);
    if (x_res == 0 || y_res == 0) {
        LLOGE("resolution %dx%d, bus not ready", x_res, y_res);
        return -1;
    }

    buf[0] = 0;
    st7102_read_reg(cfg, ST7102_REG_FW_VERSION, buf, 1);
    fw_version = buf[0];
    memset(buf, 0, sizeof(buf));
    st7102_read_reg(cfg, ST7102_REG_FW_REVISION, buf, 4);
    LLOGI("ST7102 chip_id=0x%02X fw=0x%02X rev=%02X %02X %02X %02X res=%dx%d max_touches=%d",
          chip_id, fw_version, buf[0], buf[1], buf[2], buf[3],
          x_res, y_res, st7102_max_touches);

    /* Panel size comes from the IC unless the caller configured it */
    if (cfg->w == 0 && x_res > 0)
        cfg->w = x_res;
    if (cfg->h == 0 && y_res > 0)
        cfg->h = y_res;

    /* Data ready interrupt is active low, an explicit int_type from the caller wins */
    if (cfg->int_type == Luat_GPIO_RISING)
        cfg->int_type = Luat_GPIO_FALLING;

    luat_gpio_t gpio = {0};
    gpio.pin      = cfg->pin_int;
    gpio.mode     = Luat_GPIO_IRQ;
    gpio.pull     = Luat_GPIO_PULLUP;
    gpio.irq      = cfg->int_type;
    gpio.irq_cb   = luat_tp_irq_cb;
    gpio.irq_args = cfg;
    luat_gpio_setup(&gpio);

    st7102_init_state = 1;
    return 0;
}

static int tp_st7102_deinit(luat_tp_config_t *cfg) {
    st7102_init_state = 0;
    if (cfg->pin_int != LUAT_GPIO_NONE)
        luat_gpio_close(cfg->pin_int);
    if (cfg->pin_rst != LUAT_GPIO_NONE)
        luat_gpio_close(cfg->pin_rst);
    return 0;
}

luat_tp_opts_t tp_config_st7102 = {
    .name      = "st7102",
    .init      = tp_st7102_init,
    .deinit    = tp_st7102_deinit,
    .read      = tp_st7102_read,
    .read_done = tp_st7102_read_done,
    .sleep     = tp_st7102_sleep,
    .wakeup    = tp_st7102_wakeup,
};
