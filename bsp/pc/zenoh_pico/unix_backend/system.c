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
//

#include <errno.h>
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "zenoh-pico/utils/result.h"

#if defined(ZENOH_LINUX)
#include <sys/random.h>
#include <sys/time.h>
#endif

#include <unistd.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/system/common/system_error.h"
#include "zenoh-pico/system/platform.h"

/*------------------ Random ------------------*/
uint8_t z_random_u8(void) {
    uint8_t ret = 0;
#if defined(ZENOH_LINUX)
    while (getrandom(&ret, sizeof(uint8_t), 0) <= 0) {
        ZP_ASM_NOP;
    }
#elif defined(ZENOH_MACOS) || defined(ZENOH_BSD)
    ret = z_random_u32();
#endif

    return ret;
}

uint16_t z_random_u16(void) {
    uint16_t ret = 0;
#if defined(ZENOH_LINUX)
    while (getrandom(&ret, sizeof(uint16_t), 0) <= 0) {
        ZP_ASM_NOP;
    }
#elif defined(ZENOH_MACOS) || defined(ZENOH_BSD)
    ret = z_random_u32();
#endif

    return ret;
}

uint32_t z_random_u32(void) {
    uint32_t ret = 0;
#if defined(ZENOH_LINUX)
    while (getrandom(&ret, sizeof(uint32_t), 0) <= 0) {
        ZP_ASM_NOP;
    }
#elif defined(ZENOH_MACOS) || defined(ZENOH_BSD)
    ret = arc4random();
#endif

    return ret;
}

uint64_t z_random_u64(void) {
    uint64_t ret = 0;
#if defined(ZENOH_LINUX)
    while (getrandom(&ret, sizeof(uint64_t), 0) <= 0) {
        ZP_ASM_NOP;
    }
#elif defined(ZENOH_MACOS) || defined(ZENOH_BSD)
    ret |= z_random_u32();
    ret = ret << 32;
    ret |= z_random_u32();
#endif

    return ret;
}

void z_random_fill(void *buf, size_t len) {
#if defined(ZENOH_LINUX)
    while (getrandom(buf, len, 0) <= 0) {
        ZP_ASM_NOP;
    }
#elif defined(ZENOH_MACOS) || defined(ZENOH_BSD)
    arc4random_buf(buf, len);
#endif
}

/*------------------ Memory ------------------*/
void *z_malloc(size_t size) { return malloc(size); }

void *z_realloc(void *ptr, size_t size) { return realloc(ptr, size); }

void z_free(void *ptr) { free(ptr); }

#if Z_FEATURE_MULTI_THREAD == 1
/*------------------ Task ------------------*/
z_result_t _z_task_init(_z_task_t *task, z_task_attr_t *attr, void *(*fun)(void *), void *arg) {
    _Z_CHECK_SYS_ERR(pthread_create(task, attr, fun, arg));
}

z_result_t _z_task_join(_z_task_t *task) { _Z_CHECK_SYS_ERR(pthread_join(*task, NULL)); }

z_result_t _z_task_detach(_z_task_t *task) { _Z_CHECK_SYS_ERR(pthread_detach(*task)); }

z_result_t _z_task_cancel(_z_task_t *task) { _Z_CHECK_SYS_ERR(pthread_cancel(*task)); }

void _z_task_exit(void) { pthread_exit(NULL); }

void _z_task_free(_z_task_t **task) {
    _z_task_t *ptr = *task;
    z_free(ptr);
    *task = NULL;
}

_z_task_id_t _z_task_get_id(const _z_task_t *task) { return *task; }
_z_task_id_t _z_task_current_id(void) { return pthread_self(); }
bool _z_task_id_equal(const _z_task_id_t *l, const _z_task_id_t *r) { return pthread_equal(*l, *r) != 0; }

/*------------------ Mutex ------------------*/
z_result_t _z_mutex_init(_z_mutex_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_init(m, NULL)); }

z_result_t _z_mutex_drop(_z_mutex_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_destroy(m)); }

z_result_t _z_mutex_lock(_z_mutex_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_lock(m)); }

z_result_t _z_mutex_try_lock(_z_mutex_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_trylock(m)); }

