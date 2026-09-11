#ifndef LUAT_TP_H
#define LUAT_TP_H

#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_i2c.h"

#define LUAT_TP_TOUCH_MAX 10

typedef struct luat_tp_config luat_tp_config_t;
typedef struct luat_tp_opts luat_tp_opts_t;
typedef struct luat_tp_sink_ops luat_tp_sink_ops_t;

enum{
    LUAT_TP_ROTATE_0 = 0,
    LUAT_TP_ROTATE_90,
    LUAT_TP_ROTATE_180,
    LUAT_TP_ROTATE_270,
};

#define LUAT_TP_SWAP_NONE   0
#define LUAT_TP_SWAP_X      1
#define LUAT_TP_SWAP_Y      2
#define LUAT_TP_SWAP_XY     3

typedef struct{
	uint32_t         timestamp;
    uint16_t         x_coordinate;
    uint16_t         y_coordinate;
    uint8_t          event;
    uint8_t          track_id;
    uint8_t          width;
} luat_tp_data_t;

typedef struct luat_tp_config{
    char* name;
    luat_ei2c_t* soft_i2c;
    uint8_t address;
    uint8_t i2c_id;
    uint8_t pin_rst;
    uint8_t pin_int;
    uint8_t swap_xy;
    uint8_t direction;  // 旋转方向(软件控制) 
    uint8_t refresh_rate;
    uint8_t tp_num;
    uint8_t int_type;
    int16_t w;
    int16_t h;
    void* luat_cb;
    luat_tp_opts_t* opts;
    int (*callback)(luat_tp_config_t* luat_tp_config, luat_tp_data_t* luat_tp_data);
    luat_tp_data_t tp_data[LUAT_TP_TOUCH_MAX];
    luat_rtos_task_handle task_handle;
    /* Optional application adapter; TP never interprets its state or id. */
    const luat_tp_sink_ops_t *sink_ops;
    void *sink_context;
    uint32_t sink_id; /* Adapter-published identity, zero while detached. */
    uint8_t initialized, running;

} luat_tp_config_t;

/** Optional task-context sink. Set before init, keep unchanged until deinit.
 * Hooks run under TP serialization and must not call TP lifecycle APIs.
 * process reads cfg->tp_data, writes normalized output, returns count or error.
 * All hook pointers are optional; context belongs entirely to the adapter.
 * A failed open must clean up its own partial allocations before returning.
 */
struct luat_tp_sink_ops {
    int (*open)(luat_tp_config_t *cfg);
    void (*close)(luat_tp_config_t *cfg);
    int (*process)(luat_tp_config_t *cfg, luat_tp_data_t *normalized);
    void (*reset)(luat_tp_config_t *cfg);
    void (*suspend)(luat_tp_config_t *cfg, int suspended);
};

typedef struct luat_tp_opts {
    const char* name;
    int (*init)(luat_tp_config_t* luat_tp_config);
    int (*read)(luat_tp_config_t* luat_tp_config, luat_tp_data_t* luat_tp_data);
    void (*read_done)(luat_tp_config_t* luat_tp_config);
    int (*deinit)(luat_tp_config_t* luat_tp_config);
    int (*sleep)(luat_tp_config_t* luat_tp_config);
    int (*wakeup)(luat_tp_config_t* luat_tp_config);
} luat_tp_opts_t;

typedef enum{
	TP_EVENT_TYPE_NONE = 0,
	TP_EVENT_TYPE_DOWN,
	TP_EVENT_TYPE_UP,
	TP_EVENT_TYPE_MOVE
} luat_tp_event_type_t;


extern luat_tp_opts_t tp_config_gt9xx;
extern luat_tp_opts_t tp_config_gt9157;
extern luat_tp_opts_t tp_config_jd9261t;
extern luat_tp_opts_t tp_config_jd9261t_inited;
extern luat_tp_opts_t tp_config_ft3x68;
extern luat_tp_opts_t tp_config_cst820;
extern luat_tp_opts_t tp_config_cst816d;
extern luat_tp_opts_t tp_config_cst92xx;
extern luat_tp_opts_t tp_config_pc;

int luat_tp_init(luat_tp_config_t* luat_tp_config);
int luat_tp_process(luat_tp_config_t *config);

int luat_tp_irq_enable(luat_tp_config_t* luat_tp_config, uint8_t enabled);

int luat_tp_sleep(luat_tp_config_t* luat_tp_config);

int luat_tp_wakeup(luat_tp_config_t* luat_tp_config);

/** Stop a TP device. Config storage must outlive already queued IRQ messages. */
int luat_tp_deinit(luat_tp_config_t *config);
/** Transform a raw point to panel coordinates. Returns -1 outside raw bounds. */
int luat_tp_transform(const luat_tp_config_t *config, int32_t *x, int32_t *y);
void luat_tp_dimensions(const luat_tp_config_t *config, int32_t *width, int32_t *height);


#endif
