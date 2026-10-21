//
// Copyright (c) 2022 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//   Błażej Sowa, <blazej@fictionlab.pl>

#ifndef ZENOH_PICO_SYSTEM_PLATFORM_COMMON_H
#define ZENOH_PICO_SYSTEM_PLATFORM_COMMON_H

#ifndef SPHINX_DOCS
// For some reason sphinx/clang doesn't handle bool types correctly if stdbool.h is included
#include <stdbool.h>
#endif
#include <stdint.h>

#include "zenoh-pico/api/olv_macros.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/utils/result.h"

#if defined(ZENOH_LINUX) || defined(ZENOH_MACOS) || defined(ZENOH_BSD)
#include "zenoh-pico/system/platform/unix.h"
#elif defined(ZENOH_WINDOWS)
#define NOMINMAX
#include "zenoh-pico/system/platform/windows.h"
#elif defined(ZENOH_ESPIDF)
#include "zenoh-pico/system/platform/espidf.h"
#elif defined(ZENOH_MBED)
#include "zenoh-pico/system/platform/mbed.h"
#elif defined(ZENOH_ZEPHYR)
#include "zenoh-pico/system/platform/zephyr.h"
#elif defined(ZENOH_ARDUINO_ESP32)
#include "zenoh-pico/system/platform/arduino/esp32.h"
#elif defined(ZENOH_ARDUINO_OPENCR)
#include "zenoh-pico/system/platform/arduino/opencr.h"
#elif defined(ZENOH_EMSCRIPTEN)
#include "zenoh-pico/system/platform/emscripten.h"
#elif defined(ZENOH_FLIPPER)
#include "zenoh-pico/system/platform/flipper.h"
#elif defined(ZENOH_FREERTOS_PLUS_TCP)
#include "zenoh-pico/system/platform/freertos/freertos_plus_tcp.h"
#elif defined(ZENOH_FREERTOS_LWIP)
#include "zenoh-pico/system/platform/freertos/lwip.h"
#elif defined(ZENOH_RPI_PICO)
#include "zenoh-pico/system/platform/rpi_pico.h"
#elif defined(ZENOH_GENERIC)
#include "zenoh_generic_platform.h"
#elif defined(ZENOH_THREADX_STM32)
#include "zenoh-pico/system/platform/threadx/stm32.h"
#else
#include "zenoh-pico/system/platform/void.h"
#error "Unknown platform"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*------------------ Random ------------------*/
/**
 * Generates a random unsigned 8-bit integer.
 */
uint8_t z_random_u8(void);

/**
 * Generates a random unsigned 16-bit integer.
 */
uint16_t z_random_u16(void);

/**
 * Generates a random unsigned 32-bit integer.
 */
uint32_t z_random_u32(void);

/**
 * Generates a random unsigned 64-bit integer.
 */
uint64_t z_random_u64(void);

/**
 * Fills buffer with random data.
 *
 * Parameters:
 *   buf: Pointer to the buffer that will be filled with random data.
 *   len: Number of bytes to fill in the buffer.
 */
void z_random_fill(void *buf, size_t len);

/*------------------ Memory ------------------*/

/**
 * Allocates memory of the specified size.
 *
 * Parameters:
 *   size: The number of bytes to allocate.
 *
 * Returns:
 *   A pointer to the allocated memory, or NULL if the allocation fails.
 */
void *z_malloc(size_t size);

/**
 * Reallocates the given memory block to a new size.
 *
 * Parameters:
 *   ptr: Pointer to the previously allocated memory. Can be NULL, in which case it behaves like z_malloc().
 *   size: The new size for the memory block in bytes.
 *
 * Returns:
 *   A pointer to the reallocated memory, or NULL if the reallocation fails.
 */
void *z_realloc(void *ptr, size_t size);

/**
 * Frees the memory previously allocated by z_malloc or z_realloc.
 *
 * Parameters:
 *   ptr: Pointer to the memory to be freed. If NULL, no action is taken.
 */
void z_free(void *ptr);

#if Z_FEATURE_MULTI_THREAD == 0
// dummy types for correct macros work
typedef void *_z_task_t;
typedef void *_z_mutex_t;
typedef void *_z_mutex_rec_t;
typedef void *_z_condvar_t;
typedef void *z_task_attr_t;
typedef void *_z_task_id_t;
#endif