z_result_t _z_mutex_unlock(_z_mutex_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_unlock(m)); }

z_result_t _z_mutex_rec_init(_z_mutex_rec_t *m) {
    pthread_mutexattr_t attr;
    _Z_RETURN_IF_SYS_ERR(pthread_mutexattr_init(&attr));
    _Z_RETURN_IF_SYS_ERR(pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE));
    _Z_RETURN_IF_SYS_ERR(pthread_mutex_init(m, &attr));
    _Z_CHECK_SYS_ERR(pthread_mutexattr_destroy(&attr));
}

z_result_t _z_mutex_rec_drop(_z_mutex_rec_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_destroy(m)); }

z_result_t _z_mutex_rec_lock(_z_mutex_rec_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_lock(m)); }

z_result_t _z_mutex_rec_try_lock(_z_mutex_rec_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_trylock(m)); }

z_result_t _z_mutex_rec_unlock(_z_mutex_rec_t *m) { _Z_CHECK_SYS_ERR(pthread_mutex_unlock(m)); }

/*------------------ Condvar ------------------*/
z_result_t _z_condvar_init(_z_condvar_t *cv) {
    pthread_condattr_t attr;
    pthread_condattr_init(&attr);
#ifndef ZENOH_MACOS
    // macos does not have pthread_condattr_setclock function
    pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
#endif
    _Z_CHECK_SYS_ERR(pthread_cond_init(cv, &attr));
}

z_result_t _z_condvar_drop(_z_condvar_t *cv) { _Z_CHECK_SYS_ERR(pthread_cond_destroy(cv)); }

z_result_t _z_condvar_signal(_z_condvar_t *cv) { _Z_CHECK_SYS_ERR(pthread_cond_signal(cv)); }

z_result_t _z_condvar_signal_all(_z_condvar_t *cv) { _Z_CHECK_SYS_ERR(pthread_cond_broadcast(cv)); }

z_result_t _z_condvar_wait(_z_condvar_t *cv, _z_mutex_t *m) { _Z_CHECK_SYS_ERR(pthread_cond_wait(cv, m)); }

z_result_t _z_condvar_wait_until(_z_condvar_t *cv, _z_mutex_t *m, const z_clock_t *abstime) {
#ifndef ZENOH_MACOS
    int error = pthread_cond_timedwait(cv, m, abstime);
#else
    // pthread_cond_timedwait does not work for macos since it assumes REALTIME_CLOCK
    // while z_clock_t corresponds to MONOTONIC_CLOCK.
    z_clock_t deadline = {0};
    z_clock_t now = z_clock_now();
    if (now.tv_sec < abstime->tv_sec) {
        deadline.tv_sec = abstime->tv_sec - now.tv_sec;
        if (now.tv_nsec <= abstime->tv_nsec) {
            deadline.tv_nsec = abstime->tv_nsec - now.tv_nsec;
        } else {
            deadline.tv_sec--;
            deadline.tv_nsec += 1000000000 + abstime->tv_nsec - now.tv_nsec;
        }
    } else if (now.tv_sec == abstime->tv_sec && now.tv_nsec < abstime->tv_nsec) {
        deadline.tv_nsec = abstime->tv_nsec - now.tv_nsec;
    }
    int error = pthread_cond_timedwait_relative_np(cv, m, &deadline);
#endif

    if (error == ETIMEDOUT) {
        return Z_ETIMEDOUT;
    }

    _Z_CHECK_SYS_ERR(error);
}
#endif  // Z_FEATURE_MULTI_THREAD == 1

/*------------------ Sleep ------------------*/
z_result_t z_sleep_us(size_t time) { _Z_CHECK_SYS_ERR(usleep((unsigned int)time)); }

z_result_t z_sleep_ms(size_t time) {
    z_time_t start = z_time_now();

    // Most sleep APIs promise to sleep at least whatever you asked them to.
    // This may compound, so this approach may make sleeps longer than expected.
    // This extra check tries to minimize the amount of extra time it might sleep.
    while (z_time_elapsed_ms(&start) < time) {
        z_result_t ret = z_sleep_us(1000);
        if (ret != _Z_RES_OK) {
            return ret;
        }
    }

    return _Z_RES_OK;
}

