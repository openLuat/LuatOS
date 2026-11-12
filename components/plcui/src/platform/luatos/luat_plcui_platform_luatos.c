/** @file luat_plcui_platform_luatos.c Display-only LuatOS platform and timer. */
#include "luat_conf_bsp.h"
#if defined(LUAT_USE_PLCUI_LUATOS)

#include "luat_plcui_luatos.h"
#include "luat_mcu.h"
#include "luat_rtos.h"

static luat_rtos_timer_t refresh_timer;
static void (*refresh_callback)(void *);

const char *plcui_platform_name(void) { return "luatos-display"; }

uint32_t plcui_platform_state_lock(void)
{
    return luat_rtos_entry_critical();
}

void plcui_platform_state_unlock(uint32_t token)
{
    luat_rtos_exit_critical(token);
}

static uint32_t monotonic_ms(void)
{
    return (uint32_t)luat_mcu_tick64_ms();
}

/* The parameter is an immutable session token, never a platform allocation.
 * Stale invocations remain harmless across stop/restart in the runtime. */
static void timer_callback(void *parameter)
{
    uint32_t critical = luat_rtos_entry_critical();
    void (*callback)(void *) = refresh_callback;
    luat_rtos_exit_critical(critical);
    if (callback) callback(parameter);
}

int plcui_platform_timer_start(uint32_t period_ms, void (*callback)(void *), void *parameter)
{
    if (refresh_timer || !callback || !period_ms) return -1;
    if (luat_rtos_timer_create(&refresh_timer) != 0 || !refresh_timer) return -1;
    uint32_t critical = luat_rtos_entry_critical();
    refresh_callback = callback;
    luat_rtos_exit_critical(critical);
    int result = luat_rtos_timer_start(refresh_timer, period_ms, 1, timer_callback, parameter);
    if (result != 0) plcui_platform_timer_stop();
    return result;
}

void plcui_platform_timer_stop(void)
{
    uint32_t critical = luat_rtos_entry_critical();
    refresh_callback = NULL;
    luat_rtos_exit_critical(critical);
    if (!refresh_timer) return;
    luat_rtos_timer_stop(refresh_timer);
    luat_rtos_timer_delete(refresh_timer);
    refresh_timer = NULL;
}

int plcui_platform_init(int width, int height)
{
    if (plcui_luatos_display_init(width, height) != 0) return -1;
    lv_tick_set_cb(monotonic_ms);
    if (plcui_luatos_input_init(plcui_luatos_display()) != 0) {
        plcui_platform_deinit();
        return -1;
    }
    return 0;
}

void plcui_platform_deinit(void)
{
    plcui_platform_timer_stop();
    plcui_luatos_input_deinit();
    plcui_luatos_display_deinit();
}

void plcui_platform_poll(void)
{
    plcui_luatos_input_poll();
    plcui_luatos_display_poll();
}

lv_display_t *plcui_platform_display(void)
{
    return plcui_luatos_display();
}

int plcui_platform_snapshot(const char *path)
{
    (void)path;
    return PLCUI_PLATFORM_UNSUPPORTED;
}

#endif