/*------------------ Thread ------------------*/
_Z_OWNED_TYPE_VALUE(_z_task_t, task)
_Z_OWNED_FUNCTIONS_SYSTEM_DEF(task)

z_result_t _z_task_init(_z_task_t *task, z_task_attr_t *attr, void *(*fun)(void *), void *arg);
z_result_t _z_task_join(_z_task_t *task);
z_result_t _z_task_detach(_z_task_t *task);
z_result_t _z_task_cancel(_z_task_t *task);
void _z_task_exit(void);
void _z_task_free(_z_task_t **task);
_z_task_id_t _z_task_get_id(const _z_task_t *task);
_z_task_id_t _z_task_current_id(void);
bool _z_task_id_equal(const _z_task_id_t *l, const _z_task_id_t *r);

/**
 * Constructs a new task.
 *
 * Parameters:
 *   task: An uninitialized memory location where task will be constructed.
 *   attr: Attributes of the task.
 *   fun: Function to be executed by the task.
 *   arg: Argument that will be passed to the function `fun`.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_task_init(z_owned_task_t *task, z_task_attr_t *attr, void *(*fun)(void *), void *arg);

/**
 * Joins the task and releases all allocated resources.
 *
 * Parameters:
 *   task: Pointer to a :c:type:`z_moved_task_t` representing the task to be joined.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_task_join(z_moved_task_t *task);

/**
 * Detaches the task and releases all allocated resources.
 *
 * Parameters:
 *   task: Pointer to a :c:type:`z_moved_task_t` representing the task to be detached.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_task_detach(z_moved_task_t *task);

/**
 * Drops the task. Same as :c:func:`z_task_detach`. Use :c:func:`z_task_join` to wait for the task completion.
 *
 * Parameters:
 *   task: Pointer to a :c:type:`z_moved_task_t` representing the task to be dropped.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_task_drop(z_moved_task_t *task);

/*------------------ Mutex ------------------*/
_Z_OWNED_TYPE_VALUE(_z_mutex_t, mutex)
_Z_OWNED_FUNCTIONS_SYSTEM_DEF(mutex)

z_result_t _z_mutex_init(_z_mutex_t *m);
z_result_t _z_mutex_drop(_z_mutex_t *m);

z_result_t _z_mutex_lock(_z_mutex_t *m);
z_result_t _z_mutex_try_lock(_z_mutex_t *m);
z_result_t _z_mutex_unlock(_z_mutex_t *m);

z_result_t _z_mutex_rec_init(_z_mutex_rec_t *m);
z_result_t _z_mutex_rec_drop(_z_mutex_rec_t *m);
z_result_t _z_mutex_rec_lock(_z_mutex_rec_t *m);
z_result_t _z_mutex_rec_try_lock(_z_mutex_rec_t *m);
z_result_t _z_mutex_rec_unlock(_z_mutex_rec_t *m);

/**
 * Constructs a mutex.
 *
 * Parameters:
 *   m: Pointer to an uninitialized :c:type:`z_owned_mutex_t` that will be constructed.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_mutex_init(z_owned_mutex_t *m);

/**
 * Drops a mutex and resets it to its gravestone state.
 *
 * Parameters:
 *   m: Pointer to a :c:type:`z_moved_mutex_t` that will be dropped.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_mutex_drop(z_moved_mutex_t *m);

/**
 * Locks a mutex. If the mutex is already locked, blocks the thread until it acquires the lock.
 *
 * Parameters:
 *   m: Pointer to a :c:type:`z_loaned_mutex_t` that will be locked.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_mutex_lock(z_loaned_mutex_t *m);

/**
 * Tries to lock a mutex. If the mutex is already locked, the function returns immediately.
 *
 * Parameters:
 *   m: Pointer to a :c:type:`z_loaned_mutex_t` that will be locked if not already locked.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_mutex_try_lock(z_loaned_mutex_t *m);

/**
 * Unlocks a previously locked mutex. If the mutex was not locked by the current thread, the behavior is undefined.
 *
 * Parameters:
 *   m: Pointer to a :c:type:`z_loaned_mutex_t` that will be unlocked.
 *
 * Returns:
 *   ``0`` in case of success, negative error code otherwise.
 */
z_result_t z_mutex_unlock(z_loaned_mutex_t *m);

