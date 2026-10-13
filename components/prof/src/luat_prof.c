/*
@module  prof
@summary cycle profiler 核心: 模块/槽位注册表与计数累加
@date    2026.10.14
@author  wendal
@tag LUAT_USE_PROF
*/

#include "luat_base.h"
#include "luat_prof.h"

/* 关态(LUAT_USE_PROF 未定义)时本 TU 为空, 避免 MSVC C4206 告警 */
typedef int luat_prof_empty_tu_t;

#ifdef LUAT_USE_PROF

#include <string.h>

#define LUAT_LOG_TAG "prof"
#include "luat_log.h"

typedef struct
{
    const char *name;
    uint32_t ticks;
    uint32_t calls;
    uint32_t max;
} luat_prof_slot_t;

typedef struct
{
    const char *name;
    const char *const *slot_names;
    uint8_t slot_count;
    luat_prof_slot_t slots[LUAT_PROF_MAX_SLOTS];
} luat_prof_mod_t;

volatile uint32_t luat_prof_on = 0;

static luat_prof_mod_t luat_prof_mods[LUAT_PROF_MAX_MODS];
static uint8_t luat_prof_mod_count = 0;
static uint8_t luat_prof_hw_inited = 0;

LUAT_WEAK void luat_prof_hw_init(void)
{
}

LUAT_WEAK uint32_t luat_prof_ticks_per_us(void)
{
    return 0;
}

#if !defined(__ARM_ARCH_7M__) && !defined(__ARM_ARCH_7EM__) && !defined(_MSC_VER) && !defined(__i386__) && !defined(__x86_64__)
LUAT_WEAK uint32_t luat_prof_tick(void)
{
    return 0;
}
#endif

int luat_prof_register(const char *module, const char *const *slot_names, uint8_t slot_count)
{
    int i;

    if (module == NULL || slot_names == NULL || slot_count == 0 || slot_count > LUAT_PROF_MAX_SLOTS)
    {
        return -1;
    }

    for (i = 0; i < luat_prof_mod_count; i++)
    {
        if (strcmp(luat_prof_mods[i].name, module) == 0)
        {
            return i;
        }
    }

    if (luat_prof_mod_count >= LUAT_PROF_MAX_MODS)
    {
        LLOGW("prof registry full (%d), %s rejected", LUAT_PROF_MAX_MODS, module);
        return -1;
    }

    i = luat_prof_mod_count++;
    luat_prof_mods[i].name = module;
    luat_prof_mods[i].slot_names = slot_names;
    luat_prof_mods[i].slot_count = slot_count;
    memset(luat_prof_mods[i].slots, 0, sizeof(luat_prof_mods[i].slots));
    return i;
}

void luat_prof_reset(void)
{
    int i;
    for (i = 0; i < luat_prof_mod_count; i++)
    {
        memset(luat_prof_mods[i].slots, 0, sizeof(luat_prof_mods[i].slots));
    }
}

void luat_prof_enable(int on)
{
    luat_prof_reset();
    if (on)
    {
        if (!luat_prof_hw_inited)
        {
            luat_prof_hw_init();
            luat_prof_hw_inited = 1;
        }
        luat_prof_on = 1;
    }
    else
    {
        luat_prof_on = 0;
    }
}

void luat_prof_span(int mod, int slot, uint32_t start, uint32_t end)
{
    uint32_t cost;
    luat_prof_slot_t *s;

    if (mod < 0 || mod >= luat_prof_mod_count)
    {
        return;
    }
    if (slot < 0 || slot >= luat_prof_mods[mod].slot_count)
    {
        return;
    }

    cost = end - start;
    s = &luat_prof_mods[mod].slots[slot];
    s->ticks += cost;
    s->calls++;
    if (cost > s->max)
    {
        s->max = cost;
    }
}

int luat_prof_modules(void)
{
    return luat_prof_mod_count;
}

const char *luat_prof_module_name(int mod)
{
    if (mod < 0 || mod >= luat_prof_mod_count)
    {
        return "";
    }
    return luat_prof_mods[mod].name;
}

int luat_prof_slots(int mod)
{
    if (mod < 0 || mod >= luat_prof_mod_count)
    {
        return 0;
    }
    return luat_prof_mods[mod].slot_count;
}

const char *luat_prof_slot_name(int mod, int slot)
{
    if (mod < 0 || mod >= luat_prof_mod_count || slot < 0 || slot >= luat_prof_mods[mod].slot_count)
    {
        return "";
    }
    return luat_prof_mods[mod].slot_names[slot];
}

uint32_t luat_prof_slot_ticks(int mod, int slot)
{
    if (mod < 0 || mod >= luat_prof_mod_count || slot < 0 || slot >= luat_prof_mods[mod].slot_count)
    {
        return 0;
    }
    return luat_prof_mods[mod].slots[slot].ticks;
}

uint32_t luat_prof_slot_calls(int mod, int slot)
{
    if (mod < 0 || mod >= luat_prof_mod_count || slot < 0 || slot >= luat_prof_mods[mod].slot_count)
    {
        return 0;
    }
    return luat_prof_mods[mod].slots[slot].calls;
}

uint32_t luat_prof_slot_max(int mod, int slot)
{
    if (mod < 0 || mod >= luat_prof_mod_count || slot < 0 || slot >= luat_prof_mods[mod].slot_count)
    {
        return 0;
    }
    return luat_prof_mods[mod].slots[slot].max;
}

#endif /* LUAT_USE_PROF */
