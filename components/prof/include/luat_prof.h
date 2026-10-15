#ifndef LUAT_PROF_H
#define LUAT_PROF_H

/**
 * @file luat_prof.h
 * @brief 通用 cycle profiler(性能周期剖析), 调优专用, 默认完全编译关闭.
 *
 * 开启方式: 定义 LUAT_USE_PROF (BSP 配置头或 xmake add_defines).
 *
 * 关闭(默认)时: LUAT_PROF_BEGIN/END 宏展开为 ((void)0), 本头文件所有函数
 * 为 static inline 空桩, 消费者代码不需要任何 #ifdef, 指令流与未插桩一致.
 *
 * 消费者用法:
 * @code
 * #include "luat_prof.h"
 * static const char *const mymod_slots[] = {"encode", "decode"};
 * static int mymod_id = -1;
 * // 模块初始化时注册一次(关态下是空桩, 返回 -1):
 * mymod_id = luat_prof_register("mymod", mymod_slots, 2);
 * // 热路径:
 * uint32_t tok;
 * LUAT_PROF_BEGIN(tok);
 * ... 被测代码 ...
 * LUAT_PROF_END(mymod_id, 0, tok);
 * @endcode
 */

#include <stdint.h>

/* 让纯 C 消费者(不经 lua.h/luaconf.h 链)也能看到 luat_conf_bsp.h 里的 LUAT_USE_PROF;
   找不到时依赖 -D 定义或默认关闭. */
#if defined(__has_include)
#if __has_include("luat_conf_bsp.h")
#include "luat_conf_bsp.h"
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifndef LUAT_PROF_MAX_MODS
#define LUAT_PROF_MAX_MODS 8
#endif

#ifndef LUAT_PROF_MAX_SLOTS
#define LUAT_PROF_MAX_SLOTS 32
#endif

#ifdef LUAT_USE_PROF

/*-------------------------------------------------------------------
 * 架构内联 tick: 热路径零调用, volatile 读不产生内存屏障.
 *   ARMv7-M   -> DWT CYCCNT
 *   MSVC/x86  -> rdtsc
 *   其他      -> luat_prof_tick(), weak 桩, BSP 可覆盖
 *-------------------------------------------------------------------*/

#if defined(__ARM_ARCH_7M__) || defined(__ARM_ARCH_7EM__)

#define LUAT_PROF_TICK() (*(volatile uint32_t *)0xE0001004u)

#elif defined(_MSC_VER)

#include <intrin.h>
#define LUAT_PROF_TICK() ((uint32_t)__rdtsc())

#elif defined(__i386__) || defined(__x86_64__)

#define LUAT_PROF_TICK() ((uint32_t)__builtin_ia32_rdtsc())

#else

uint32_t luat_prof_tick(void);
#define LUAT_PROF_TICK() luat_prof_tick()

#endif

/* 非 0 时剖析器在采集. 宏直读, 关闭运行时不产生调用. */
extern volatile uint32_t luat_prof_on;

#define LUAT_PROF_BEGIN(tok)                                                  \
    do {                                                                      \
        (tok) = luat_prof_on ? LUAT_PROF_TICK() : 0u;                          \
    } while (0)

#define LUAT_PROF_END(mod, slot, tok)                                         \
    do {                                                                      \
        if ((tok) != 0u)                                                      \
        {                                                                     \
            const uint32_t luat_prof_now_ = LUAT_PROF_TICK();                  \
            luat_prof_span((mod), (slot), (tok), luat_prof_now_);              \
        }                                                                     \
    } while (0)

int luat_prof_register(const char *module, const char *const *slot_names, uint8_t slot_count);
void luat_prof_enable(int on);
void luat_prof_reset(void);
void luat_prof_span(int mod, int slot, uint32_t start, uint32_t end);

int luat_prof_modules(void);
const char *luat_prof_module_name(int mod);
int luat_prof_slots(int mod);
const char *luat_prof_slot_name(int mod, int slot);
uint32_t luat_prof_slot_ticks(int mod, int slot);
uint32_t luat_prof_slot_calls(int mod, int slot);
uint32_t luat_prof_slot_max(int mod, int slot);

/* 平台挂钩: weak 默认桩, BSP 覆盖.
 * ticks_per_us 返回 0 表示无频率信息(NO-DATA), Lua 侧只报原始 ticks. */
void luat_prof_hw_init(void);
uint32_t luat_prof_ticks_per_us(void);

#else /* !LUAT_USE_PROF */

#define LUAT_PROF_BEGIN(tok)         ((void)0)
#define LUAT_PROF_END(mod, slot, tok) ((void)0)

static inline int luat_prof_register(const char *module, const char *const *slot_names, uint8_t slot_count)
{
    (void)module; (void)slot_names; (void)slot_count;
    return -1;
}
static inline void luat_prof_enable(int on) { (void)on; }
static inline void luat_prof_reset(void) {}
static inline void luat_prof_span(int mod, int slot, uint32_t start, uint32_t end)
{
    (void)mod; (void)slot; (void)start; (void)end;
}
static inline int luat_prof_modules(void) { return 0; }
static inline const char *luat_prof_module_name(int mod) { (void)mod; return ""; }
static inline int luat_prof_slots(int mod) { (void)mod; return 0; }
static inline const char *luat_prof_slot_name(int mod, int slot) { (void)mod; (void)slot; return ""; }
static inline uint32_t luat_prof_slot_ticks(int mod, int slot) { (void)mod; (void)slot; return 0; }
static inline uint32_t luat_prof_slot_calls(int mod, int slot) { (void)mod; (void)slot; return 0; }
static inline uint32_t luat_prof_slot_max(int mod, int slot) { (void)mod; (void)slot; return 0; }
static inline void luat_prof_hw_init(void) {}
static inline uint32_t luat_prof_ticks_per_us(void) { return 0; }

#endif /* LUAT_USE_PROF */

#ifdef __cplusplus
}
#endif

#endif /* LUAT_PROF_H */