/*------------------ CondVar ------------------*/
_Z_OWNED_TYPE_VALUE(_z_condvar_t, condvar)
_Z_OWNED_FUNCTIONS_SYSTEM_DEF(condvar)

z_result_t _z_condvar_init(_z_condvar_t *cv);
z_result_t _z_condvar_drop(_z_condvar_t *cv);

z_result_t _z_condvar_signal(_z_condvar_t *cv);
z_result_t _z_condvar_signal_all(_z_condvar_t *cv);
z_result_t _z_condvar_wait(_z_condvar_t *cv, _z_mutex_t *m);
z_result_t _z_condvar_wait_until(_z_condvar_t *cv, _z_mutex_t *m, const z_clock_t *abstime);

/**
 * Initializes a condition variable.
 *
 * Parameters:
 *   cv: Pointer to an uninitialized :c:type:`z_owned_condvar_t` that will be initialized.
 *
 * Returns:
 *   ``0`` if the initialization is successful, a negative value otherwise.
 */
z_result_t z_condvar_init(z_owned_condvar_t *cv);

/**
 * Destroys a condition variable and releases its resources.
 *
 * Parameters:
 *   cv: Pointer to a :c:type:`z_moved_condvar_t` that will be destroyed.
 *
 * Returns:
 *   ``0`` if the destruction is successful, a negative value otherwise.
 */
z_result_t z_condvar_drop(z_moved_condvar_t *cv);

/**
 * Signals (wakes up) one thread waiting on the condition variable.
 *
 * Parameters:
 *   cv: Pointer to a :c:type:`z_loaned_condvar_t` that will be signaled.
 *
 * Returns:
 *   ``0`` if the signal is successful, a negative value otherwise.
 */
z_result_t z_condvar_signal(z_loaned_condvar_t *cv);

/**
 * Waits for a signal on the condition variable while holding a mutex.
 *
 * The calling thread is blocked until the condition variable is signaled.
 * The associated mutex must be locked by the calling thread, and it will be automatically unlocked while waiting.
 *
 * Parameters:
 *   cv: Pointer to a :c:type:`z_loaned_condvar_t` on which to wait.
 *   m: Pointer to a :c:type:`z_loaned_mutex_t` that will be unlocked during the wait.
 *
 * Returns:
 *   ``0`` if the wait is successful, a negative value otherwise.
 */
z_result_t z_condvar_wait(z_loaned_condvar_t *cv, z_loaned_mutex_t *m);

/**
 * Waits for a signal on the condition variable while holding a mutex until a specified time.
 *
 * The calling thread is blocked until the condition variable is signaled or the timeout occurs.
 * The associated mutex must be locked by the calling thread, and it will be automatically unlocked while waiting.
 *
 * Parameters:
 *   cv: Pointer to a :c:type:`z_loaned_condvar_t` on which to wait.
 *   m: Pointer to a :c:type:`z_loaned_mutex_t` that will be unlocked during the wait.
 *   abstime: Absolute end time.
 *
 * Returns:
 *   ``0`` if the wait is successful, ``Z_ETIMEDOUT`` if a timeout occurred, other negative value otherwise.
 */
z_result_t z_condvar_wait_until(z_loaned_condvar_t *cv, z_loaned_mutex_t *m, const z_clock_t *abstime);

/*------------------ Sleep ------------------*/
/**
 * Suspends execution for a specified amount of time in microseconds.
 *
 * Parameters:
 *   time: The amount of time to sleep, in microseconds.
 *
 * Returns:
 *   ``0`` if the sleep is successful, a negative value otherwise.
 */
z_result_t z_sleep_us(size_t time);

/**
 * Suspends execution for a specified amount of time in milliseconds.
 *
 * Parameters:
 *   time: The amount of time to sleep, in milliseconds.
 *
 * Returns:
 *   ``0`` if the sleep is successful, a negative value otherwise.
 */
z_result_t z_sleep_ms(size_t time);

/**
 * Suspends execution for a specified amount of time in seconds.
 *
 * Parameters:
 *   time: The amount of time to sleep, in seconds.
 *
 * Returns:
 *   ``0`` if the sleep is successful, a negative value otherwise.
 */
z_result_t z_sleep_s(size_t time);

/*------------------ Clock ------------------*/
/**
 * Returns monotonic clock time point corresponding to the current time instant.
 */
z_clock_t z_clock_now(void);

