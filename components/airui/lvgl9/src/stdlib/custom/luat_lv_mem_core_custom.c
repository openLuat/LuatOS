#include <stddef.h>

#include "../../stdlib/lv_mem.h"
#include "luat_mem.h"
#include "../../misc/lv_log.h"
#include "luat_airui_conf.h"

#if LV_USE_STDLIB_MALLOC == LV_STDLIB_CUSTOM

#ifndef LUAT_AIRUI_LVGL_HEAP_TYPE
    #ifdef LUAT_USE_PSRAM
        #define LUAT_AIRUI_LVGL_HEAP_TYPE LUAT_HEAP_PSRAM
    #else
        #define LUAT_AIRUI_LVGL_HEAP_TYPE LUAT_HEAP_AUTO
    #endif
#endif

void lv_mem_init(void)
{
    LV_LOG_INFO("lv_mem_init");
    // luat_heap_opt_init(LUAT_AIRUI_LVGL_HEAP_TYPE);
    return;
}

void lv_mem_deinit(void)
{
    return;
}

lv_mem_pool_t lv_mem_add_pool(void * mem, size_t bytes)
{
    LV_UNUSED(mem);
    LV_UNUSED(bytes);
    return NULL;
}

void lv_mem_remove_pool(lv_mem_pool_t pool)
{
    LV_UNUSED(pool);
}

void * lv_malloc_core(size_t size)
{
    return luat_heap_opt_malloc(LUAT_AIRUI_LVGL_HEAP_TYPE, size);
}

void * lv_realloc_core(void * p, size_t new_size)
{
    return luat_heap_opt_realloc(LUAT_AIRUI_LVGL_HEAP_TYPE, p, new_size);
}

void lv_free_core(void * p)
{
    luat_heap_opt_free(LUAT_AIRUI_LVGL_HEAP_TYPE, p);
}

void lv_mem_monitor_core(lv_mem_monitor_t * mon_p)
{
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;

    luat_meminfo_opt_sys(LUAT_AIRUI_LVGL_HEAP_TYPE, &total, &used, &max_used);

    mon_p->total_size = total;
    mon_p->free_size = (total >= used) ? (total - used) : 0;
    mon_p->free_biggest_size = mon_p->free_size;
    mon_p->max_used = max_used;
    mon_p->used_pct = (total > 0) ? (uint8_t)((used * 100) / total) : 0;
    mon_p->frag_pct = 0;
}

lv_result_t lv_mem_test_core(void)
{
    return LV_RESULT_OK;
}

#endif /* LV_USE_STDLIB_MALLOC == LV_STDLIB_CUSTOM */
