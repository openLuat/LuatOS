#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "ns2009"
#include "luat_log.h"

enum {
    NS2009_ADDR_MIN = 0x48,
    NS2009_ADDR_MAX = 0x4b,
    /* 12-bit, PD0=0: power down and restore PENIRQ after conversion. */
    NS2009_READ_X = 0xc0,
    NS2009_READ_Y = 0xd0,
    NS2009_INTERVAL_MS = 20,
    NS2009_RELEASE_FRAMES = 2,
    NS2009_FAILED_FRAMES = 5,
    NS2009_WINDOW = 3,
    NS2009_ADC_MAX = 4095,
    NS2009_CAL_POINTS = 4,
    NS2009_CAL_TIMEOUT_MS = 30000,
    NS2009_CAL_MIN_X = 300,
    NS2009_CAL_MIN_Y = 200,
};

typedef struct {
    uint16_t x, y;
} ns_point_t;

typedef enum {
    NS_CAL_IDLE,
    NS_CAL_POINT,
    NS_CAL_WAIT_RELEASE,
    NS_CAL_CAPTURE,
    NS_CAL_DONE,
    NS_CAL_RESUME,
} ns_cal_phase_t;

typedef struct {
    /* Keep the current mapping until a complete new fit succeeds. */
    ns_point_t endpoints[2];
    bool calibrated, swap;

    ns_point_t points[NS2009_CAL_POINTS];
    luat_tp_cal_notify_t notify;
    uint64_t deadline;
    int serial;
    uint8_t phase, index;
    bool queued, notice_blocked, ok;
} ns_calibration_t;

typedef struct {
    const char *stage;
    int detail; /* HAL return value, pin level or invalid padding nibble. */
    uint8_t command;
} ns_fault_t;

/* One controller. TP task state is serialized by the TP core. */
static struct {
    luat_tp_config_t *cfg;
    luat_rtos_timer_t timer;
    ns_calibration_t calibration;
    ns_point_t window[NS2009_WINDOW];
    uint8_t count, next, high, failures;
    bool gpio_open, irq_enabled, pressed, poll;
    bool sampling_warned, rearm_warned, post_retry_logged;
} ns;

/* The GPIO/timer callbacks only touch this mailbox state, never the driver
 * state or I2C. The high bits identify the open instance. */
enum {
    NS_QUEUED = 1,
    NS_KICK = 2,
    NS_POLL = 4,
    NS_POST_RETRY = 8,
    NS_FLAGS = NS_QUEUED | NS_KICK | NS_POLL | NS_POST_RETRY,
};
static uint32_t ns_generation;
static int ns_cal_serial;
static uint32_t ns_signal;
static luat_tp_config_t *ns_signal_cfg;
static luat_rtos_task_handle ns_signal_task;