z_result_t z_sleep_s(size_t time) { _Z_CHECK_SYS_ERR((int)sleep((unsigned int)time)); }

/*------------------ Instant ------------------*/
z_clock_t z_clock_now(void) {
    z_clock_t now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now;
}

unsigned long zp_clock_elapsed_us_since(z_clock_t *instant, z_clock_t *epoch) {
    long elapsed = (1000000 * (instant->tv_sec - epoch->tv_sec) + (instant->tv_nsec - epoch->tv_nsec) / 1000);
    return elapsed > 0 ? (unsigned long)elapsed : 0;
}

unsigned long zp_clock_elapsed_ms_since(z_clock_t *instant, z_clock_t *epoch) {
    long elapsed = (1000 * (instant->tv_sec - epoch->tv_sec) + (instant->tv_nsec - epoch->tv_nsec) / 1000000);
    return elapsed > 0 ? (unsigned long)elapsed : 0;
}

unsigned long zp_clock_elapsed_s_since(z_clock_t *instant, z_clock_t *epoch) {
    long elapsed = (instant->tv_sec - epoch->tv_sec);
    return elapsed > 0 ? (unsigned long)elapsed : 0;
}

unsigned long z_clock_elapsed_us(z_clock_t *instant) {
    z_clock_t now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return zp_clock_elapsed_us_since(&now, instant);
}

unsigned long z_clock_elapsed_ms(z_clock_t *instant) {
    z_clock_t now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    return zp_clock_elapsed_ms_since(&now, instant);
}

unsigned long z_clock_elapsed_s(z_clock_t *instant) {
    z_clock_t now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    return zp_clock_elapsed_s_since(&now, instant);
}

void z_clock_advance_us(z_clock_t *clock, unsigned long duration) {
    clock->tv_sec += (time_t)(duration / 1000000);
    clock->tv_nsec += (long int)((duration % 1000000) * 1000);

    if (clock->tv_nsec >= 1000000000) {
        clock->tv_sec += 1;
        clock->tv_nsec -= 1000000000;
    }
}

void z_clock_advance_ms(z_clock_t *clock, unsigned long duration) {
    clock->tv_sec += (time_t)(duration / 1000);
    clock->tv_nsec += (long int)((duration % 1000) * 1000000);

    if (clock->tv_nsec >= 1000000000) {
        clock->tv_sec += 1;
        clock->tv_nsec -= 1000000000;
    }
}

void z_clock_advance_s(z_clock_t *clock, unsigned long duration) { clock->tv_sec += (time_t)duration; }

/*------------------ Time ------------------*/
z_time_t z_time_now(void) {
    z_time_t now;
    gettimeofday(&now, NULL);
    return now;
}

const char *z_time_now_as_str(char *const buf, unsigned long buflen) {
    z_time_t tv = z_time_now();
    struct tm ts;
    ts = *localtime(&tv.tv_sec);
    strftime(buf, buflen, "%Y-%m-%dT%H:%M:%SZ", &ts);
    return buf;
}

unsigned long z_time_elapsed_us(z_time_t *time) {
    z_time_t now;
    gettimeofday(&now, NULL);

    unsigned long elapsed = (unsigned long)(1000000 * (now.tv_sec - time->tv_sec) + (now.tv_usec - time->tv_usec));
    return elapsed;
}

unsigned long z_time_elapsed_ms(z_time_t *time) {
    z_time_t now;
    gettimeofday(&now, NULL);

    unsigned long elapsed = (unsigned long)(1000 * (now.tv_sec - time->tv_sec) + (now.tv_usec - time->tv_usec) / 1000);
    return elapsed;
}

unsigned long z_time_elapsed_s(z_time_t *time) {
    z_time_t now;
    gettimeofday(&now, NULL);

    unsigned long elapsed = (unsigned long)(now.tv_sec - time->tv_sec);
    return elapsed;
}

z_result_t _z_get_time_since_epoch(_z_time_since_epoch *t) {
    z_time_t now;
    gettimeofday(&now, NULL);
    t->secs = (uint32_t)now.tv_sec;
    t->nanos = (uint32_t)now.tv_usec * 1000;
    return 0;
}
