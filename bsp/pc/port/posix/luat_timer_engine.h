#ifndef LUAT_TIMER_ENGINE_H
#define LUAT_TIMER_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Opaque timer handle returned by luat_timer_engine_create(). */
typedef void* luat_timer_handle_t;

/** Callback signature: invoked from the engine thread when a timer fires. */
typedef void (*luat_timer_cb_t)(void *param);

/**
 * Initialize the timer engine. Must be called once before any other timer
 * function, typically from main() before luat_main().
 */
void luat_timer_engine_init(void);

/**
 * Shutdown the timer engine. Stops the background thread. Normally not
 * needed unless graceful teardown is required.
 */
void luat_timer_engine_deinit(void);

/**
 * Create a timer (does not start it).
 * @param cb    Callback to call when the timer fires.
 * @param param User parameter passed to the callback.
 * @return Opaque handle, or NULL on allocation failure.
 */
luat_timer_handle_t luat_timer_engine_create(luat_timer_cb_t cb, void *param);

/**
 * Update the callback/param of an existing (possibly running) timer.
 * Safe to call before start or after stop.
 */
void luat_timer_engine_set_cb(luat_timer_handle_t handle, luat_timer_cb_t cb, void *param);

/**
 * Start (or restart) a timer.
 * @param handle  Timer handle from luat_timer_engine_create().
 * @param ms      Timeout in milliseconds (must be > 0).
 * @param repeat  0 = one-shot, 1 = repeating.
 * @return 0 on success, -1 on error.
 */
int luat_timer_engine_start(luat_timer_handle_t handle, uint32_t ms, int repeat);

/**
 * Stop a running timer. Safe to call on an already-stopped timer.
 */
void luat_timer_engine_stop(luat_timer_handle_t handle);

/**
 * Stop and free a timer. The handle must not be used after this call.
 */
void luat_timer_engine_delete(luat_timer_handle_t handle);

/**
 * @return 1 if the timer is currently active (started and not yet fired/stopped),
 *         0 otherwise.
 */
int luat_timer_engine_is_active(luat_timer_handle_t handle);

/**
 * @return Milliseconds remaining until the timer fires, or 0 if inactive.
 */
uint32_t luat_timer_engine_remaining_ms(luat_timer_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_TIMER_ENGINE_H */
