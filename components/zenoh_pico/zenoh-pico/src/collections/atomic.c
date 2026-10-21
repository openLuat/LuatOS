#include "zenoh-pico/collections/atomic.h"

#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/config.h"

#if Z_FEATURE_MULTI_THREAD == 1
#if ZENOH_C_STANDARD != 99
#ifndef __cplusplus
#include <stdatomic.h>
typedef _Atomic(size_t) _z_atomic_t;
_Static_assert(sizeof(size_t) == sizeof(_z_atomic_t), "_Atomic(size_t) must have same size as size_t");
static const memory_order _z_memory_order_map[] = {memory_order_relaxed, memory_order_acquire, memory_order_release,
                                                   memory_order_acq_rel, memory_order_seq_cst};
void _z_atomic_size_init(_z_atomic_size_t *var, size_t value) { atomic_init((_z_atomic_t *)&var->_value, value); }
size_t _z_atomic_size_load(_z_atomic_size_t *var, _z_memory_order_t order) {
    return atomic_load_explicit((_z_atomic_t *)&var->_value, _z_memory_order_map[order]);
}
void _z_atomic_size_store(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    atomic_store_explicit((_z_atomic_t *)&var->_value, val, _z_memory_order_map[order]);
}
size_t _z_atomic_size_fetch_add(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    return atomic_fetch_add_explicit((_z_atomic_t *)&var->_value, val, _z_memory_order_map[order]);
}
size_t _z_atomic_size_fetch_sub(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    return atomic_fetch_sub_explicit((_z_atomic_t *)&var->_value, val, _z_memory_order_map[order]);
}
bool _z_atomic_size_compare_exchange_strong(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                            _z_memory_order_t success, _z_memory_order_t failure) {
    // to silence C4100 warning on MSVC
    (void)success;
    (void)failure;
    return atomic_compare_exchange_strong_explicit((_z_atomic_t *)&var->_value, expected, desired,
                                                   _z_memory_order_map[success], _z_memory_order_map[failure]);
}
bool _z_atomic_size_compare_exchange_weak(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                          _z_memory_order_t success, _z_memory_order_t failure) {
    // to silence C4100 warning on MSVC
    (void)success;
    (void)failure;
    return atomic_compare_exchange_weak_explicit((_z_atomic_t *)&var->_value, expected, desired,
                                                 _z_memory_order_map[success], _z_memory_order_map[failure]);
}
void _z_atomic_thread_fence(_z_memory_order_t order) { atomic_thread_fence(_z_memory_order_map[order]); }

#else
#include <atomic>
static_assert(sizeof(size_t) == sizeof(std::atomic<size_t>), "std::atomic<size_t> must have the same size as size_t");
static const std::memory_order _z_memory_order_map[] = {std::memory_order_relaxed, std::memory_order_acquire,
                                                        std::memory_order_release, std::memory_order_acq_rel,
                                                        std::memory_order_seq_cst};
typedef std::atomic<size_t> _z_atomic_t;
void _z_atomic_size_init(_z_atomic_size_t *var, size_t value) {
    reinterpret_cast<_z_atomic_t *>(&var->_value)->store(value, _z_memory_order_map[_z_memory_order_relaxed]);
}
size_t _z_atomic_size_load(_z_atomic_size_t *var, _z_memory_order_t order) {
    return reinterpret_cast<_z_atomic_t *>(&var->_value)->load(_z_memory_order_map[order]);
}
void _z_atomic_size_store(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    reinterpret_cast<_z_atomic_t *>(&var->_value)->store(val, _z_memory_order_map[order]);
}
size_t _z_atomic_size_fetch_add(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    return reinterpret_cast<_z_atomic_t *>(&var->_value)->fetch_add(val, _z_memory_order_map[order]);
}
size_t _z_atomic_size_fetch_sub(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    return reinterpret_cast<_z_atomic_t *>(&var->_value)->fetch_sub(val, _z_memory_order_map[order]);
}
bool _z_atomic_size_compare_exchange_strong(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                            _z_memory_order_t success, _z_memory_order_t failure) {
    return reinterpret_cast<_z_atomic_t *>(&var->_value)
        ->compare_exchange_strong(*expected, desired, _z_memory_order_map[success], _z_memory_order_map[failure]);
}
bool _z_atomic_size_compare_exchange_weak(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                          _z_memory_order_t success, _z_memory_order_t failure) {
    return reinterpret_cast<_z_atomic_t *>(&var->_value)
        ->compare_exchange_weak(*expected, desired, _z_memory_order_map[success], _z_memory_order_map[failure]);
}
void _z_atomic_thread_fence(_z_memory_order_t order) { std::atomic_thread_fence(_z_memory_order_map[order]); }
#endif
#else
#ifdef ZENOH_COMPILER_GCC
static const int _z_memory_order_map[] = {__ATOMIC_RELAXED, __ATOMIC_ACQUIRE, __ATOMIC_RELEASE, __ATOMIC_ACQ_REL,
                                          __ATOMIC_SEQ_CST};
