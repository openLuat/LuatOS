/* Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
 * All rights reserved.
 *
 * This software is supplied "AS IS" without any warranties.
 * RDA assumes no responsibility or liability for the use of the software,
 * conveys no license or title under any patent, copyright, or mask work
 * right to the product. RDA reserves the right to make changes in the
 * software without notification.  RDA also make no representation or
 * warranty that such application will be suitable for the specified use
 * without further testing or modification.
 */

#ifndef _OSI_API_H_
#define _OSI_API_H_

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "kernel_config.h"
#include "osi_compiler.h"
#include "osi_vsmap.h"
#include "osi_clock.h"

#ifdef __cplusplus
extern "C" {
#endif

#define OSI_WAIT_FOREVER (-1U)
#define OSI_DELAY_MAX (-1U)

/**
 * Special value to indicate timer callback will be invoked in
 * timer ISR.
 */
#define OSI_TIMER_IN_ISR ((osiThread_t *)NULL)

/**
 * Special value to indicate timer callback will be invoked in
 * timer service thread.
 */
#define OSI_TIMER_IN_SERVICE ((osiThread_t *)0xffffffff)

/**
 * reserved event id to indicate quit event loop
 */
#define OSI_EVENT_ID_QUIT (8)

/**
 * elapsed timer for couting elapsed time
 */
typedef uint32_t osiElapsedTimer_t;

/**
 * opaque data structure for timer
 */
typedef struct osiTimer osiTimer_t;

/**
 * opaque data structure for timer pool
 */
typedef struct osiTimerPool osiTimerPool_t;

/**
 * opaque data structure for thread
 */
typedef struct osiThread osiThread_t;

/**
 * opaque data structure for message queue
 */
typedef struct osiMessageQueue osiMessageQueue_t;

/**
 * opaque data structure for event queue
 *
 * Event queue is just a message queue, and the message is \p osiEvent_t
 * (event itself rather than pointer).
 */
typedef struct osiEventQueue osiEventQueue_t;

/**
 * opaque data structure for mutex
 */
typedef struct osiMutex osiMutex_t;

/**
 * opaque data structure for semaphore
 */
typedef struct osiSemaphore osiSemaphore_t;

/**
 * opaque data structure for work
 */
typedef struct osiWork osiWork_t;

/**
 * opaque data structure for work queue
 */
typedef struct osiWorkQueue osiWorkQueue_t;

/**
 * opaque data structure for thread notify
 */
typedef struct osiNotify osiNotify_t;

/**
 * function type of callback
 */
typedef void (*osiCallback_t)(void *ctx);

/**
 * function type of thread entry
 */
typedef void (*osiThreadEntry_t)(void *argument);

/**
 * function type of interrupt handler
 */
typedef void (*osiIrqHandler_t)(void *ctx);

/**
 * event, with ID and 3 parameters
 */
typedef struct osiEvent
{
    uint32_t id;     ///< event identifier
    uint32_t param1; ///< 1st parameter
    uint32_t param2; ///< 2nd parameter
    uint32_t param3; ///< 3rd parameter
} osiEvent_t;

/**
 * thread priority
 *
 * The definition is independent of implementation. Though some
 * implementation will use larger value for higher priority and
 * others will use smaller value for highe priority, this enum will
 * use larger value for higher priority.
 *
 * \p OSI_PRIORITY_IDLE and \p OSI_PRIORITY_HISR are reserved, can't
 * be used.
 *
 * The definition is the same as CMSIS-RTOS.
 */
typedef enum osiThreadPriority
{
    OSI_PRIORITY_IDLE = 1, // reserved
    OSI_PRIORITY_LOW = 8,
    OSI_PRIORITY_BELOW_NORMAL = 16,
    OSI_PRIORITY_NORMAL = 24,
    OSI_PRIORITY_ABOVE_NORMAL = 32,
    OSI_PRIORITY_HIGH = 40,
    OSI_PRIORITY_REALTIME = 48,
    OSI_PRIORITY_HISR = 56, // reserved
} osiThreadPriority_t;

/**
 * suspend mode
 *
 * System behavior of suspend modes will be diffrent among underlay
 * platform. Driver shall take care the difference, and most likely
 * application won't take care it.
 */
typedef enum osiSuspendMode
{
    OSI_SUSPEND_PM1, ///< 1st level suspend mode
    OSI_SUSPEND_PM2  ///< 2nd level suspend mode
} osiSuspendMode_t;

/**
 * resume wakeup source
 *
 * Resume wakeup source depends on platform. They should be defined in
 * \p hal_chip.h. One bit indicates one source, and multiple sources are
 * possible. \p OSI_RESUME_ABORT is reserved to indicate suspend is
 * aborted.
 */
typedef enum osiResumeSource
{
    OSI_RESUME_ABORT = (1 << 31), ///< resume by suspend aborted
} osiResumeSource_t;

/**
 * \brief boot cause
 *
 * This list is for cold boot cause. Though it is rare, it is possible
 * there exist multiple boot causes simultanuously.
 *
 * Usually boot cause is determined from hardware status registers.
 */
typedef enum osiBootCause
{
    OSI_BOOTCAUSE_UNKNOWN = 0,           ///< placeholder for unknown reason
    OSI_BOOTCAUSE_PWRKEY = (1 << 0),     ///< boot by power key
    OSI_BOOTCAUSE_PIN_RESET = (1 << 1),  ///< boot by pin reset
    OSI_BOOTCAUSE_ALARM = (1 << 2),      ///< boot by alarm
    OSI_BOOTCAUSE_CHARGE = (1 << 3),     ///< boot by charge in
    OSI_BOOTCAUSE_WDG = (1 << 4),        ///< boot by watchdog
    OSI_BOOTCAUSE_PIN_WAKEUP = (1 << 5), ///< boot by wakeup
    OSI_BOOTCAUSE_PSM_WAKEUP = (1 << 6), ///< boot from PSM wakeup
    /*+\NEW\zhuwangbin\2020.04.04\区分软件重启和reset按键重启*/
    OSI_BOOTCAUSE_RESET = (1 << 7),   
    /*-\NEW\zhuwangbin\2020.04.04\区分软件重启和reset按键重启*/
} osiBootCause_t;

/**
 * boot mode
 *
 * Besides normal boot, there are several other boot modes. For each
 * platform, not all boot modes are supported.
 *
 * Usually, boot mode can be determined by hardware (for example, some
 * GPIO) or software (for example, by flags written at \p osiShutdown).
 */
typedef enum osiBootMode
{
    OSI_BOOTMODE_NORMAL = 0,           ///< normal boot
    OSI_BOOTMODE_DOWNLOAD = 0x444e,    ///< 'DN' boot to download mode
    OSI_BOOTMODE_CALIB = 0x434c,       ///< 'CL' boot to calibration mode
    OSI_BOOTMODE_CALIB_POST = 0x4350,  ///< 'CP' boot to calibration post mode
    OSI_BOOTMODE_NB_CALIB = 0x4e43,    ///< 'NC' boot to NB calibration mode
    OSI_BOOTMODE_BBAT = 0x4241,        ///< 'BA' boot to BBAT mode
    OSI_BOOTMODE_UPGRADE = 0x4654,     ///< 'FT' boot to bootloader upgrade
    OSI_BOOTMODE_PSM_RESTORE = 0x5053, ///< 'PS' boot to PSM restore
} osiBootMode_t;

/**
 * shudown mode
 *
 * For each platform, not all shutdown modes are supported.
 */
typedef enum osiShutdownMode
{
    OSI_SHUTDOWN_RESET = 0,               ///< normal reset
    OSI_SHUTDOWN_FORCE_DOWNLOAD = 0x5244, ///< 'RD' reset to force download mode
    OSI_SHUTDOWN_DOWNLOAD = 0x444e,       ///< 'DN' reset to download mode
    OSI_SHUTDOWN_CALIB_MODE = 0x434c,     ///< 'CL' reset to calibration mode
    OSI_SHUTDOWN_NB_CALIB_MODE = 0x4e43,  ///< 'NC' reset to NB calibration mode
    OSI_SHUTDOWN_BBAT_MODE = 0x4241,      ///< 'BA' reset to BBAT mode
    OSI_SHUTDOWN_UPGRADE = 0x4654,        ///< 'FT' reset to upgrade mode
    OSI_SHUTDOWN_POWER_OFF = 0x4f46,      ///< 'OF' power off
    OSI_SHUTDOWN_PSM_SLEEP = 0x5053,      ///< 'PS' power saving mode
} osiShutdownMode_t;

/**
 * PSM data owner
 */
typedef enum osiPsmDataOwner
{
    OSI_PSMDATA_OWNER_KERNEL,     ///< kernel
    OSI_PSMDATA_OWNER_STACK,      ///< stack
    OSI_PSMDATA_OWNER_AT,         ///< AT engine
    OSI_PSMDATA_OWNER_USER = 100, ///< start owner for user application
} osiPsmDataOwner_t;

/**
 * shuwdown callback function type
 *
 * Before shutdown, the registered callbacks will be invokes. The callbacks
 * are executed in system high priority work queue, and with interrupt
 * disabled. So, the callbacks shouldn't rely on system high priority work
 * queue and interrupts. However, thread schedule is still working and
 * multi-thread can work still.
 */
typedef void (*osiShutdownCallback_t)(void *ctx, osiShutdownMode_t mode);

/**
 * invoke global constructors
 *
 * Global constructors are not called during boot. Rather, they will be called
 * in \p osiInvokeGlobalCtors, and it shall be called in \p osiAppStart.
 *
 * At \p osiAppStart, RTOS is ready. So, it is permitted to call more OSI
 * APIs at global constructors.
 *
 * Though global constructors are supported. It is not encouraged to use this
 * feature. Only use this feature when you really know what you are doing.
 */
void osiInvokeGlobalCtors(void);

/**
 * kernel start
 *
 * Start the kernel. This API will create system threads (at least,
 * idle thread) and start thread scheduler. So, it won't return.
 *
 * Before \p osiKernelStart is called, kernel data structure may be
 * uninitialized, and many osi APIs can be called. Including
 *
 * - timer
 * - IRQ
 * - power management
 */
OSI_NO_RETURN void osiKernelStart(void);

/**
 * suspend thread scheduler
 *
 * After scheduler is suspended, there are no thread context switch.
 * However, interrupt handlers will be executed.
 *
 * The meaning of return flag depends on underlay RTOS. Don't assume the
 * meaning of the return value.
 *
 * \return  scheduler suspend flag.
 */
uint32_t osiSchedulerSuspend(void);

/**
 * resume thread scheduler
 *
 * Scheduler suspend and resume is not *recursive*. That is, after
 * \p osiSchedulerResume is called, scheduler is resumed no matter
 * how many times \p osiSchedulerSuspend are called.
 *
 * \param [in] flag     scheduler suspend flag returned by the latest
 *                      \p osiSchedulerSuspend
 */
void osiSchedulerResume(uint32_t flag);

/**
 * \brief enter critical section
 *
 * The underlay RTOS may have different implementation for critical
 * section. It may manipulate CPU IRQ enable bit(s), or manipulate
 * IRQ mask.
 *
 * This can be called in ISR.
 *
 * \return  critical section flags
 */
uint32_t osiEnterCritical(void);

/**
 * \brief exit critical section
 *
 * Critical section flags is implementation depend. It should be the value
 * returned by \p osiEnterCritical, and don't change the value manually.
 *
 * Critical section is *recursive*. That is, after \p osiExitCritical is
 * called, it doesn't mean system will enter *unprotected* state. Rather,
 * it will return to state before last call of \p osiEnterCritical.
 * For example:
 *
 * \code{.cpp}
 * uint32_t critical1 = osiEnterCritical();
 * uint32_t critical2 = osiEnterCritical();
 * // ...
 * osiExitCritical(critical2);
 * osiExitCritical(critical1);
 * \endcode
 *
 * After the first call of \p osiExitCritical, system is in *protected*
 * state still.
 *
 * In recursive, the exit order must be the reverse order of enter. For
 * example, the following codes are wrong:
 *
 * \code{.cpp}
 * uint32_t critical1 = osiEnterCritical();
 * uint32_t critical2 = osiEnterCritical();
 * // ...
 * osiExitCritical(critical1);
 * osiExitCritical(critical2);
 * \endcode
 *
 * This can be called in ISR.
 *
 * \param critical  critical section flags
 */
void osiExitCritical(uint32_t critical);

/**
 * \brief get IRQ flags and disable IRQ
 *
 * This will always manipulate CPU IRQ enable bit(s).
 *
 * After this call, \p osiEnterCritical can't be called. When
 * \p osiEnterCritical manipulates IRQ mask, it is very possible that
 * it will change CPU IRQ enable bit(s) without protection.
 *
 * In most cases, \p osiIrqSave and \p osiIrqRestore shouldn't be
 * used, unless you really know what you are doing.
 *
 * \return  IRQ flags before disable IRQ
 */
uint32_t osiIrqSave(void);

/**
 * \brief restore IRQ flags
 *
 * IRQ flags is arch and implementation depend. It should be the value
 * returned by \p osiIrqSave, and don't change the value manually.
 *
 * \param flags IRQ flags
 */
void osiIrqRestore(uint32_t flags);

/**
 * set interrupt handler
 *
 * When interrupt arrived, the registered handler will be called with
 * the registered context pointer.
 *
 * For each interrupt, only one handler can be registered. When a handler
 * is already registered for an interrupt, \p osiIrqSetHandler will
 * replace the old one.
 *
 * \p irqn depends on interrupt controller in system. When GIC is used,
 * it is the number in GIC.
 *
 * \param irqn      IRQ number
 * \param handler   IRQ handler
 * \param ctx       IRQ handler context pointer
 * \return
 *      - true on success
 *      - false on invalid parameters
 */
bool osiIrqSetHandler(uint32_t irqn, osiIrqHandler_t handler, void *ctx);

/**
 * enable interrupt
 *
 * \param irqn      IRQ number
 * \return
 *      - true on success
 *      - false on invalid parameters
 */
bool osiIrqEnable(uint32_t irqn);

/**
 * disable interrupt
 *
 * \param irqn      IRQ number
 * \return
 *      - true on success
 *      - false on invalid parameters
 */
bool osiIrqDisable(uint32_t irqn);

/**
 * whether interrupt is enabled
 *
 * \param irqn      IRQ number
 * \return
 *      - true if interrupt is enabled
 *      - false if interrupt is disabled
 */
bool osiIrqEnabled(uint32_t irqn);

/**
 * set interrupt priority
 *
 * \p priority depends on interrupt controller used on system. When GIC
 * is used, \p priority should follow GIC requirement and meaning.
 *
 * \param irqn      IRQ number
 * \param priority  IRQ priority
 * \return
 *      - true on success
 *      - false on invalid parameters
 */
bool osiIrqSetPriority(uint32_t irqn, uint32_t priority);

/**
 * get interrupt priority
 *
 * When \p irqn is invalid, 0x80000000U will be returned.
 *
 * \param irqn      IRQ number
 * \return      IRQ priority
 */
uint32_t osiIrqGetPriority(uint32_t irqn);

/**
 * check whether there are pending interrupt
 *
 * This is for special purpose. It shall be called with interrupt disabled
 * (not masked off).
 *
 * This may be unimplemented in some chips.
 *
 * \return
 *      - true if there are interrupt pending.
 */
bool osiIrqPending(void);

/**
 * enable D-cache
 *
 * Usually, it shouldn't be called in application. It will only be called
 * once in boot code.
 *
 * Not all platforms implement this API.
 */
void osiDCacheEnable(void);

/**
 * disable D-cache
 *
 * Usually, it shouldn't be called in application. And most likely it will
 * never be called. It is provided for completeness.
 *
 * Not all platforms implement this API.
 */
void osiDCacheDisable(void);

/**
 * enable I-cache
 *
 * Usually, it shouldn't be called in application. It will only be called
 * once in boot code.
 *
 * Not all platforms implement this API.
 */
void osiICacheEnable(void);

/**
 * disable I-cache
 *
 * Usually, it shouldn't be called in application. And most likely it will
 * never be called. It is provided for completeness.
 *
 * Not all platforms implement this API.
 */
void osiICacheDisable(void);

/**
 * clean (write back) D-cache
 *
 * Usually it shall be called **before** the cachable memory will be read by
 * not cache coherent hardware.
 *
 * D-cache clean will operate by cache line. So, is the memory range is
 * not cache line aligned, other memory on the cache line will be cleaned
 * also. For example, assuming D-cache line size is 32 byte,
 * \p osiDCacheClean((void *)8, 32) will clean [0-8], [40-64] also.
 *
 * When D-cache coherence is needed to be considered, it is recommended to
 * declare or allocate memory by the following:
 *
 * \code{.cpp}
 * char mem1[SIZE] OSI_CACHE_LINE_ALIGNED;
 * void *mem2 = memalign(CONFIG_CACHE_LINE_SIZE, size);
 * \endcode
 *
 * \param address   starting address to be cleaned
 * \param size      size to be cleaned
 */
void osiDCacheClean(const void *address, size_t size);

/**
 * invalidate D-cache
 *
 * Usually it shall be called **before** the cachable memory will be write by
 * not cache coherent hardware.
 *
 * D-cache line alignment is very important for \p osiDCacheInvalidate.
 * Otherwise, other memory on the cache line will be changed randomly.
 *
 * \param address   starting address to be cleaned
 * \param size      size to be cleaned
 */
void osiDCacheInvalidate(const void *address, size_t size);

/**
 * clean and invalidate D-cache
 *
 * \param address   starting address to be cleaned
 * \param size      size to be cleaned
 */
void osiDCacheCleanInvalidate(const void *address, size_t size);

/**
 * invalidate D-cache range
 *
 * \param address   starting address to be cleaned
 * \param size      size to be cleaned
 */
void osiICacheInvalidate(const void *address, size_t size);

/**
 * sync D-cahce with I-cache
 *
 * It shall be called after code memory is operated as data (such as,
 * copy codes from flash to RAM).
 *
 * \param address   starting address to be cleaned
 * \param size      size to be cleaned
 */
void osiICacheSync(const void *address, size_t size);

/**
 * clean all D-cache
 */
void osiDCacheCleanAll(void);

/**
 * invalidate all D-cache
 */
void osiDCacheInvalidateAll(void);

/**
 * clean and invalidate all D-cache
 */
void osiDCacheCleanInvalidateAll(void);

/**
 * invalidate all I-cache
 */
void osiICacheInvalidateAll(void);

/**
 * sync D-cahce with I-cache for all
 */
void osiICacheSyncAll(void);

/**
 * create a thread
 *
 * Each \p osiThread_t will have an event queue. So, the event queue
 * depth should be specified at creation.
 *
 * \p name will be copied to thread control block. So, \p name can be dynamic
 * memory.
 *
 * After a thread is created, it will be executed immediately. So, it is
 * possible that \p entry will be executed before the return value is
 * assigned to some variable, if the new thread priority is higher than
 * current thread priority. Pay attention to use thread pointer in
 * \p entry.
 *
 * \code{.cpp}
 * void entry(void *argument) {
 *     osiThread_t *thread = osiThreadCurrent();
 *     for (;;) {
 *         osiEvent_t event = {};
 *         osiEventWait(thread, &event);
 *         ......
 *     }
 * }
 * \endcode
 *
 * In some underlay RTOS, there are limitation on maximum stack size.
 * For example, when \p configSTACK_DEPTH_TYPE is defined as \p uint16_t,
 * the stack size must be less than 64KB*4.
 *
 * \param name      thread name
 * \param entry     thread entry function
 * \param argument  thread entry function argument
 * \param priority  thread priority
 * \param stack_size    thread stack size in byte
 * \param event_count   thread event queue depth (count of events can be hold)
 * \return
 *      - thread pointer
 *      - NULL if failed
 */
osiThread_t *osiThreadCreate(const char *name, osiThreadEntry_t entry, void *argument,
                             uint32_t priority, uint32_t stack_size,
                             uint32_t event_count);

/*+\new\rww\2020.4.14\添加线程创建接口*/
osiThread_t *osiThreadCreateNotSuspendScheduler(const char *name, osiCallback_t func, void *argument,
										uint32_t priority, uint32_t stack_size,
										uint32_t event_count);
/*-\new\rww\2020.4.14\添加线程创建接口*/

/**
 * create a thread with specified stack
 *
 * It is similar to \p osiThreadCreate, and the stack won't be dynamic created.
 * Rather, the specified buffer \p stack will be used at the stack of the
 * thread. Typical usage is to create performance sensitive thread, and set stack
 * in SRAM to improve performance.
 *
 * Application should always use \p osiThreadCreate. It may be unimplemented on
 * some platforms.
 *
 * \param name      thread name
 * \param entry     thread entry function
 * \param argument  thread entry function argument
 * \param priority  thread priority
 * \param stack     thread stack buffer, must be valid
 * \param stack_size    thread stack size in byte
 * \param event_count   thread event queue depth (count of events can be hold)
 * \return
 *      - thread pointer
 *      - NULL if failed
 */
osiThread_t *osiThreadCreateWithStack(const char *name, osiThreadEntry_t entry, void *argument,
                                      uint32_t priority, void *stack, uint32_t stack_size,
                                      uint32_t event_count);

/**
 * get event queue of thread
 *
 * When \p thread is NULL, return the event queue of current thread.
 *
 * \param thread    thread pointer
 * \return      event queue of the thread
 */
osiEventQueue_t *osiThreadEventQueue(osiThread_t *thread);

/**
 * get current thread pointer
 *
 * \return      current thread pointer
 */
osiThread_t *osiThreadCurrent(void);

/**
 * set whether current thread need FPU
 *
 * By default, FPU isn't permitted for new created thread. To enable FPU,
 * \p osiThreadSetFPUEnabled(true) should be called before floating point
 * instructions.
 *
 * Though it is possible to call \p osiThreadSetFPUEnabled(false) if it is
 * known that floating point instructions won't be used any more, it is not
 * necessary. It will only increase a little context save and restore cycles.
 * Typical usage it to call \p osiThreadSetFPUEnabled(true) at the beginning
 * of thread entry.
 *
 * It is undefined if thread uses floating point instructions whthout call
 * of \p osiThreadSetFPUEnabled(true).
 *
 * \param enabled   true for enable FPU, false for disable FPU.
 */
void osiThreadSetFPUEnabled(bool enabled);

/**
 * get thread priority
 *
 * When \p thread is NULL, return the priotity of current thread.
 *
 * \param thread    thread pointer
 * \return      priotity of the thread
 */
uint32_t osiThreadPriority(osiThread_t *thread);

/**
 * set thread priority
 *
 * When \p thread is NULL, set the priotity of current thread.
 *
 * After the priority changed, it is possible thread context switch
 * will occur. However, don't depend on this feature.
 *
 * \param thread    thread pointer
 * \param priority  priority to be set
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiThreadSetPriority(osiThread_t *thread, uint32_t priority);

/**
 * suspend a thread
 *
 * When \p thread is NULL, suspend current thread.
 *
 * \param thread    thread pointer
 */
void osiThreadSuspend(osiThread_t *thread);

/**
 * resume a thread
 *
 * \p thread can't be NULL.
 *
 * \param thread    thread pointer
 */
void osiThreadResume(osiThread_t *thread);

/**
 * current thread yield
 *
 * When there are threads with the same priority, other threads will
 * be scheduled.
 */
void osiThreadYield(void);

/**
 * current thread sleep
 *
 * Change current thread into sleep mode, and will be rescheduled
 * after the specified period.
 *
 * This will use the underlay RTOS mechanism. It is possible the sleep
 * time precision is the tick of underlay RTOS.
 *
 * \param ms        sleep time in milliseconds
 */
void osiThreadSleep(uint32_t ms);

/**
 * current thread sleep with relaxed timeout
 *
 * It is a power optimization version of \p osiThreadSleep. Due to power
 * saving, it is possible that current thread will be wakeup later then
 * *normal timeout*, but it will wakeup no later than *relaxed timeout*
 * even system will enter suspend.
 *
 * When \p relax_ms is \p OSI_DELAY_MAX, it means it can be ignored
 * completed for power saving. However, after system is awoken, the thread
 * will be wakeup still if the *normal timeout* is expired.
 *
 * \param ms        sleep time in milliseconds
 * \param relax_ms  relaxed sleep time in milliseconds
 */
void osiThreadSleepRelaxed(uint32_t ms, uint32_t relax_ms);

/**
 * thread stack unused space
 *
 * It needs underlay RTOS support. When the underlay RTOS doesn't support
 * this feature, it returns 0.
 *
 * The typical method to support this feature in underlay RTOS is to check
 * stack content, and comparing with preset magic byte or word.
 *
 * It is recommended to use it only for debug.
 *
 * \param thread    thread pointer, NULL for current thread
 * \return
 *      - thread stack unused space in bytes
 *      - 0 if the underlay RTOS doesn't support this feature
 */
uint32_t osiThreadStackUnused(osiThread_t *thread);

/**
 * space from current stack pointer to current thread stack end
 *
 * When \p refill is true, the current stack space will be fill with magic
 * byte or word for measuring unused stack. When underlay RTOS doesn't
 * support feature to measure stack remain, \p refill will be ignored.
 *
 * It is recommended to use it only for debug.
 *
 * \return
 *      - space to current thread stack end, in bytes
 */
uint32_t osiThreadStackCurrentSpace(bool refill);

/**
 * current thread exit
 *
 * When a thread is finished, \p osiThreadExit must be called. And
 * kernel will release thread resources at appropriate time.
 */
OSI_NO_RETURN void osiThreadExit(void);

/**
 * show thread information through trace
 *
 * It is for debug purpose only.
 */
void osiShowThreadState(void);

/**
 * send an event to a thread
 *
 * At send, the body of \p event will be copied to event queue
 * rather then send the pointer of \p event.
 *
 * When event queue of the target thread is full, the caller thread
 * will be block until there are rooms in target thread event queue.
 *
 * \param thread    thread pointer, can't be NULL
 * \param event     event to be sent
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiEventSend(osiThread_t *thread, const osiEvent_t *event);

/**
 * send event loop quit event to a thread
 *
 * This is the normalized method to notify a thread to quit. When \p thread
 * is the current thread, \p wait can't be true.
 *
 * \code{.cpp}
 *     // caller thread
 *     osiSendQuitEvent(thread);
 *
 *     // thread to quit
 *     for (;;) {
 *         osiEvent_t event = {};
 *         osiEventWait(thread, &event);
 *         if (event.id == OSI_EVENT_ID_QUIT)
 *             break;
 *
 *         // ......
 *     }
 *     osiThreadExit();
 * \endcode
 *
 * \param thread    thread pointer, can't be NULL
 * \param wait      whether to wait thread exit
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiSendQuitEvent(osiThread_t *thread, bool wait);

/**
 * send an event to a thread with timeout
 *
 * When \p timeout is 0, this will return false immediately. When \p timeout
 * is \p OSI_WAIT_FOREVER, this will wait forever until there are
 * rooms in target thread event queue.
 *
 * This can be called in ISR. And in ISR, \p timeout must be 0.
 *
 * \param thread    thread pointer, can't be NULL
 * \param event     event to be sent
 * \param timeout   timeout in milliseconds
 * \return
 *      - true on success
 *      - false on invalid parameter, or timeout
 */
bool osiEventTrySend(osiThread_t *thread, const osiEvent_t *event, uint32_t timeout);

/**
 * wait an event
 *
 * Wait an event from current thread event queue. When current thread
 * event queue is empty, it will be blocked forever until there are
 * event in event queue.
 *
 * The event body will be copied to \p event.
 *
 * There are some event ID used by system. After system event is received
 * and process, this will return an event with ID of 0. Application can
 * ignore event ID 0 safely.
 *
 * \param thread    thread pointer, can't be NULL
 * \param event     event pointer
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiEventWait(osiThread_t *thread, osiEvent_t *event);

/**
 * wait an event with timeout
 *
 * When \p timeout is 0, this will return false immediately. When \p timeout
 * is \p OSI_WAIT_FOREVER, this will wait forever until there are
 * events in target thread event queue.
 *
 * \param thread    thread pointer, can't be NULL
 * \param event     event pointer
 * \param timeout   timeout in milliseconds
 * \return
 *      - true on success
 *      - false on invalid parameter, or timeout
 */
bool osiEventTryWait(osiThread_t *thread, osiEvent_t *event, uint32_t timeout);

/**
 * whether there are pending event in event queue
 *
 * \param thread    thread pointer, can't be NULL
 * \return
 *      - true if there are pending event
 *      - false if not
 */
bool osiEventPending(osiThread_t *thread);

/**
 * set callback to be executed on thread
 *
 * Thread callback is implemented by \p osiEvent_t.
 *
 * This can be called in ISR. In ISR, the callback event will be lost when
 * the event queue of target thread is full.
 *
 * \param thread    thread pointer, can't be NULL
 * \param cb        callback to be executed
 * \param cb_ctx    callback context
 * \return
 *      - true on success
 *      - false on invalid parameter, or event queue is full in ISR
 */
bool osiThreadCallback(osiThread_t *thread, osiCallback_t cb, void *cb_ctx);

/**
 * \brief create a work
 *
 * \p run can't be NULL, and \p complete can be NULL.
 *
 * \param run       execute function of the work
 * \param complete  callback to be invoked after the work is finished
 * \param ctx       context of \p run and \p complete
 * \return
 *      - the created work
 *      - NULL if invalid parameter or out of memory
 */
osiWork_t *osiWorkCreate(osiCallback_t run, osiCallback_t complete, void *ctx);

/**
 * \brief delete the work
 *
 * When \p work is running when it is called, it will be deleted after the
 * current run finished.
 *
 * \param work      the work to be deleted
 */
void osiWorkDelete(osiWork_t *work);

/**
 * \brief enqueue a work in specified work queue
 *
 * When \p work is running, it will be queued to \wq again and then it
 * will be invoked again.
 *
 * When \p work is queued, and \p wq is the same as original work queue,
 * nothing will be done. When \p wq is not the same as the original
 * work queue, it will be removed from the original work queue, and
 * queue the work into the specified work queue.
 *
 * This can be called in ISR.
 *
 * \param work      the work pointer, must be valid
 * \param wq        work queue to run the work, must be valid
 * \return
 *      - true on success
 *      - false for invalid parameter, or work is running
 */
bool osiWorkEnqueue(osiWork_t *work, osiWorkQueue_t *wq);

/**
 * \brief enqueue a work in the last of specified work queue
 *
 * It is similar to \p osiWorkEnqueue, except it will consider work order.
 * For example:
 *
 * \code{.cpp}
 *      osiWorkEnqueue(work1, wq);
 *      osiWorkEnqueue(work2, wq);
 *      osiWorkEnqueue(work1, wq);
 * \encode
 *
 * If work queue is busy on another work during these calls, and when work
 * queue processing these works, it will:
 * - execute work1->callback
 * - execute work2->callback
 *
 * So, even the order of works aren't preserved. \p work1 is the last queued
 * work, and the real last executed work is \p work2.
 *
 * With \p osiWorkEnqueueLast, it will ensure that the last queued work will
 * be executed at the last.
 *
 * \param work      the work pointer, must be valid
 * \param wq        work queue to run the work, must be valid
 * \return
 *      - true on success
 *      - false for invalid parameter, or work is running
 */
bool osiWorkEnqueueLast(osiWork_t *work, osiWorkQueue_t *wq);

/**
 * \brief cancel a work
 *
 * When \p work is running, the current execution won't be interrupted.
 *
 * \param work      the work pointer, must be valid
 */
void osiWorkCancel(osiWork_t *work);

/**
 * \brief wait a work finish
 *
 * When \p work is running or enqued, this will wait the work finish.
 * When \p timeout is 0, it will return immediately. When \p timeout
 * is \p OSI_WAIT_FOREVER, it will wait infinitely until the work is
 * finished.
 *
 * \param work      the work pointer, must be valid
 * \param timeout   wait timeout
 * \return
 *      - true if the work is finished
 *      - false on invalid parameter, or wait timeout
 */
bool osiWorkWaitFinish(osiWork_t *work, unsigned timeout);

/**
 * \brief create work queue
 *
 * Multiple threads can be created to reduce work execution latency. For
 * example, when one thread in a work queue is blocked, other threads of
 * the work queue can execute other works queued to the work queue.
 *
 * The maximum thread count is implementation dependent. So, it is possible
 * that the created thread count is less than \p thread_count. And also it is
 * possible that \p thread_count is ignored.
 *
 * The created threads have the same priority and stack size.
 *
 * The work queue thread entry function can't be customized
 *
 * \param name      work queue name
 * \param thread_count  thread count to be created for the work queue
 * \param priority  work queue thread priority
 * \param stack_size    thread stack size in byte
 * \return
 *      - the work queue pointer
 *      - NULL if failed
 */
osiWorkQueue_t *osiWorkQueueCreate(const char *name, size_t thread_count, uint32_t priority, uint32_t stack_size);

/**
 * \brief delete work queue
 *
 * All resources of the work queue will be deleted.
 *
 * The works in running will continue, and \p complete will be invoked as
 * normal. However, queued work in the work queue won't be executed any more.
 *
 * \param wq    work queue to be deleted
 */
void osiWorkQueueDelete(osiWorkQueue_t *wq);

/**
 * \brief get the system high priority work queue
 *
 * A work queue with priority \p OSI_PRIORITY_HIGH will be created at kernel
 * start.
 *
 * \return  the system high priority work queue
 */
osiWorkQueue_t *osiSysWorkQueueHighPriority(void);

/**
 * \brief get the system low priority work queue
 *
 * A work queue with priority \p OSI_PRIORITY_LOW will be created at kernel
 * start.
 *
 * \return  the system low priority work queue
 */
osiWorkQueue_t *osiSysWorkQueueLowPriority(void);

/**
 * \brief get the system work queue for asynchronuous file system write
 *
 * A work queue with priority \p OSI_PRIORITY_BELOW_NORMAL will be created
 * at kernel start. This work queue shall be used for asynchronuous file
 * system write.
 *
 * Usually file write is slow, especially for file system on NOR flash.
 * When faster response is needed, file write can be deferred to this
 * work queue. Also, the work queue will be flushed before system shutdown.
 *
 * \return  the system file write work queue
 */
osiWorkQueue_t *osiSysWorkQueueFileWrite(void);

/**
 * \brief create a thread notify
 *
 * Thread notify is thread callback with state to avoid duplicated event
 * to be sent to thread event queue.
 *
 * \param thread    thread to execute the callback, can't be NULL
 * \param cb        callback to be executed, can't be NULL
 * \param ctx       callback context
 * \return
 *      - created notify
 *      - NULL if parameters are invalid or out of memory
 */
osiNotify_t *osiNotifyCreate(osiThread_t *thread, osiCallback_t cb, void *ctx);

/**
 * \brief delete a thread notify
 *
 * The memory of the thread notify will be released.
 *
 * When the thread notify is already in thread event queue, the callback
 * won't be invoked, and the memory may be released delayed.
 *
 * \param notify    thread notify pointer, must be valid
 */
void osiNotifyDelete(osiNotify_t *notify);

/**
 * \brief trigger a thread notify
 *
 * When the thread notify event isn't in thread event queue, an event for
 * thread notify will be queued to the tail of thread event queue.
 *
 * \param notify    thread notify pointer, must be valid
 */
void osiNotifyTrigger(osiNotify_t *notify);

/**
 * \brief cancel a thread notify
 *
 * When the thread notify event has already sent to thread event queue,
 * the invocation of the callback will be cancelled.
 *
 * \param notify    thread notify pointer, must be valid
 */
void osiNotifyCancel(osiNotify_t *notify);

/**
 * \brief create a timer
 *
 * Create a timer with specified callback and callback context. After create,
 * the timer is in stop state. Application can start it in various mode.
 *
 * When \p thread is \p OSI_TIMER_IN_ISR, the callback will be executed in
 * timer ISR. So, the callback should follow ISR programming guide. This is
 * **not** recommended unless it is absolutely needed.
 *
 * When \p thread is \p OSI_TIMER_IN_SERVICE, the callback will be executed
 * in timer service thread.
 *
 * Otherwise, the callback will be executed in the specified thread through
 * *event* mechanism.
 *
 * It is needed to call \p osiTimerDelete to free resources.
 *
 * \param thread    thread to execute the callback
 * \param cb        callback to be executed after timer expire
 * \param ctx       callback context
 * \return
 *      - the created timer instance
 *      - NULL at out of memory, or invalid parameter
 */
osiTimer_t *osiTimerCreate(osiThread_t *thread, osiCallback_t cb, void *ctx);

/**
 * \brief create a timer, enqueue a work on expiration
 *
 * Create a timer with specified callback and callback context. After create,
 * the timer is in stop state. Application can start it in various mode.
 *
 * At expiration, \p work will be enqueued to \p wq.
 *
 * It is needed to call \p osiTimerDelete to free resources.
 *
 * \param work      work to be enqueued at expiration
 * \param wq        work queue to be enqueued at expiration
 * \return
 *      - the created timer instance
 *      - NULL at out of memory, or invalid parameter
 */
osiTimer_t *osiTimerCreateWork(osiWork_t *work, osiWorkQueue_t *wq);

/**
 * \brief create a timer, EV_TIMER on expiration
 *
 * This is for legacy codes only. **Don't** use it except at porting
 * legacy codes.
 *
 * Create a timer with specified timerid. After the timer expired, the
 * specified thread will receive an event { EV_TIMER, timerid, 0, 0}.
 *
 * It is needed to call \p osiTimerDelete to free resources.
 *
 * \param thread    thread to execute the callback, it can't be NULL
 * \param timerid   timerid in expiration event
 * \return
 *      - the created timer instance
 *      - NULL at out of memory, or invalid parameter
 */
osiTimer_t *osiTimerEventCreate(osiThread_t *thread, uint32_t timerid);

/**
 * \brief set/change callback of timer
 *
 * In most cases, timer callback set at create is not needed to be changed.
 *
 * \p timer should be created by \p osiTimerCreate. Special values of
 * \p thread follow \p osiTimerCreate.
 *
 * It is permitted to change \p thread of timer, including special values.
 * For example, it is permitted to change a timer executing in timer service
 * to timer executing in specified thread. However, it is not recommended.
 *
 * This can only be called when \p timer is stopped. Otherwise, it will
 * return false.
 *
 * \param timer     timer to be changed
 * \param thread    thread to execute the callback
 * \param cb        callback to be executed after timer expire
 * \param ctx       callback context
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerSetCallback(osiTimer_t *timer, osiThread_t *thread, osiCallback_t cb, void *ctx);

/**
 * \brief set/change work and work queue of timer
 *
 * In most cases, timer work and work queue set at create is not needed to be changed.
 *
 * \p timer should be created by \p osiTimerCreateWork, to enqueue work to work
 * queue at expiration.
 *
 * \param timer     timer to be changed
 * \param work      work to be enqueued at expiration
 * \param wq        work queue to be enqueued at expiration
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerSetWork(osiTimer_t *timer, osiWork_t *work, osiWorkQueue_t *wq);

/**
 * \brief set/change timer event
 *
 * In most cases, timer thread and id set at create is not needed to be changed.
 *
 * \p timer should be created by \p osiTimerEventCreate.
 *
 * \param thread    thread to execute the callback, it can't be NULL
 * \param timerid   timerid in expiration event
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerSetEvent(osiTimer_t *timer, osiThread_t *thread, uint32_t timerid);

/**
 * \brief delete a timer
 *
 * Delete the timer, and free associated resources.
 *
 * When the timer callback will be executed in thread rather than ISR, and the
 * event for timer expiration has been sent, some resources won't be freed
 * immediately. Rather, they will be freed after the timer expiration event
 * is popped out from thread event queue. However, the callback won't be
 * executed even delete is delayed.
 *
 * Refer to document about corner case of timer thread callback.
 *
 * \param timer     the timer to be deleted
 */
void osiTimerDelete(osiTimer_t *timer);
/**
 * \brief change timer relaxed timeout for running timer
 *
 * When the timer is not running, it will return false.
 *
 * When the timer is started, this will change the relaxed timeout
 * specified at start.
 *
 * This can be called for both one shot timer and periodic timer.
 *
 * \p relaxed_ms is the additional time based on normal timeout. It will
 * only be used for sleep. When \p relaxed_ms is 0, this timer will wakeup
 * system even system enter sleep mode. When \p relaxed_ms is
 * \p OSI_DELAY_MAX, this timer will not wakeup system when system enter
 * sleep mode. Otherwise, system will process the timer no later than the
 * normal timeout plus additional timeout.
 *
 * For example, when the period of a timer is 100ms, and relaxed timeout
 * is 500ms, system will process the timer no later than 600ms. This can
 * make system sleep more time, and reduce power consumption.
 *
 * For periodic timer, the additional timeout is add to normal timeout of
 * earch run. For example, a periodic timer period is 100ms, and relaxed
 * timeout is 50ms, then system will process the timer no later than 150ms.
 * And even the timer is delayed to 150ms due to system sleep, the next
 * timeout is 200ms unchanged. Another example, a periodic timer period
 * is 100ms, and relaxed timeout is 500ms, then system will process the
 * timer no later than 600ms. When the timer is delayed to 600ms due to
 * system sleep, the callback will be invoked only once even 6 periods are
 * elapsed. The next timeout is at 700ms.
 *
 * \param timer         the timer to be set
 * \param relaxed_ms    relaxed timeout in milliseconds
 * \return
 *      - true on success
 *      - false on invalid parameter, or timer is not running
 */
bool osiTimerChangeRelaxed(osiTimer_t *timer, uint32_t relaxed_ms);

/**
 * \brief set timer period for next call
 *
 * The properties will be used by next \p osiTimerStartLast. It can only be
 * called when the timer is not running.
 *
 * It is the same as \p osiTimerSetPeriodRelaxed, with \p relaxed_ms
 * as 0.
 *
 * \param timer     the timer to be set
 * \param ms        period in milliseconds
 * \param periodic  true for periodic, false for one shot
 * \return
 *      - true on success
 *      - false on invalid parameter, or timer is started
 */
bool osiTimerSetPeriod(osiTimer_t *timer, uint32_t ms, bool periodic);

/**
 * \brief set timer period for next call, with relaxed timeout
 *
 * The properties will be used by next \p osiTimerStartLast. It can only be
 * called when the timer is not running.
 *
 * \param timer     the timer to be set
 * \param ms        period in milliseconds
 * \param relaxed   relaxed timeout in milliseconds
 * \param periodic  true for periodic, false for one shot
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerSetPeriodRelaxed(osiTimer_t *timer, uint32_t ms, uint32_t relaxed_ms, bool periodic);

/**
 * \brief whether timer is started
 *
 * \param timer     the timer to be set
 * \return
 *      - true if the timer is started
 *      - false if not started, or invalid parameter
 */
bool osiTimerIsRunning(osiTimer_t *timer);

/**
 * \brief get remaining time of timer in milliseconds
 *
 * Even the timer is already timed out, it will return 0 rather then negative
 * value. For example, thread callback timer is already timed out, but the
 * callback hasn't invoked in the specified thread.
 *
 * \param timer     the timer to be set
 * \return
 *      - remaining time
 *      - timer is not started, or invalid parameter
 */
int64_t osiTimerRemaining(osiTimer_t *timer);

/**
 * \brief timer expiration time in milliseconds
 *
 * The expiration time is in the same coordinate of \p osiUpTime.
 *
 * When the timer is not running, it will return -1. For already timeed out
 * timer, the return value may be smaller than \p osiUpTime.
 *
 * \param timer     the timer to be checked
 * \return
 *      - expiration time
 *      - -1 if the timer is not running
 */
int64_t osiTimerExpiration(osiTimer_t *timer);

/**
 * \brief start a timer with last period
 *
 * The last period is the period set by \p osiTimerSetPeriod, or other start
 * APIs with period parameter.
 *
 * It is recommended that not to mixing start API with period parameter, and
 * start API without period parameter. Though the behavior is determinstic,
 * it is harder to be understood.
 *
 * \param timer     the timer to be started
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStartLast(osiTimer_t *timer);

/**
 * \brief start a timer
 *
 * Start a timer, and the timer will be expired in specified period from
 * now. After the callback is executed, the timer will come to stopped state
 * automatically.
 *
 * When the timer is in stated state before this function, the previous
 * expiration won't be executed.
 *
 * Refer to document about corner case of timer thread callback.
 *
 * It is valid that the timeout period is 0. In this case, the timer will
 * expire very soon.
 *
 * Due to timeout is 32bits of milliseconds, The maximum timeout period is
 * ~50 days.
 *
 * It is the same as \p osiTimerStartRelaxed, with \p relaxed_ms is 0.
 *
 * \param timer     the timer to be started
 * \param ms        timeout period
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStart(osiTimer_t *timer, uint32_t ms);

/**
 * \brief start a timer with relaxed timeout
 *
 * It is a power optimization version of \p osiTimerStart.
 *
 * Refer to \p osiTimerChangeRelaxed for explaination of \p relaxed_ms.
 *
 * \param timer     the timer to be started
 * \param ms        normal timeout period
 * \param relax_ms  relaxed timeout period
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStartRelaxed(osiTimer_t *timer, uint32_t ms, uint32_t relax_ms);

/**
 * \brief start a timer with relaxed timeout, in unit of hardware tick
 *
 * **Don't** call this in application code. It is only for legacy codes.
 *
 * The frequency of hardware tick is chip dependent, and implementation dependent.
 *
 * \param timer     the timer to be started
 * \param ticks     normal timeout period in hardware tick
 * \param relax_ticks   relaxed timeout period in hardware tick
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStartHWTickRelaxed(osiTimer_t *timer, uint32_t ticks, uint32_t relax_ticks);

/**
 * \brief start a timer, timeout in unit of microseconds
 *
 * Timeout in microseconds can support higher precision. However, the maximum
 * timeout is shorter, ~1.2 hours.
 *
 * The real precision depends on hardware.

 * \param timer     the timer to be started
 * \param us        timeout period in microseconds
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStartMicrosecond(osiTimer_t *timer, uint32_t us);

/**
 * \brief start a periodic timer
 *
 * Internally, the period may be aligned to hardware tick (larger than
 * 16384Hz), there may exist accumulated error in long run. So, don't use
 * periodic timer count for long time time, \p osiUpTime is a better choice.
 *
 * When the period of periodic timer is too small, it will have serious impact
 * on system. Internally, the period taking effect will no less than
 * \p CONFIG_KERNEL_PERIODIC_TIMER_MIN_PERIOD.
 *
 * It is the same as \p osiTimerStartPeriodicRelaxed, with \p relaxed_ms is 0.
 *
 * \param timer     the timer to be started
 * \param ms        interval in microseconds
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStartPeriodic(osiTimer_t *timer, uint32_t ms);

/**
 * \brief start a periodic timer with relaxed timeout
 *
 * It is a power optimization version of \p osiTimerStartPeriodic.
 *
 * Refer to \p osiTimerChangeRelaxed for explaination of \p relaxed_ms.
 *
 * \param timer     the timer to be started
 * \param ms        interval in microseconds
 * \param relaxed_ms    relaxed timeout period
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStartPeriodicRelaxed(osiTimer_t *timer, uint32_t ms, uint32_t relaxed_ms);

/**
 * \brief stop a time
 *
 * Stop a not-started or stopped timer is valid, just do nothing.
 *
 * Refer to document about corner case of timer thread callback.
 *
 * \param timer     the timer to be stopped
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiTimerStop(osiTimer_t *timer);

/**
 * \brief tickless light sleep for timer
 *
 * When OS tick is implemented in timer, \p idle_tick is the maximum
 * idle OS tick count (not hardware tick count) for sleep.
 *
 * The timer interrupt will be moved to minimum of:
 * * OS timer, after \p idle_tick
 * * other timers timeout time
 *
 * When there are no timers, timer interrupt will be disabled.
 *
 * The normal timeout time of timer, rather than the relaxed timeout
 * time of timer, will be used.
 *
 * When the timer interrupt is moved, it will return true. In that case,
 * the timer interrupt will be moved back after light sleep.
 *
 * \param idle_tick     OS tick sleep count
 * \return
 *      - true if timer interrupt is moved
 *      = false if timer interrupt is not moved
 */
bool osiTimerLightSleep(uint32_t idle_tick);

/**
 * \brief calculate the deep sleep time of all timers
 *
 * When OS tick is implemented in timer, \p idle_tick is the maximum
 * idle OS tick count (not hardware tick count) for sleep.
 *
 * When there are timers which will wakeup system, the return value is
 * the earliest timer wakeup time from now in milliseconds.
 *
 * When there are no timer will wakeup system, return \p INT64_MAX.
 *
 * The relaxed timeout time of timer, rather than the normal timeout
 * time, is used in checking sleep time.
 *
 * Usually, it will be called by system sleep module. And it is not
 * prohibited to be called in other cases.
 *
 * It **must** be called with interrupt disabled. The implementation
 * won't perform protection.
 *
 * \param idle_tick     OS tick sleep count
 * \return
 *      - the earliest sleep timer from now in milliseconds.
 *        \p INT64_MAX for no need to wakeup.
 */
int64_t osiTimerDeepSleepTime(uint32_t idle_tick);

/**
 * \brief calculate the PSM wakup time of all timers
 *
 * When OS tick is implemented in timer, OS tick is not considered.
 * That is, PSM wont't be waken by OS tick.
 *
 * The there are times which will wakeup system, the return value is
 * the earliest timer wakeup time in milliseconds.
 *
 * When there are no timer will wakeup system, return \p INT64_MAX.
 *
 * The relaxed timeout time of timer, rather than the normal timeout
 * time, is used in checking sleep time.
 *
 * It **must** be called with interrupt disabled. The implementation
 * won't perform protection.
 *
 * \return
 *      - the earliest wakeup timer from now in milliseconds.
 *        \p INT64_MAX for no need to wakeup.
 */
int64_t osiTimerPsmWakeUpTime(void);

/**
 * \brief timer module processing after wakeup
 *
 * In case \p osiUpHWTick will be discontinued at sleep, it should be called
 * after \p osiUpHWTick is stable.
 *
 * Usually, it will be called by system sleep module. And it is not
 * prohibited to be called in other cases.
 *
 * It **must** be called with interrupt disabled. The implementation
 * won't perform protection.
 */
void osiTimerWakeupProcess(void);

/**
 * \brief dump timer information to memory
 *
 * It is for debug only. The data format of timer information dump is
 * not stable, and may change. When the provided memory size is not
 * enough for all timers, some timers will be absent in dump.
 *
 * \param mem       memory for timer information dump
 * \param size      provided memory size
 * \return
 *      - dump memory size
 */
int osiTimerDump(void *mem, unsigned size);

/**
 * create a message queue
 *
 * \param msg_count maximum message count can be hold in queue
 * \param msg_size  size of each message in bytes
 * \return
 *      - message queue pointer
 *      - NULL on invalid parameter or out of memory
 */
osiMessageQueue_t *osiMessageQueueCreate(uint32_t msg_count, uint32_t msg_size);

/**
 * delete a message queue
 *
 * When \p mq is NULL, nothing will be done, just as \p free.
 *
 * \param mq    message queue pointer
 */
void osiMessageQueueDelete(osiMessageQueue_t *mq);

/**
 * put a message to message queue
 *
 * \p msg should hold content size the same as \p msg_size specified at
 * \p osiMessageQueueCreate.
 *
 * After put, the content of \p msg will be copied to message queue.
 *
 * When \p mq is full, it will be blocked until there are rooms.
 *
 * \param mq    message queue pointer
 * \param msg   mesage pointer
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiMessageQueuePut(osiMessageQueue_t *mq, const void *msg);

/**
 * put a message to message queue with timeout
 *
 * This can be called in ISR. And in ISR, \p timeout must be 0.
 *
 * \param mq        message queue pointer
 * \param msg       mesage pointer
 * \param timeout   timeout in milliseconds
 * \return
 *      - true on success
 *      - false on invalid parameter or timeout
 */
bool osiMessageQueueTryPut(osiMessageQueue_t *mq, const void *msg, uint32_t timeout);

/**
 * get a message to message queue
 *
 * \p msg should be able tp hold content size of \p msg_size specified at
 * \p osiMessageQueueCreate.
 *
 * After get, the content of message will be copied to \p msg.
 *
 * When \p mq is empty, it will be blocked until there are messages.
 *
 * \param mq    message queue pointer
 * \param msg   mesage pointer
 * \return
 *      - true on success
 *      - false on invalid parameter
 */
bool osiMessageQueueGet(osiMessageQueue_t *mq, void *msg);

/**
 * get a message to message queue with timeout
 *
 * This can be called in ISR. And in ISR, \p timeout must be 0.
 *
 * \param mq        message queue pointer
 * \param msg       mesage pointer
 * \param timeout   timeout in milliseconds
 * \return
 *      - true on success
 *      - false on invalid parameter or timeout
 */
bool osiMessageQueueTryGet(osiMessageQueue_t *mq, void *msg, uint32_t timeout);

/**
 * create a semaphore
 *
 * When \p max_count is 1, it is a binary semaphore. Otherwise, it is
 * counting semaphore.
 *
 * \param max_count     maximum count of the semaphore
 * \param init_count    initial count of the semaphore
 * \return
 *      - semaphore pointer
 *      - NULL on invalid parameter or out of memory
 */
osiSemaphore_t *osiSemaphoreCreate(uint32_t max_count, uint32_t init_count);

/**
 * delete the semaphore
 *
 * When there are blocked thread on the semaphore, the behavior is undefined
 * for \p osiSemaphoreDelete.
 *
 * \param semaphore     semaphore pointer
 */
void osiSemaphoreDelete(osiSemaphore_t *semaphore);

/**
 * acquire from semaphore
 *
 * After acquire, the count of semaphore will be decreased by 1.
 *
 * When the count of semaphore is 0, it will be blocked until the count
 * becomes non-zero (increased by \p osiSemaphoreRelease).
 *
 * \param semaphore     semaphore pointer
 */
void osiSemaphoreAcquire(osiSemaphore_t *semaphore);

/**
 * acquire from semaphore with timeout
 *
 * This can be called in ISR. And in ISR, \p timeout must be 0.
 *
 * \param semaphore     semaphore pointer
 * \param timeout       timeout in milliseconds
 * \return
 *      - true on success
 *      - false on timeout
 */
bool osiSemaphoreTryAcquire(osiSemaphore_t *semaphore, uint32_t timeout);

/**
 * release to semaphore
 *
 * After release, the count of semaphore will be increased by 1.
 * When there are blocked thread on the semaphore, one of the blocked
 * thread will be unblocked.
 *
 * This can be called in ISR.
 *
 * \param semaphore     semaphore pointer
 */
void osiSemaphoreRelease(osiSemaphore_t *semaphore);

/**
 * create a mutex
 *
 * After creation, the mutex is in *open* state.
 *
 * \return
 *      - mutex pointer
 *      - NULL on out of memory
 */
osiMutex_t *osiMutexCreate(void);

/**
 * delete the mutex
 *
 * When \p mutex is NULL, nothing will be done, just as \p free.
 *
 * \param mutex     mutex pointer to be deleted
 */
void osiMutexDelete(osiMutex_t *mutex);

/**
 * lock the mutex
 *
 * When \p mutex is locked by another thread, it will wait forever
 * until the mutex is unlocked.
 *
 * \param mutex     mutex pointer to be locked
 */
void osiMutexLock(osiMutex_t *mutex);

/**
 * lock the mutex with timeout
 *
 * \param mutex     mutex pointer to be locked
 * \param timeout   timeout in milliseconds
 * \return
 *      - true on success
 *      - false on timeout
 */
bool osiMutexTryLock(osiMutex_t *mutex, uint32_t timeout);

/**
 * unlock the mutex
 *
 * \param mutex     mutex pointer to be unlocked
 */
void osiMutexUnlock(osiMutex_t *mutex);

/**
 * \brief monoclinic system time
 *
 * It is a relative time from system boot. Even after suspend and resume,
 * the monoclinic system time will be contiguous.
 *
 * \return      monoclinic system time in milliseconds
 */
int64_t osiUpTime(void);

/**
 * \brief monoclinic system time in microsecond
 *
 * The monoclinic system time in unit of microsecond.
 *
 * \return      monoclinic system time in microseconds
 */
int64_t osiUpTimeUS(void);

/**
 * \brief set monoclinic system time
 *
 * When it is known that the hardware resource for monoclinic system time
 * is discontinued, such as power off during deep sleep, this is called to
 * set monoclinic system time.
 *
 * When up time is changed, epoch time and local time aren't be changed.
 *
 * It should only be called in system integration.
 *
 * \param ms        target monoclinic system time in microseconds
 */
void osiSetUpTime(int64_t ms);

/**
 * \brief get the epoch time
 *
 * The time is millisecond (1/1000 second) from 1970-01-01 UTC. To avoid
 * overflow, the data type is 64 bits.
 *
 * Epoch time is not monoclinic time. For example, when system time is
 * synchronized with network, there may exist a jump (forward or backward)
 * of epoch time.
 *
 * In 2 cases, this system time may be not reliable:
 * - During boot, and before RTC is initialized.
 * - During wakeup, and the elapsed sleep time hasn't compensated.
 *
 * \return      epoch time in milliseconds
 */
int64_t osiEpochTime(void);

/**
 * \brief get the epoch time in second
 *
 * The time is seconds from 1970-01-01 UTC. To avoid overflow, the data
 * type is 64 bits.
 * - signed 32bits will overflow at year 2038
 * - unsigned 32bits will overflow at year 2106
 *
 * Epoch time is not monoclinic time. For example, when system time is
 * synchronized with network, there may exist a jump (forward or backward)
 * of epoch time.
 *
 * In 2 cases, this system time may be not reliable:
 * - During boot, and before RTC is initialized.
 * - During wakeup, and the elapsed sleep time hasn't compensated.
 *
 * \return      epoch time in seconds
 */
int64_t osiEpochSecond(void);

/**
 * \brief set the monoclinic system time
 *
 * After the system time is changed, RTC won't be updated automatically.
 * It is needed to call RTC API to sync system time to RTC.
 *
 * When epoch time is changed, the monoclilinc system up time isn't changed,
 * and local time is changed correspondingly. The delta bewteen epoch time
 * and local time is only affected by timezone.
 *
 * \param ms    epoch time in milliseconds
 *
 * \return      true on succeed else fail
 */
bool osiSetEpochTime(int64_t ms);

/**
 * \brief get time zone in second
 *
 * Time zone is the offset between local time and epoch time:
 *      local_time = epoch_time + time_zone
 *
 * OSI won't keep time zone at power off. Other module should store
 * time zone in NVRAM, and set to OSI at boot.
 *
 * \return  time zone in second
 */
int osiTimeZoneOffset(void);

/**
 * \brief set time zone in second
 *
 * Time zone is the offset between local time and epoch time:
 *      local_time = epoch_time + time_zone
 *
 * Time zone should be in [-12*3600, 12*3600]. However, it is not checked
 * inside this. The caller should make sure the \p offset is reasonable.
 *
 * \param offset    time zone in second
 */
void osiSetTimeZoneOffset(int offset);

/**
 * \brief get the local time
 *
 * It is just: epoch_time + time_zone
 *
 * \return      local time in milliseconds
 */
int64_t osiLocalTime(void);

/**
 * \brief get the local time in seconds
 *
 * It is just: epoch_time + time_zone
 *
 * \return      local time in seconds
 */
int64_t osiLocalSecond(void);

/**
 * \brief monoclinic system hardware tick
 *
 * **Don't** call this in application code. It is only for legacy codes.
 *
 * The frequency of hardware tick is chip dependent, and implementation dependent.
 *
 * \return      monoclinic system hardware tick
 */
int64_t osiUpHWTick(void);

/**
 * \brief hardware tick count in 16384Hz
 *
 * The return value should be fulll 32bits value. That is, the next tick of
 * 0xffffffff will be 0. Then the simple substract will always provide the tick
 * delta.
 *
 * This is only for legacy codes. \p osiUpTime or \p osiUpTimeUS is recommended.
 * On some platform, it may be un-implemented.
 *
 * \return      hardware tick count
 */
uint32_t osiHWTick16K(void);

/**
 * \brief convert epoch time to up time
 *
 * When some values has special meanings, such as INT64_MAX means invalid or not
 * exist, caller should check special values before call this.
 *
 * \param epoch     epoch time in milliseconds
 * \return  up time in milliseconds
 */
int64_t osiEpochToUpTime(int64_t epoch);

/**
 * \brief start couting of elsapsed timer
 *
 * \param timer     elapsed timer, must be valid
 */
void osiElapsedTimerStart(osiElapsedTimer_t *timer);

/**
 * \brief elapsed milliseconds after start
 *
 * \param timer     elapsed timer, must be valid
 * \return
 *      - elapsed milliseconds after start
 */
uint32_t osiElapsedTime(osiElapsedTimer_t *timer);

/**
 * \brief elapsed microseconds after start
 *
 * \param timer     elapsed timer, must be valid
 * \return
 *      - elapsed microseconds after start
 */
uint32_t osiElapsedTimeUS(osiElapsedTimer_t *timer);

/**
 * \brief convert uptime to epoch time
 *
 * When some values has special meanings, such as INT64_MAX means invalid or not
 * exist, caller should check special values before call this.
 *
 * \param epoch     up time in milliseconds
 * \return  epoch time in milliseconds
 */
int64_t osiUpTimeToEpoch(int64_t uptime);

/**
 * \brief CPU suspend
 *
 * Usually, it shouldn't be called directly by application. Rather, it is
 * implemented by BSP, and called by \p osiPmSuspend.
 *
 * \param mode  suspend mode
 * \param ms    suspend time in milliseconds
 * \return
 *      suspend resume source. \p OSI_RESUME_ABORT bit indicates suspend
 *      aborted.
 */
uint32_t osiPmCpuSuspend(osiSuspendMode_t mode, int64_t ms);

/**
 * \brief PM source callbacks
 *
 * All the callbacks are called with interrupt disabled. So, it is not
 * needed to call \p osiEnterCritical or \p osiIrqSave for protection.
 * And it is not error to call them.
 *
 * Don't call blocking API in the callback.
 */
typedef struct osiPmSourceOps
{
    void (*suspend)(void *ctx, osiSuspendMode_t mode);                 ///< callback to be called before suspend
    void (*resume)(void *ctx, osiSuspendMode_t mode, uint32_t source); ///< callback to be called after resume
    bool (*prepare)(void *ctx);                                        ///< callback to be called at suspend check
    void (*prepare_abort)(void *ctx);                                  ///< callback to be called at suspend check fail
} osiPmSourceOps_t;

/**
 * PM source opaque data struct
 */
typedef struct osiPmSource osiPmSource_t;

/**
 * \brief power management module initialization
 *
 * It should be called in early stage of boot, due to many other modules
 * may register suspend and resume callback at initialization.
 */
void osiPmInit(void);

/**
 * \brief power management core start
 *
 * To avoid suspend too early, PM core won't be started at initialization
 * automatically. After system is initialized, and necessary PM sources
 * are created, \p osiPmStart shall be called.
 *
 * Only after \p osiPmStart is called, PM core will check and enter suspend.
 */
void osiPmStart(void);

/**
 * \brief power management core stop
 *
 * Stop PM core, and systen will never suspend.
 *
 * It is only for debug. And it shouldn't be used in real application.
 */
void osiPmStop(void);

/**
 * \brief create PM source
 *
 * Modules are distinguished by FOURCC *tag*. So, tag should be unique
 * system wise.
 *
 * When the *tag* is already registered, it will return existed PM source.
 *
 * \p ops is permitted to be NULL, and all callbacks inside it are permitted
 * to be NULL.
 *
 * Resume callbacks are called in create order, suspend callbacks are called
 * in revered order. When resume order does matter, call \p osiPmResumeReorder
 * or \p osiPmResumeFirst to change resume order.
 *
 * The returned pointer should be destroyed and freed by \p osiPmSourceDelete.
 *
 * PM source lock and unlock is binary. That is, there is no *counter* inside.
 * When \p osiPmWakeUnlock is called, the PM source won't prevent system
 * suspend, no matter how many times of \p osiPmWakeLock is called.
 *
 * \param tag       module tag
 * \param ops       callbacks during suspend and resume
 * \param ctx       callback context, shared by all callbacks
 * \return
 *      - PM source pointer
 *      - NULL on out of memory
 */
osiPmSource_t *osiPmSourceCreate(uint32_t tag, const osiPmSourceOps_t *ops, void *ctx);

/**
 * \brief destroy PM source
 *
 * \param ps        PM source
 */
void osiPmSourceDelete(osiPmSource_t *ps);

/**
 * \brief ensure resume callback order
 *
 * In cases that the resume callback order is important, this API will check
 * and change resume callback order if needed. After the call, the resumed
 * order is ensured.
 *
 * When resume callback order is changed, suspend callback order is changed
 * also.
 *
 * It won't be checked whether the tags are valid.
 *
 * \param tag_later     module tag to be resumed laster
 * \param tag_earlier   module tag to be resumed earlier
 */
void osiPmResumeReorder(uint32_t tag_later, uint32_t tag_earlier);

/**
 * \brief move PM source to the first in resume order
 *
 * Find the PM source, and move it to the head of resume list. When PM source
 * with \p tag is not found in resume list, nothing will be done.
 *
 * \param tag       module tag to be moved
 */
void osiPmResumeFirst(uint32_t tag);

/**
 * \brief wake lock to prevent suspend
 *
 * Indicate the PM source will prevent system suspend. PM source is *NOT*
 * counting, \p osiPmWakeLock will just set the PM source state. Multiple
 * calls of \p osiPmWakeLock is equivalent to a single call.
 *
 * When \p ops.prepare is not NULL, the internal state of PM source is
 * *suspend possible* rather than *active*. When system wants to
 * suspend, \p ops.prepare will be called to double check whether
 * suspend is permitted.
 *
 * \param ps        PM source
 */
void osiPmWakeLock(osiPmSource_t *ps);

/**
 * \brief wake unlock to permit suspend
 *
 * Indicate the PM source won't prevent system suspend. PM source is *NOT*
 * counting. No matter how many calls of \p osiPmWakeLock are called,
 * \p osiPmWakeUnlock will set the PM source to unlock state.
 *
 * \param ps        PM source
 */
void osiPmWakeUnlock(osiPmSource_t *ps);

/**
 * \brief power management suspend
 *
 * Usually, it shouldn't be called directly by application. Rather, it will
 * be called after suspend criteria are met.
 */
void osiPmSleep(uint32_t idle_tick);

/**
 * \brief dump PM source information to memory
 *
 * It is for debug only. The data format of timer information dump is
 * not stable, and may change. Currently, there is 4 bytes header, and
 * 4 bytes for each PM source.
 *
 * Caller should make sure \p mem is enough for hold PM source information
 * of \p count.
 *
 * \param mem       memory for PM source information dump
 * \param count     maximum PM source count to be dump
 * \return
 *      - dump memory size
 *      - -1 if \p count is too small
 */
int osiPmSourceDump(void *mem, int count);

/**
 * \brief set 32K sleep flag
 *
 * For platforms support both 32K sleep and suspend, the default sleep
 * mode is suspend. When it is needed to use 32K sleep forcedly, it is
 * needed to call this API.
 *
 * Each bit of \p flag represents a request source. When there are any
 * 32K sleep requests, system will use 32K sleep rather than suspend.
 *
 * The 32K sleep request sources depend on platform. And they are
 * defined in platform dependent hal_chip.h.
 *
 * \param flag      32K sleep request flag
 */
void osiSet32KSleepFlag(uint32_t flag);

/**
 * \brief clear 32K sleep flag
 *
 * \param flag      32K sleep request flag
 */
void osiClear32KSleepFlag(uint32_t flag);

/**
 * \brief register a shutdown callback
 *
 * When the callback and context is already registered, it will return
 * false.
 *
 * The order to invoke callbacks is undefined.
 *
 * *Don't* call \p osiRegisterShutdownCallback or
 * \p osiUnregisterShutdownCallback inside the callbacks.
 *
 * \param cb        shutdown callback to be registered, can't be NULL
 * \param ctx       shutdown callback context
 * \return
 *      - true if callback registered
 *      - false if callback is already registered, or callback is NULL
 */
bool osiRegisterShutdownCallback(osiShutdownCallback_t cb, void *ctx);

/**
 * \brief unregister a shutdown callback
 *
 * \param cb        shutdown callback to be unregistered, can't be NULL
 * \param ctx       shutdown callback context
 * \return
 *      - true if callback unregistered
 *      - false if callback isn't found
 */
bool osiUnregisterShutdownCallback(osiShutdownCallback_t cb, void *ctx);

/**
 * \brief get PSM expiration time in uptime
 *
 * \return
 *      - PSM expiration time in uptime
 *      - INT64_MAX if PSM not enabled
 */
int64_t osiGetPsmWakeUpTime(void);

/**
 * \brief set PSM expiration time in uptime
 *
 * \param uptime    PSM expiration time in uptime
 *                  or INT64_MAX to disable PSM
 */
void osiSetPsmWakeUpTime(int64_t uptime);

/**
 * \brief set PSM sleep time from now
 *
 * \param ms        PSM sleep time from now
 *                  or INT64_MAX to disable PSM
 */
void osiSetPsmSleepTime(int64_t ms);

/**
 * \brief get PSM elapsed time in milliseconds
 *
 * The starting point is the time \p osiSetPsmWakeUpTime or
 * \p osiSetPsmSleepTime is called. And this returns the elapsed time from
 * the starting point to now.
 *
 * \return      PSM elsapsed time
 */
int64_t osiGetPsmElapsedTime(void);

/**
 * \brief get cp deep sleep time in milliseconds
 *
 * \return      cp deep sleep time
 */
uint64_t osiCpDeepSleepTime(void);

/**
 * \brief shutdown to specified mode
 *
 * When parameter is wrong, it will return false:
 * - When \p mode is OSI_SHUTDOWN_PSM_SLEEP, and PSM isn't enabled.
 *   Caller should check whether PSM is enabled before calling
 *   \p osiShutdown.
 * - When \p mode is not supported in the platform.
 *
 * It never return true.
 *
 * \param mode      shutdown mode
 * \return
 *      - false on parameter error
 */
bool osiShutdown(osiShutdownMode_t mode);

/**
 * \brief get boot causes
 *
 * It is possible there are multiple boot causes. The returned value is
 * bit or of all boot causes.
 *
 * It is possible hardware registers will be cleared after accessed. So,
 * always call \p osiGetBootCauses to get the boot causes, rather than
 * accessing hardware registers directly.
 *
 * \return  boot causes
 */
uint32_t osiGetBootCauses(void);

/**
 * \brief set a boot cause
 *
 * It is intended only for system integration.
 *
 * \param cause     boot cause
 */
void osiSetBootCause(osiBootCause_t cause);

/**
 * \brief clear a boot cause
 *
 * It is intended only for system integration.
 *
 * \param cause     boot cause
 */
void osiClearBootCause(osiBootCause_t cause);

/**
 * \brief get boot mode
 *
 * \return  boot mode
 */
osiBootMode_t osiGetBootMode(void);

/**
 * \brief set boot mode
 *
 * It is intended only for system integration. At calling, caller should
 * take care conflict of other boot mode detection.
 *
 * \param mode      boot mode
 */
void osiSetBootMode(osiBootMode_t mode);

/**
 * \brief PSM save preparation
 *
 * It will be called before any \p osiPsmDataSave. Usually, it will prepare
 * PSM data memory.
 *
 * \param mode      shutdown mode
 */
void osiPsmSavePrepare(osiShutdownMode_t mode);

/**
 * \brief PSM save
 *
 * Save all owner's PSM data to persistent storage.
 *
 * \param mode      shutdown mode
 */
void osiPsmSave(osiShutdownMode_t mode);

/**
 * \brief PSM restore
 *
 * It should be called in system initialization, after file system
 * initialization.
 */
void osiPsmRestore(void);

/**
 * \brief save PSM data
 *
 * PSM data save is implemented in platform. PSM data should be saved in
 * persistent storage, which can be flash or aon memory. Caller shouldn't
 * assume the storage type.
 *
 * It should only be called in \p osiShutdown callbacks.
 *
 * For each owner, \p osiPsmDataSave shall be called only once at most.
 *
 * It is recommended to use fixed size buffer, which is the same at each
 * PSM shutdown. However, variable size buffer is also supported.
 *
 * As a special case, \p size of 0 is permitted. It just keep record that
 * the owner is saved without real data.
 *
 * \param owner     PSM data owner
 * \param buf       owner's PSM data buffer
 * \param size      owner's PSM data buffer size
 * \return
 *      - true on success
 *      - false on fail
 *          - duplicated owner
 *          - out of memory
 */
bool osiPsmDataSave(osiPsmDataOwner_t owner, const void *buf, uint32_t size);

/**
 * \brief restore PSM data
 *
 * Restore PSM data. At PSM resume boot, PSM data owner calls this to get
 * the data saved by \p osiPsmDataSave
 *
 * The buffer size should be equal or larger than the saved size. If it is
 * smaller than saved size, return -1.
 *
 * When \p buf is NULL, it will return PSM data size without copy. It can
 * be used to get the PSM data size.
 *
 * \param owner     PSM data owner
 * \param buf       buffer for owner's PSM data
 * \param size      buffer size
 * \return
 *      - PSM data size on success
 *      - 0 if there are no PSM data
 *      - -1 on error
 */
int osiPsmDataRestore(osiPsmDataOwner_t owner, void *buf, uint32_t size);

/**
 * send out debug event to trace tool
 *
 * If system and trace tool support debug event, this will send
 * a word to trace tool.
 *
 * It should be only used in quick debug. It is possible that platform
 * can't support debug event, and debug event output may be turned off
 * by compiling option.
 *
 * \param event     word which will appear on trace tool
 */
void osiDebugEvent(uint32_t event);

/**
 * panic
 *
 * Called on fatal error, and system can't go on.
 *
 * It is different from \p assert. It will always cause system panic,
 * and there are no compiling option to ignore it.
 */
OSI_NO_RETURN void osiPanic(void);

/**
 * whether system is in panic mode
 *
 * In panic mode, system will still run a small daemon. And there is no
 * interrupt in panic mode. So, features used in panic daemon shall take
 * care of this.
 *
 * \return
 *      - true if system is in panic mode
 *      - false if system is not in panic mode
 */
bool osiIsPanic(void);

#ifdef CONFIG_KERNEL_ASSERT_ENABLED
/*+\NEW\zhuwangbin\2020.4.2\添加AT*exinfo指令*/
extern void osiPanicInfoFuncLineSet(const char *func, int line);

#define OSI_ASSERT(expect_true, info) OSI_DO_WHILE0(if (!(expect_true)) {osiPanicInfoFuncLineSet(__FUNCTION__,__LINE__);osiPanic();})
#else
#define OSI_ASSERT(expect_true, info)
#endif
/*-\NEW\zhuwangbin\2020.4.2\添加AT*exinfo指令*/
/**
 * busy loop delay
 *
 * The precision of delay depends on platform. And it will ensure to delay
 * at least the specified time.
 *
 * \param us    delay time in microseconds
 */
OSI_NO_MIPS16 void osiDelayUS(uint32_t us);

/**
 * delay by CPU loop
 *
 * The absolute delay time depends on CPU frequency. \p count is the loop
 * count, not the delayed instruction count.
 *
 * \param count     delay loop count
 */
void osiDelayLoops(uint32_t count);

/**
 * call function with specified stack
 *
 * This will only be called with low level codes, and most likely, it is not
 * needed for application.
 *
 * This function is located in SRAM. So, it can be called even the external
 * RAM in unavailable.
 *
 * \p function shall have 2 parameters at most. It can return one word. When
 * \p function doesn't return value, the return value of this wrapper is
 * undefined.
 *
 * \p sp should be 8 bytes aligned.
 *
 * \param sp        the stack to be used for \p function
 * \param function  the real function
 * \param param0    the first parameter for \p function
 * \param param1    the second parameter for \p function
 * \return
 *      - the return value of \p function
 */
uint32_t osiCallWithStack(void *sp, void *function, uint32_t param0, uint32_t param1);

#ifndef DOXYGEN
// it is needed to place such definitions in a better place
#define PM_TAG_ADI_BUS OSI_MAKE_TAG('A', 'D', 'I', 'B')
#define PM_TAG_IOMUX OSI_MAKE_TAG('I', 'O', 'M', 'X')
#define PM_TAG_GPIO OSI_MAKE_TAG('G', 'P', 'I', 'O')
#define PM_TAG_AXI_DMA OSI_MAKE_TAG('A', 'D', 'M', 'A')
#endif

#ifdef __cplusplus
}
#endif
#endif