unsigned long zp_clock_elapsed_us_since(z_clock_t *instant, z_clock_t *epoch);
unsigned long zp_clock_elapsed_ms_since(z_clock_t *instant, z_clock_t *epoch);
unsigned long zp_clock_elapsed_s_since(z_clock_t *instant, z_clock_t *epoch);

/**
 * Returns the elapsed time in microseconds since a given clock time.
 *
 * Parameters:
 *   time: Pointer to a `z_clock_t` representing the starting time.
 *
 * Returns:
 *   The elapsed time in microseconds.
 */
unsigned long z_clock_elapsed_us(z_clock_t *time);

/**
 * Returns the elapsed time in milliseconds since a given clock time.
 *
 * Parameters:
 *   time: Pointer to a `z_clock_t` representing the starting time.
 *
 * Returns:
 *   The elapsed time in milliseconds.
 */
unsigned long z_clock_elapsed_ms(z_clock_t *time);

/**
 * Returns the elapsed time in seconds since a given clock time.
 *
 * Parameters:
 *   time: Pointer to a `z_clock_t` representing the starting time.
 *
 * Returns:
 *   The elapsed time in seconds.
 */
unsigned long z_clock_elapsed_s(z_clock_t *time);

/**
 * Offsets the clock by a specified duration in microseconds.
 *
 * Parameters:
 *   clock: Pointer to a `z_clock_t` to offset.
 *   duration: The duration in microseconds.
 */
void z_clock_advance_us(z_clock_t *clock, unsigned long duration);

/**
 * Offsets the clock by a specified duration in milliseconds.
 *
 * Parameters:
 *   clock: Pointer to a `z_clock_t` to offset.
 *   duration: The duration in milliseconds.
 */
void z_clock_advance_ms(z_clock_t *clock, unsigned long duration);

/**
 * Offsets the clock by a specified duration in seconds.
 *
 * Parameters:
 *   clock: Pointer to a `z_clock_t` to offset.
 *   duration: The duration in seconds.
 */
void z_clock_advance_s(z_clock_t *clock, unsigned long duration);

/*------------------ Time ------------------*/

/**
 * Returns system clock time point corresponding to the current time instant.
 */
z_time_t z_time_now(void);

/**
 * Gets the current time as a string.
 *
 * Parameters:
 *   buf: Pointer to a buffer where the time string will be written.
 *   buflen: The length of the buffer.
 *
 * Returns:
 *   A pointer to the buffer containing the time string.
 */
const char *z_time_now_as_str(char *const buf, unsigned long buflen);

/**
 * Returns the elapsed time in microseconds since a given time.
 *
 * Parameters:
 *   time: Pointer to a `z_time_t` representing the starting time.
 *
 * Returns:
 *   The elapsed time in microseconds.
 */
unsigned long z_time_elapsed_us(z_time_t *time);

/**
 * Returns the elapsed time in milliseconds since a given time.
 *
 * Parameters:
 *   time: Pointer to a `z_time_t` representing the starting time.
 *
 * Returns:
 *   The elapsed time in milliseconds.
 */
unsigned long z_time_elapsed_ms(z_time_t *time);

/**
 * Returns the elapsed time in seconds since a given time.
 *
 * Parameters:
 *   time: Pointer to a `z_time_t` representing the starting time.
 *
 * Returns:
 *   The elapsed time in seconds.
 */
unsigned long z_time_elapsed_s(z_time_t *time);

typedef struct {
    uint32_t secs;
    uint32_t nanos;
} _z_time_since_epoch;

z_result_t _z_get_time_since_epoch(_z_time_since_epoch *t);

/*------------------ P2p unicast internal functions ------------------*/

z_result_t _z_socket_set_blocking(const _z_sys_net_socket_t *sock, bool blocking);
z_result_t _z_socket_accept(const _z_sys_net_socket_t *sock_in, _z_sys_net_socket_t *sock_out);
z_result_t _z_ip_port_to_endpoint(const uint8_t *address, size_t address_len, uint16_t port, char *dst, size_t dst_len);
z_result_t _z_socket_get_endpoints(const _z_sys_net_socket_t *sock, char *local, size_t local_len, char *remote,
                                   size_t remote_len);
void _z_socket_close(_z_sys_net_socket_t *sock);
z_result_t _z_socket_wait_event(void *peers, _z_mutex_rec_t *mutex);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SYSTEM_PLATFORM_COMMON_H */