static void ns_signal_update(uint32_t id, uint32_t set, uint32_t clear)
{
    uint32_t old = __atomic_load_n(&ns_signal, __ATOMIC_ACQUIRE);
    while ((old & ~(uint32_t)NS_FLAGS) == id) {
        uint32_t next = (old & ~clear) | set;
        if (__atomic_compare_exchange_n(&ns_signal, &old, next, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
            break;
        }
    }
}

static void ns_post(uint32_t id, bool irq)
{
    if (!id) return;
    if (irq) ns_signal_update(id, NS_KICK, 0);
    uint32_t old = __atomic_load_n(&ns_signal, __ATOMIC_ACQUIRE);
    while ((old & ~(uint32_t)NS_FLAGS) == id && !(old & NS_QUEUED) && (old & (NS_KICK | NS_POLL))) {
        luat_tp_config_t *cfg = __atomic_load_n(&ns_signal_cfg, __ATOMIC_RELAXED);
        luat_rtos_task_handle task = __atomic_load_n(&ns_signal_task, __ATOMIC_RELAXED);
        uint32_t next = (old & ~(uint32_t)NS_KICK) | NS_QUEUED;
        if (__atomic_compare_exchange_n(&ns_signal, &old, next, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
            if (luat_rtos_message_send(task, id, cfg)) {
                ns_signal_update(id, NS_KICK | NS_POST_RETRY, NS_QUEUED);
            }
            return;
        }
    }
}

static int ns_irq(int pin, void *arg)
{
    (void)pin;
    ns_post((uint32_t)(uintptr_t)arg, true);
    return 0;
}

static void ns_timer(void *arg)
{
    ns_post((uint32_t)(uintptr_t)arg, false);
}

static bool ns_is_released(const luat_tp_config_t *cfg)
{
    return luat_gpio_get(cfg->pin_int) == LUAT_GPIO_HIGH;
}

static int ns_irq_enable(luat_tp_config_t *cfg, bool enable)
{
    if (ns.irq_enabled == enable) return 0;
    int ret = luat_gpio_irq_enable(cfg->pin_int, enable, LUAT_GPIO_FALLING_IRQ,
                                   (void *)(uintptr_t)cfg->read_message_id);
    if (!ret) ns.irq_enabled = enable;
    return ret;
}

static bool ns_rearm_irq(luat_tp_config_t *cfg)
{
    int ret = ns_irq_enable(cfg, true);
    if (ret) {
        if (!ns.rearm_warned) LLOGW("PENIRQ rearm failed: gpio=%u rc=%d; retrying", cfg->pin_int, ret);
        ns.rearm_warned = true;
        return false;
    }
    if (ns.rearm_warned) LLOGI("PENIRQ rearm recovered: gpio=%u", cfg->pin_int);
    ns.rearm_warned = false;
    /* Recover a contact starting between the last sample and IRQ rearm. */
    return ns_is_released(cfg);
}

static bool ns_valid_pen(int level)
{
    return level == LUAT_GPIO_LOW || level == LUAT_GPIO_HIGH;
}

static bool ns_read12(const luat_tp_config_t *cfg, uint8_t command, uint16_t *value, ns_fault_t *fault)
{
    /* Leave invalid padding if a HAL timeout returns success without both bytes. */
    uint8_t bytes[2] = {0xff, 0xff};
    /* The command starts a conversion; it is not a register address. */
    int ret = luat_i2c_send(cfg->i2c_id, cfg->address, &command, 1, 1);
    if (ret) {
        *fault = (ns_fault_t){ "i2c-send", ret, command };
        return false;
    }
    ret = luat_i2c_recv(cfg->i2c_id, cfg->address, bytes, sizeof(bytes));
    if (ret) {
        *fault = (ns_fault_t){ "i2c-recv", ret, command };
        return false;
    }
    if (bytes[1] & 0x0f) {
        *fault = (ns_fault_t){ "adc-padding", bytes[1] & 0x0f, command };
        return false;
    }
    *value = ((uint16_t)bytes[0] << 4) | (bytes[1] >> 4);
    return true;
}

static int ns_detect(luat_tp_config_t *cfg)
{
    for (unsigned addr = NS2009_ADDR_MIN; addr <= NS2009_ADDR_MAX; addr++) {
        cfg->address = addr;
        uint16_t probe;
        ns_fault_t fault = {0};
        /* There is no product ID. Look for a valid ADC conversion reply. */
        if (ns_read12(cfg, NS2009_READ_X, &probe, &fault)) return 0;
        LLOGD("probe miss: i2c=%u addr=0x%02x stage=%s cmd=0x%02x detail=%d",
              cfg->i2c_id, addr, fault.stage, fault.command, fault.detail);
    }
    cfg->address = 0;
    LLOGE("probe failed: i2c=%u no valid reply at 0x%02x..0x%02x",
          cfg->i2c_id, NS2009_ADDR_MIN, NS2009_ADDR_MAX);
    return -1;
}

static int ns_init_failed(const luat_tp_config_t *cfg, const char *stage, int detail)
{
    LLOGE("init failed: stage=%s i2c=%u addr=0x%02x penirq=%u detail=%d",
          stage, cfg->i2c_id, cfg->address, cfg->pin_int, detail);
    return -1;
}

static int ns_init(luat_tp_config_t *cfg)
{
    if (ns.cfg) return ns_init_failed(cfg, "already-open", 0);
    if (cfg->soft_i2c) return ns_init_failed(cfg, "hardware-i2c-required", 0);
    if (cfg->pin_int == LUAT_GPIO_NONE) return ns_init_failed(cfg, "penirq-required", 0);
    if (cfg->w < 2 || cfg->h < 2) {
        LLOGE("init failed: invalid panel size %dx%d", cfg->w, cfg->h);
        return -1;
    }
    int ret = luat_i2c_exist(cfg->i2c_id);
    if (ret <= 0) return ns_init_failed(cfg, "i2c-port", ret);
    if (ns_detect(cfg)) return -1;

    ns.cfg = cfg;
    ns_generation += NS_FLAGS + 1;
    if (!ns_generation) ns_generation = NS_FLAGS + 1;
    cfg->read_message_id = ns_generation;
    cfg->tp_num = 1;
    cfg->int_type = LUAT_GPIO_FALLING_IRQ;
    memset(cfg->tp_data, 0, sizeof(cfg->tp_data));

    void *token = (void *)(uintptr_t)cfg->read_message_id;
    luat_gpio_cfg_t gpio = {
        .pin = cfg->pin_int, .mode = LUAT_GPIO_IRQ, .pull = LUAT_GPIO_PULLUP,
        .irq_type = LUAT_GPIO_FALLING_IRQ, .irq_cb = ns_irq, .irq_args = token,
    };
    ret = luat_gpio_open(&gpio);
    if (ret) return ns_init_failed(cfg, "gpio-open", ret);
    ns.gpio_open = true;
    int pen = luat_gpio_get(cfg->pin_int);
    if (!ns_valid_pen(pen)) return ns_init_failed(cfg, "penirq-read", pen);
    ret = ns_irq_enable(cfg, true);
    if (ret) return ns_init_failed(cfg, "irq-enable", ret);
    ret = luat_rtos_timer_create(&ns.timer);
    if (ret) return ns_init_failed(cfg, "timer-create", ret);
    ret = luat_rtos_timer_start(ns.timer, NS2009_INTERVAL_MS, 1, ns_timer, token);
    return ret ? ns_init_failed(cfg, "timer-start", ret) : 0;
}

static void ns_activate(luat_tp_config_t *cfg)
{
    __atomic_store_n(&ns_signal_cfg, cfg, __ATOMIC_RELAXED);
    __atomic_store_n(&ns_signal_task, cfg->task_handle, __ATOMIC_RELAXED);
    /* A pen already held at initialization has no falling edge to deliver. */
    __atomic_store_n(&ns_signal, cfg->read_message_id | NS_KICK, __ATOMIC_RELEASE);
    LLOGI("ready: i2c=%u addr=0x%02x penirq=%u level=%d panel=%dx%d dir=%u mirror=%u interval=%dms sink=%u",
          cfg->i2c_id, cfg->address, cfg->pin_int, luat_gpio_get(cfg->pin_int), cfg->w, cfg->h,
          cfg->direction, cfg->swap_xy, NS2009_INTERVAL_MS, cfg->sink_ops != NULL);
}

static int ns_deinit(luat_tp_config_t *cfg)
{
    if (ns.cfg != cfg) return 0;
    __atomic_store_n(&ns_signal, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&ns_signal_cfg, NULL, __ATOMIC_RELAXED);
    __atomic_store_n(&ns_signal_task, NULL, __ATOMIC_RELAXED);
    if (ns.gpio_open) {
        ns_irq_enable(cfg, false);
        luat_gpio_close(cfg->pin_int);
    }
    if (ns.timer) {
        luat_rtos_timer_stop(ns.timer);
        luat_rtos_timer_delete(ns.timer);
    }
    memset(&ns, 0, sizeof(ns));
    memset(cfg->tp_data, 0, sizeof(cfg->tp_data));
    return 0;
}

static uint16_t median3(uint16_t a, uint16_t b, uint16_t c)
{
    if (a > b) { uint16_t tmp = a; a = b; b = tmp; }
    if (b > c) b = c;
    return a > b ? a : b;
}

static ns_point_t ns_median(void)
{
    return (ns_point_t){
        median3(ns.window[0].x, ns.window[1].x, ns.window[2].x),
        median3(ns.window[0].y, ns.window[1].y, ns.window[2].y),
    };
}

static void ns_cal_next_notice(ns_calibration_t *cal, ns_cal_phase_t phase)
{
    ns_cal_serial = ns_cal_serial == INT_MAX ? 1 : ns_cal_serial + 1;
    cal->serial = ns_cal_serial;
    cal->phase = phase;
    cal->queued = false;
    cal->notice_blocked = false;
}

static bool ns_cal_busy(const luat_tp_config_t *cfg)
{
    return ns.calibration.phase != NS_CAL_IDLE || ns.pressed || !ns_is_released(cfg);
}

static int ns_cal_begin(luat_tp_config_t *cfg, luat_tp_cal_notify_t notify)
{
    if (ns.cfg != cfg) return LUAT_TP_CAL_UNSUPPORTED;
    if (ns_cal_busy(cfg)) return LUAT_TP_CAL_BUSY;
    ns_calibration_t *cal = &ns.calibration;
    cal->notify = notify;
    cal->index = 0;
    cal->deadline = 0;
    ns_cal_next_notice(cal, NS_CAL_POINT);
    ns_signal_update(cfg->read_message_id, NS_KICK, 0);
    return 0;
}

static int32_t ns_cal_mark(int32_t extent, bool far)
{
    int32_t edge = extent - 1;
    return far ? edge - edge / 10 : edge / 10;
}

static bool ns_cal_notice(luat_tp_config_t *cfg, int serial, luat_tp_cal_notice_t *out)
{
    const ns_calibration_t *cal = &ns.calibration;
    if (ns.cfg != cfg || !cal->queued || cal->serial != serial) return false;
    out->done = cal->phase == NS_CAL_DONE;
    out->ok = cal->ok;
    if (!out->done) {
        out->x = ns_cal_mark(cfg->w, cal->index & 1);
        out->y = ns_cal_mark(cfg->h, cal->index & 2);
        luat_tp_transform(cfg, &out->x, &out->y);
        // LLOGD("calibration target %u: pixel=(%d,%d)", cal->index + 1, (int)out->x, (int)out->y);
    }
    return true;
}

static void ns_cal_ack(luat_tp_config_t *cfg, int serial, bool callback_ok)
{
    ns_calibration_t *cal = &ns.calibration;
    if (ns.cfg != cfg || !cal->notify) return;
    /* A point callback can fail after the driver has already queued a timeout. */
    if (!callback_ok || (cal->serial == serial && cal->phase == NS_CAL_DONE)) {
        cal->notify = NULL;
        cal->queued = false;
        cal->phase = NS_CAL_RESUME;
    } else if (cal->serial == serial && cal->phase == NS_CAL_POINT) {
        cal->queued = false;
        cal->phase = NS_CAL_WAIT_RELEASE;
    }
}

static unsigned ns_cal_span(uint16_t a, uint16_t b)
{
    return a >= b ? a - b : b - a;
}

static uint16_t ns_cal_mean(uint16_t a, uint16_t b)
{
    return ((uint32_t)a + b + 1) / 2;
}

static bool ns_cal_apply(ns_calibration_t *cal, const luat_tp_cal_data_t *data)
{
    if ((uint32_t)data->left > NS2009_ADC_MAX || (uint32_t)data->right > NS2009_ADC_MAX ||
        (uint32_t)data->top > NS2009_ADC_MAX || (uint32_t)data->bottom > NS2009_ADC_MAX) return false;
    uint16_t x0 = data->left, x1 = data->right, y0 = data->top, y1 = data->bottom;
    unsigned x_span = ns_cal_span(x0, x1), y_span = ns_cal_span(y0, y1);
    if (x_span < NS2009_CAL_MIN_X || y_span < NS2009_CAL_MIN_Y) {
        LLOGW("calibration rejected: span=(%u,%u) min=(%d,%d); mapping unchanged",
              x_span, y_span, NS2009_CAL_MIN_X, NS2009_CAL_MIN_Y);
        return false;
    }
    cal->endpoints[0] = (ns_point_t){x0, y0};
    cal->endpoints[1] = (ns_point_t){x1, y1};
    cal->swap = data->swap;
    cal->calibrated = true;
    LLOGI("calibration applied: swap=%u raw-x=%u..%u raw-y=%u..%u", cal->swap, x0, x1, y0, y1);
    return true;
}

static int ns_cal_get(luat_tp_config_t *cfg, luat_tp_cal_data_t *out)
{
    if (ns.cfg != cfg) return LUAT_TP_CAL_UNSUPPORTED;
    const ns_calibration_t *cal = &ns.calibration;
    if (!cal->calibrated) return LUAT_TP_CAL_NOT_CALIBRATED;
    *out = (luat_tp_cal_data_t){
        .left = cal->endpoints[0].x, .right = cal->endpoints[1].x,
        .top = cal->endpoints[0].y, .bottom = cal->endpoints[1].y, .swap = cal->swap,
    };
    return 0;
}

static int ns_cal_set(luat_tp_config_t *cfg, const luat_tp_cal_data_t *data)
{
    if (ns.cfg != cfg) return LUAT_TP_CAL_UNSUPPORTED;
    if (ns_cal_busy(cfg)) return LUAT_TP_CAL_BUSY;
    return ns_cal_apply(&ns.calibration, data) ? 0 : LUAT_TP_CAL_INVALID_DATA;
}

static bool ns_cal_fit(ns_calibration_t *cal)
{
    const ns_point_t *p = cal->points;
    unsigned x_travel = ns_cal_span(p[0].x, p[1].x) + ns_cal_span(p[2].x, p[3].x);
    unsigned y_travel = ns_cal_span(p[0].y, p[1].y) + ns_cal_span(p[2].y, p[3].y);
    bool swap = y_travel > x_travel;
    const luat_tp_cal_data_t data = {
        .left = swap ? ns_cal_mean(p[0].y, p[2].y) : ns_cal_mean(p[0].x, p[2].x),
        .right = swap ? ns_cal_mean(p[1].y, p[3].y) : ns_cal_mean(p[1].x, p[3].x),
        .top = swap ? ns_cal_mean(p[0].x, p[1].x) : ns_cal_mean(p[0].y, p[1].y),
        .bottom = swap ? ns_cal_mean(p[2].x, p[3].x) : ns_cal_mean(p[2].y, p[3].y),
        .swap = swap,
    };
    return ns_cal_apply(cal, &data);
}

static const char *ns_cal_wait_stage(const ns_calibration_t *cal)
{
    switch (cal->phase) {
    case NS_CAL_POINT:
        return cal->queued ? "lua-callback" : "msgbus";
    case NS_CAL_WAIT_RELEASE:
        return "pen-release";
    case NS_CAL_CAPTURE:
        return "samples";
    default:
        return "session";
    }
}

static void ns_cal_step(luat_tp_config_t *cfg, bool released, bool failed, const ns_point_t *sample)
{
    ns_calibration_t *cal = &ns.calibration;
    if (cal->phase == NS_CAL_RESUME) {
        if (released) {
            cal->phase = NS_CAL_IDLE;
        }
        return;
    }
    if (cal->phase != NS_CAL_DONE) {
        uint64_t now = luat_mcu_tick64_ms();
        if (!cal->deadline) cal->deadline = now + NS2009_CAL_TIMEOUT_MS;
        if (failed || now >= cal->deadline) {
            LLOGW("calibration failed: point=%u stage=%s reason=%s; mapping unchanged",
                  cal->index + 1, ns_cal_wait_stage(cal), failed ? "sampling-fault" : "timeout");
            cal->ok = false;
            ns_cal_next_notice(cal, NS_CAL_DONE);
        } else if (cal->phase == NS_CAL_WAIT_RELEASE && released) {
            cal->phase = NS_CAL_CAPTURE;
        } else if (cal->phase == NS_CAL_CAPTURE && released && sample) {
            cal->points[cal->index++] = *sample;
            // LLOGD("calibration captured %u: raw=(%u,%u)", cal->index, sample->x, sample->y);
            if (cal->index == NS2009_CAL_POINTS) {
                cal->ok = ns_cal_fit(cal);
                ns_cal_next_notice(cal, NS_CAL_DONE);
            } else {
                cal->deadline = now + NS2009_CAL_TIMEOUT_MS;
                ns_cal_next_notice(cal, NS_CAL_POINT);
            }
        }
    }
    if ((cal->phase == NS_CAL_POINT || cal->phase == NS_CAL_DONE) && !cal->queued) {
        cal->queued = cal->notify(cfg, cal->serial) == 0;
        if (!cal->queued && !cal->notice_blocked) {
            LLOGW("calibration %s notice delayed by msgbus; retrying",
                  cal->phase == NS_CAL_DONE ? "done" : "point");
            cal->notice_blocked = true;
        }
    }
}

static uint16_t ns_cal_axis(uint16_t raw, uint16_t a, uint16_t b, int32_t extent)
{
    int32_t span = (int32_t)b - a;
    int32_t first = ns_cal_mark(extent, false), last = ns_cal_mark(extent, true);
    int64_t num = (int64_t)first * span + ((int32_t)raw - a) * (int64_t)(last - first);
    if (span < 0) {
        span = -span;
        num = -num;
    }
    if (num <= 0) return 0;
    if (num >= (int64_t)(extent - 1) * span) return extent - 1;
    return (num + span / 2) / span;
}

static ns_point_t ns_map(const luat_tp_config_t *cfg, ns_point_t raw)
{
    const ns_calibration_t *cal = &ns.calibration;
    if (!cal->calibrated) {
        return (ns_point_t){
            ((uint32_t)raw.x * (cfg->w - 1) + NS2009_ADC_MAX / 2) / NS2009_ADC_MAX,
            ((uint32_t)raw.y * (cfg->h - 1) + NS2009_ADC_MAX / 2) / NS2009_ADC_MAX,
        };
    }
    return (ns_point_t){
        ns_cal_axis(cal->swap ? raw.y : raw.x, cal->endpoints[0].x, cal->endpoints[1].x, cfg->w),
        ns_cal_axis(cal->swap ? raw.x : raw.y, cal->endpoints[0].y, cal->endpoints[1].y, cfg->h),
    };
}

static bool ns_check_sampling(const ns_fault_t *fault, int pen, bool fresh)
{
    if (!fault->stage) {
        ns.failures = 0;
        /* An idle high level does not prove that the ADC link recovered. */
        if (fresh && ns.sampling_warned) {
            LLOGI("sampling recovered");
            ns.sampling_warned = false;
        }
        return false;
    }
    if (ns.failures < NS2009_FAILED_FRAMES) ns.failures++;
    if (ns.failures == NS2009_FAILED_FRAMES && !ns.sampling_warned) {
        LLOGW("sampling failed %u frames: stage=%s cmd=0x%02x detail=%d level=%d pressed=%u",
              ns.failures, fault->stage, fault->command, fault->detail, pen, ns.pressed);
        ns.sampling_warned = true;
    }
    return ns.failures == NS2009_FAILED_FRAMES;
}

static int ns_read(luat_tp_config_t *cfg, luat_tp_data_t *data)
{
    bool calibrating = ns.calibration.phase != NS_CAL_IDLE;
    bool sample = !calibrating || ns.calibration.phase == NS_CAL_CAPTURE;
    ns_point_t raw = {0};
    int pen = luat_gpio_get(cfg->pin_int);
    ns_fault_t fault = {0};
    bool fresh = false;
    if (!ns_valid_pen(pen)) fault = (ns_fault_t){ "penirq-read", pen, 0 };
    if (!sample) ns.count = ns.next = 0;
    if (pen == LUAT_GPIO_LOW) {
        ns.high = 0;
        int ret = ns_irq_enable(cfg, false);
        if (ret) {
            fault = (ns_fault_t){ "irq-mask", ret, 0 };
        } else if (sample) {
            bool valid = ns_read12(cfg, NS2009_READ_X, &raw.x, &fault) &&
                         ns_read12(cfg, NS2009_READ_Y, &raw.y, &fault);
            /* Only idle PENIRQ is meaningful; it is driven low while measuring. */
            pen = luat_gpio_get(cfg->pin_int);
            if (valid && !ns_valid_pen(pen)) fault = (ns_fault_t){ "penirq-read", pen, 0 };
            fresh = valid && pen == LUAT_GPIO_LOW;
        }
    }
    if (pen == LUAT_GPIO_HIGH) {
        if (ns.high < NS2009_RELEASE_FRAMES) ns.high++;
    } else {
        ns.high = 0;
    }
    bool released = ns.high == NS2009_RELEASE_FRAMES;
    bool persistent_failure = ns_check_sampling(&fault, pen, fresh);
    if (fresh) {
        ns.window[ns.next] = raw;
        ns.next = (ns.next + 1) % NS2009_WINDOW;
        if (ns.count < NS2009_WINDOW) ns.count++;
    }
    if (ns.count == NS2009_WINDOW) raw = ns_median();
    bool point_ready = released && ns.count == NS2009_WINDOW;
    if (released || persistent_failure) ns.count = ns.next = 0;

    if (calibrating) {
        ns_cal_step(cfg, released, persistent_failure, point_ready ? &raw : NULL);
    }
    ns.poll = !released || ns.calibration.phase != NS_CAL_IDLE;
    if (released && !ns.irq_enabled && !ns_rearm_irq(cfg)) ns.poll = true;

    if (calibrating) return LUAT_TP_READ_NO_FRAME;
    if (released || persistent_failure) {
        if (!ns.pressed) return LUAT_TP_READ_NO_FRAME;
        ns.pressed = false;
        data[0].timestamp = luat_mcu_ticks();
        data[0].event = TP_EVENT_TYPE_UP;
        return 0;
    }
    if (!fresh) return LUAT_TP_READ_NO_FRAME;
    ns_point_t p = ns_map(cfg, raw);
    if (ns.pressed && data[0].x_coordinate == p.x && data[0].y_coordinate == p.y) return LUAT_TP_READ_NO_FRAME;
    data[0] = (luat_tp_data_t){
        .timestamp = luat_mcu_ticks(),
        .x_coordinate = p.x, .y_coordinate = p.y,
        .event = ns.pressed ? TP_EVENT_TYPE_MOVE : TP_EVENT_TYPE_DOWN,
    };
    ns.pressed = true;
    return 1;
}

static void ns_read_done(luat_tp_config_t *cfg)
{
    if (!ns.post_retry_logged && (__atomic_load_n(&ns_signal, __ATOMIC_ACQUIRE) & NS_POST_RETRY)) {
        LLOGW("TP task post failed; read retried");
        ns.post_retry_logged = true;
    }
    ns_signal_update(cfg->read_message_id, ns.poll ? NS_POLL : 0, NS_QUEUED | NS_POLL | NS_POST_RETRY);
}

static const luat_tp_calibration_ops_t ns_calibration_ops = {
    .begin = ns_cal_begin,
    .notice = ns_cal_notice,
    .ack = ns_cal_ack,
    .get = ns_cal_get,
    .set = ns_cal_set,
};

luat_tp_opts_t tp_config_ns2009 = {
    .name = "ns2009",
    .init = ns_init,
    .activate = ns_activate,
    .read = ns_read,
    .read_done = ns_read_done,
    .deinit = ns_deinit,
    .calibration = &ns_calibration_ops,
    .default_pin_int = LUAT_GPIO_NONE,
};
