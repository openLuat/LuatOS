#ifndef LUAT_POSIX_COMPAT_H
#define LUAT_POSIX_COMPAT_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* ------------------------------------------------------------------ */
/* Platform-specific pthread headers                                   */
/* ------------------------------------------------------------------ */
#if defined(_WIN32) || defined(_WIN64)
  /* Must define WIN32_LEAN_AND_MEAN and include winsock2.h BEFORE pthreads4w
   * (which pulls in windows.h) to prevent winsock v1 vs v2 conflicts and
   * LwIP socket type clashes.  This mirrors what uv.h used to do. */
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
  #endif
  #include <winsock2.h>
  #include <ws2tcpip.h>
  /* pthreads4w – installed via xmake's add_requires("pthreads4w") */
  #include <pthread.h>
  #include <semaphore.h>
  #include <windows.h>
  #include <time.h>   /* MSVC time.h for timespec / timespec_get */
  /* pthreads4w may not expose PTHREAD_MUTEX_RECURSIVE as a compile-time
   * constant on all versions; define a safe fallback. */
  #ifndef PTHREAD_MUTEX_RECURSIVE
  #define PTHREAD_MUTEX_RECURSIVE PTHREAD_MUTEX_RECURSIVE_NP
  #endif
  /* pthreads4w defines CLOCK_REALTIME / CLOCK_MONOTONIC in its time shim;
   * provide numeric fallbacks if the installed version omits them so that
   * clock_gettime() calls still compile.  The values (0 / 1) match what
   * pthreads4w's own clock_gettime() implementation expects. */
  #ifndef CLOCK_REALTIME
  #define CLOCK_REALTIME  0
  #endif
  #ifndef CLOCK_MONOTONIC
  #define CLOCK_MONOTONIC 1
  #endif

  /* pthreads4w does not always export clock_gettime as a linked symbol.
   * Provide our own CLOCK_REALTIME implementation using Windows FILETIME
   * so that luat_calc_abs_timeout compiles and links without libuv. */
  static inline int luat_win_clock_realtime(struct timespec *ts) {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    /* FILETIME: 100-ns intervals since 1601-01-01 */
    uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | (uint64_t)ft.dwLowDateTime;
    t -= 116444736000000000ULL; /* 100-ns intervals from 1601 to Unix epoch 1970 */
    ts->tv_sec  = (time_t)(t / 10000000ULL);
    ts->tv_nsec = (long)((t % 10000000ULL) * 100ULL);
    return 0;
  }
#elif defined(__EMSCRIPTEN__)
  #include <emscripten.h>
  #include <pthread.h>
  #include <semaphore.h>
  #include <time.h>
#else
  /* Linux / macOS */
  #include <pthread.h>
  #include <semaphore.h>
  #include <time.h>
  #include <unistd.h>
#endif

/* ------------------------------------------------------------------ */
/* luat_sleep_ms – sleep for `ms` milliseconds                        */
/* ------------------------------------------------------------------ */
static inline void luat_sleep_ms(uint32_t ms) {
#if defined(_WIN32) || defined(_WIN64)
    Sleep(ms);
#elif defined(__EMSCRIPTEN__)
    /* emscripten_sleep requires -sASYNCIFY or PROXY_TO_PTHREAD.
     * Under PROXY_TO_PTHREAD the main thread is a real pthread, so
     * nanosleep works normally. */
    struct timespec ts;
    ts.tv_sec  = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
#else
    struct timespec ts;
    ts.tv_sec  = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
#endif
}

/* ------------------------------------------------------------------ */
/* luat_monotonic_ns – monotonic clock in nanoseconds                 */
/* ------------------------------------------------------------------ */
static inline uint64_t luat_monotonic_ns(void) {
#if defined(_WIN32) || defined(_WIN64)
    static LARGE_INTEGER freq = {0};
    LARGE_INTEGER counter;
    static double ns_per_tick = 0.0;
    if (ns_per_tick == 0.0) {
        QueryPerformanceFrequency(&freq);
        ns_per_tick = 1000000000.0 / (double)freq.QuadPart;
    }
    QueryPerformanceCounter(&counter);
    /* Use double arithmetic – QPF is idempotent so this is thread-safe enough. */
    return (uint64_t)((double)counter.QuadPart * ns_per_tick);
#elif defined(__EMSCRIPTEN__)
    /* emscripten_get_now returns milliseconds as double */
    double ms = emscripten_get_now();
    return (uint64_t)(ms * 1000000.0);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
#endif
}

/* ------------------------------------------------------------------ */
/* luat_monotonic_ms – monotonic clock in milliseconds                */
/* ------------------------------------------------------------------ */
static inline uint64_t luat_monotonic_ms(void) {
    return luat_monotonic_ns() / 1000000ULL;
}

/* ------------------------------------------------------------------ */
/* luat_monotonic_us – monotonic clock in microseconds                */
/* ------------------------------------------------------------------ */
static inline uint64_t luat_monotonic_us(void) {
    return luat_monotonic_ns() / 1000ULL;
}

/* ------------------------------------------------------------------ */
/* Helper: compute absolute timespec from now + timeout_ms            */
/* ------------------------------------------------------------------ */
static inline void luat_calc_abs_timeout(struct timespec *abs, uint32_t timeout_ms) {
#if defined(_WIN32) || defined(_WIN64)
    /* pthreads4w pthread_cond_timedwait expects CLOCK_REALTIME absolute time.
     * Use our GetSystemTimeAsFileTime wrapper since pthreads4w may not export
     * clock_gettime as a linkable symbol. */
    struct timespec now;
    luat_win_clock_realtime(&now);
    uint64_t ns = (uint64_t)now.tv_nsec + (uint64_t)timeout_ms * 1000000ULL;
    abs->tv_sec  = now.tv_sec + (time_t)(ns / 1000000000ULL);
    abs->tv_nsec = (long)(ns % 1000000000ULL);
#else
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    uint64_t ns = (uint64_t)now.tv_nsec + (uint64_t)timeout_ms * 1000000ULL;
    abs->tv_sec  = now.tv_sec + (time_t)(ns / 1000000000ULL);
    abs->tv_nsec = (long)(ns % 1000000000ULL);
#endif
}

#endif /* LUAT_POSIX_COMPAT_H */
