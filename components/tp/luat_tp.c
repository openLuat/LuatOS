#include "luat_base.h"
#include "luat_tp.h"
#include "luat_mem.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "tp"
#include "luat_log.h"

static luat_rtos_task_handle g_s_tp_task_handle;
static luat_rtos_mutex_t tp_mutex;
#define TP_LOCK() luat_rtos_mutex_lock(tp_mutex, LUAT_WAIT_FOREVER)
#define TP_UNLOCK() luat_rtos_mutex_unlock(tp_mutex)

void luat_tp_dimensions(const luat_tp_config_t *cfg, int32_t *w, int32_t *h)
{
    *w = (cfg->direction & 1) ? cfg->h : cfg->w;
    *h = (cfg->direction & 1) ? cfg->w : cfg->h;
}

int luat_tp_transform(const luat_tp_config_t *cfg, int32_t *x, int32_t *y)
{
    int32_t sx = *x, sy = *y, w, h;
    if (sx < 0 || sy < 0 || sx >= cfg->w || sy >= cfg->h) return -1;
    luat_tp_dimensions(cfg, &w, &h);
    switch (cfg->direction & 3) {
    case LUAT_TP_ROTATE_90: *x = sy; *y = cfg->w - 1 - sx; break;
    case LUAT_TP_ROTATE_180: *x = cfg->w - 1 - sx; *y = cfg->h - 1 - sy; break;
    case LUAT_TP_ROTATE_270: *x = cfg->h - 1 - sy; *y = sx; break;
    default: break;
    }
    if (cfg->swap_xy & LUAT_TP_SWAP_X) *x = w - 1 - *x;
    if (cfg->swap_xy & LUAT_TP_SWAP_Y) *y = h - 1 - *y;
    return 0;
}

/* One task-context read, also used by native transport regression tests. */
int luat_tp_process(luat_tp_config_t *cfg)
{
    luat_tp_data_t normalized[LUAT_TP_TOUCH_MAX];
    if (!cfg || !cfg->opts || !cfg->opts->read) return -1;
    TP_LOCK();
    /* Independent of the optional sink: discard stale IRQ work after stop. */
    if (!cfg->running) { TP_UNLOCK(); return 0; }
    int ret = cfg->opts->read(cfg, cfg->tp_data);
    if (ret >= 0 && cfg->sink_ops && cfg->sink_ops->process) {
        ret = cfg->sink_ops->process(cfg, normalized);
    } else if (ret >= 0) {
        memcpy(normalized, cfg->tp_data, sizeof(normalized));
        for (unsigned i = 0; i < LUAT_TP_TOUCH_MAX; i++) {
            if (normalized[i].event == TP_EVENT_TYPE_NONE) continue;
            int32_t x = normalized[i].x_coordinate, y = normalized[i].y_coordinate;
            if (!luat_tp_transform(cfg, &x, &y)) {
                normalized[i].x_coordinate = x;
                normalized[i].y_coordinate = y;
            }
        }
        /* Driver read() returns current contact count, including zero on UP. */
        ret = 1;
    }
    if (ret < 0 && cfg->sink_ops && cfg->sink_ops->reset) cfg->sink_ops->reset(cfg);
    if (cfg->opts->read_done) cfg->opts->read_done(cfg);
    TP_UNLOCK();
    /* Legacy callback receives the normalized task-local copy. */
    if (ret > 0 && cfg->callback) cfg->callback(cfg, normalized);
    return ret;
}

void luat_tp_task_entry(void *param)
{
    (void)param;
    uint32_t message_id;
    luat_tp_config_t *cfg;
    while (!g_s_tp_task_handle) luat_rtos_task_sleep(2);
    for (;;) {
        luat_rtos_message_recv(g_s_tp_task_handle, &message_id, &cfg, LUAT_WAIT_FOREVER);
        luat_tp_process(cfg);
    }
}

int luat_tp_init(luat_tp_config_t *cfg)
{
    if (!cfg || !cfg->opts || !cfg->opts->init) return -1;
    if (!tp_mutex && luat_rtos_mutex_create(&tp_mutex)) return -1;
    if (!g_s_tp_task_handle) {
        if (luat_rtos_task_create(&g_s_tp_task_handle, 4096, 27, "tp", luat_tp_task_entry, NULL, 32)) {
            g_s_tp_task_handle = NULL;
            LLOGE("tp task create failed!");
            return -1;
        }
    }
    TP_LOCK();
    if (cfg->initialized) { TP_UNLOCK(); return -1; }
    cfg->task_handle = g_s_tp_task_handle;
    int ret = cfg->opts->init(cfg);
    if (!ret && cfg->sink_ops && cfg->sink_ops->open) ret = cfg->sink_ops->open(cfg);
    if (ret && cfg->opts->deinit) cfg->opts->deinit(cfg);
    cfg->initialized = cfg->running = !ret;

    TP_UNLOCK();
    return ret;
}

int luat_tp_irq_enable(luat_tp_config_t *cfg, uint8_t enabled)
{
    return luat_gpio_irq_enable(cfg->pin_int, enabled, cfg->int_type, cfg);
}

LUAT_WEAK int luat_tp_sleep(luat_tp_config_t *cfg)
{
    if (!cfg || !cfg->opts || !cfg->opts->sleep) return -1;
    TP_LOCK();
    int ret = cfg->opts->sleep(cfg);
    if (!ret) {
        cfg->running = 0;
        if (cfg->sink_ops && cfg->sink_ops->suspend) cfg->sink_ops->suspend(cfg, 1);
    }
    TP_UNLOCK();
    return ret;
}

LUAT_WEAK int luat_tp_wakeup(luat_tp_config_t *cfg)
{
    if (!cfg || !cfg->opts || !cfg->opts->wakeup) return -1;
    TP_LOCK();
    int ret = cfg->opts->wakeup(cfg);
    if (!ret) {
        if (cfg->sink_ops && cfg->sink_ops->suspend) cfg->sink_ops->suspend(cfg, 0);
        cfg->running = 1;
    }
    TP_UNLOCK();
    return ret;
}

int luat_tp_deinit(luat_tp_config_t *cfg)
{
    if (!cfg || !cfg->opts || !cfg->opts->deinit) return -1;
    TP_LOCK();
    int ret = cfg->opts->deinit(cfg);
    if (!ret) {
        cfg->initialized = cfg->running = 0;
        if (cfg->sink_ops && cfg->sink_ops->close) cfg->sink_ops->close(cfg);
    }
    TP_UNLOCK();
    return ret;
}