void _z_atomic_size_init(_z_atomic_size_t *var, size_t value) {
    __atomic_store_n(&var->_value, value, _z_memory_order_map[_z_memory_order_relaxed]);
}
size_t _z_atomic_size_load(_z_atomic_size_t *var, _z_memory_order_t order) {
    return __atomic_load_n(&var->_value, _z_memory_order_map[order]);
}
void _z_atomic_size_store(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    __atomic_store_n(&var->_value, val, _z_memory_order_map[order]);
}
size_t _z_atomic_size_fetch_add(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    return __atomic_fetch_add(&var->_value, val, _z_memory_order_map[order]);
}
size_t _z_atomic_size_fetch_sub(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    return __atomic_fetch_sub(&var->_value, val, _z_memory_order_map[order]);
}
bool _z_atomic_size_compare_exchange_strong(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                            _z_memory_order_t success, _z_memory_order_t failure) {
    return __atomic_compare_exchange_n(&var->_value, expected, desired, false, _z_memory_order_map[success],
                                       _z_memory_order_map[failure]);
}
bool _z_atomic_size_compare_exchange_weak(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                          _z_memory_order_t success, _z_memory_order_t failure) {
    return __atomic_compare_exchange_n(&var->_value, expected, desired, true, _z_memory_order_map[success],
                                       _z_memory_order_map[failure]);
}
void _z_atomic_thread_fence(_z_memory_order_t order) { __atomic_thread_fence(_z_memory_order_map[order]); }
#else
#error "Atomic operations in C99 only exists for GCC, use GCC or C11 or deactivate multi-thread"
#endif
#endif
#else
void _z_atomic_size_init(_z_atomic_size_t *var, size_t value) { var->_value = value; }
size_t _z_atomic_size_load(_z_atomic_size_t *var, _z_memory_order_t order) {
    (void)order;
    return var->_value;
}
void _z_atomic_size_store(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    (void)order;
    var->_value = val;
}
size_t _z_atomic_size_fetch_add(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    (void)order;
    size_t old = var->_value;
    var->_value += val;
    return old;
}
size_t _z_atomic_size_fetch_sub(_z_atomic_size_t *var, size_t val, _z_memory_order_t order) {
    (void)order;
    size_t old = var->_value;
    var->_value -= val;
    return old;
}
bool _z_atomic_size_compare_exchange_strong(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                            _z_memory_order_t success, _z_memory_order_t failure) {
    (void)success;
    (void)failure;
    if (*expected == var->_value) {
        var->_value = desired;
        return true;
    }
    *expected = var->_value;
    return false;
}
bool _z_atomic_size_compare_exchange_weak(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                          _z_memory_order_t success, _z_memory_order_t failure) {
    (void)success;
    (void)failure;
    return _z_atomic_size_compare_exchange_strong(var, expected, desired, success, failure);
}
void _z_atomic_thread_fence(_z_memory_order_t order) {
    (void)order;
    // No-op in single-threaded mode
}
#endif
