# 1 "lvgl.h"
# 1 "<built-in>" 1
# 1 "<built-in>" 3
# 322 "<built-in>" 3
# 1 "<command line>" 1
# 1 "<built-in>" 2
# 1 "lvgl.h" 2
# 25 "lvgl.h"
# 1 "./src/lv_misc/lv_log.h" 1
# 16 "./src/lv_misc/lv_log.h"
# 1 "./src/lv_misc/../lv_conf_internal.h" 1
# 11 "./src/lv_misc/../lv_conf_internal.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 1 "../../../pycparser/utils/fake_libc_include/_fake_typedefs.h" 1



typedef int size_t;
typedef int __builtin_va_list;
typedef int __gnuc_va_list;
typedef int va_list;
typedef int __int8_t;
typedef int __uint8_t;
typedef int __int16_t;
typedef int __uint16_t;
typedef int __int_least16_t;
typedef int __uint_least16_t;
typedef int __int32_t;
typedef int __uint32_t;
typedef int __int64_t;
typedef int __uint64_t;
typedef int __int_least32_t;
typedef int __uint_least32_t;
typedef int __s8;
typedef int __u8;
typedef int __s16;
typedef int __u16;
typedef int __s32;
typedef int __u32;
typedef int __s64;
typedef int __u64;
typedef int _LOCK_T;
typedef int _LOCK_RECURSIVE_T;
typedef int _off_t;
typedef int __dev_t;
typedef int __uid_t;
typedef int __gid_t;
typedef int _off64_t;
typedef int _fpos_t;
typedef int _ssize_t;
typedef int wint_t;
typedef int _mbstate_t;
typedef int _flock_t;
typedef int _iconv_t;
typedef int __ULong;
typedef int __FILE;
typedef int ptrdiff_t;
typedef int wchar_t;
typedef int __off_t;
typedef int __pid_t;
typedef int __loff_t;
typedef int u_char;
typedef int u_short;
typedef int u_int;
typedef int u_long;
typedef int ushort;
typedef int uint;
typedef int clock_t;
typedef int time_t;
typedef int daddr_t;
typedef int caddr_t;
typedef int ino_t;
typedef int off_t;
typedef int dev_t;
typedef int uid_t;
typedef int gid_t;
typedef int pid_t;
typedef int key_t;
typedef int ssize_t;
typedef int mode_t;
typedef int nlink_t;
typedef int fd_mask;
typedef int _types_fd_set;
typedef int clockid_t;
typedef int timer_t;
typedef int useconds_t;
typedef int suseconds_t;
typedef int FILE;
typedef int fpos_t;
typedef int cookie_read_function_t;
typedef int cookie_write_function_t;
typedef int cookie_seek_function_t;
typedef int cookie_close_function_t;
typedef int cookie_io_functions_t;
typedef int div_t;
typedef int ldiv_t;
typedef int lldiv_t;
typedef int sigset_t;
typedef int __sigset_t;
typedef int _sig_func_ptr;
typedef int sig_atomic_t;
typedef int __tzrule_type;
typedef int __tzinfo_type;
typedef int mbstate_t;
typedef int sem_t;
typedef int pthread_t;
typedef int pthread_attr_t;
typedef int pthread_mutex_t;
typedef int pthread_mutexattr_t;
typedef int pthread_cond_t;
typedef int pthread_condattr_t;
typedef int pthread_key_t;
typedef int pthread_once_t;
typedef int pthread_rwlock_t;
typedef int pthread_rwlockattr_t;
typedef int pthread_spinlock_t;
typedef int pthread_barrier_t;
typedef int pthread_barrierattr_t;
typedef int jmp_buf;
typedef int rlim_t;
typedef int sa_family_t;
typedef int sigjmp_buf;
typedef int stack_t;
typedef int siginfo_t;
typedef int z_stream;


typedef int int8_t;
typedef int uint8_t;
typedef int int16_t;
typedef int uint16_t;
typedef int int32_t;
typedef int uint32_t;
typedef int int64_t;
typedef int uint64_t;


typedef int int_least8_t;
typedef int uint_least8_t;
typedef int int_least16_t;
typedef int uint_least16_t;
typedef int int_least32_t;
typedef int uint_least32_t;
typedef int int_least64_t;
typedef int uint_least64_t;


typedef int int_fast8_t;
typedef int uint_fast8_t;
typedef int int_fast16_t;
typedef int uint_fast16_t;
typedef int int_fast32_t;
typedef int uint_fast32_t;
typedef int int_fast64_t;
typedef int uint_fast64_t;


typedef int intptr_t;
typedef int uintptr_t;


typedef int intmax_t;
typedef int uintmax_t;


typedef _Bool bool;


typedef void* MirEGLNativeWindowType;
typedef void* MirEGLNativeDisplayType;
typedef struct MirConnection MirConnection;
typedef struct MirSurface MirSurface;
typedef struct MirSurfaceSpec MirSurfaceSpec;
typedef struct MirScreencast MirScreencast;
typedef struct MirPromptSession MirPromptSession;
typedef struct MirBufferStream MirBufferStream;
typedef struct MirPersistentId MirPersistentId;
typedef struct MirBlob MirBlob;
typedef struct MirDisplayConfig MirDisplayConfig;


typedef struct xcb_connection_t xcb_connection_t;
typedef uint32_t xcb_window_t;
typedef uint32_t xcb_visualid_t;
# 3 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 12 "./src/lv_misc/../lv_conf_internal.h" 2



# 1 "./src/lv_misc/../lv_conf_kconfig.h" 1
# 16 "./src/lv_misc/../lv_conf_internal.h" 2
# 39 "./src/lv_misc/../lv_conf_internal.h"
# 1 ".\\lv_conf.h" 1
# 16 ".\\lv_conf.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 17 ".\\lv_conf.h" 2
# 70 ".\\lv_conf.h"
typedef int16_t lv_coord_t;
# 155 ".\\lv_conf.h"
typedef void * lv_anim_user_data_t;
# 190 ".\\lv_conf.h"
typedef void * lv_group_user_data_t;
# 217 ".\\lv_conf.h"
typedef void * lv_fs_drv_user_data_t;
# 249 ".\\lv_conf.h"
typedef void * lv_img_decoder_user_data_t;
# 309 ".\\lv_conf.h"
typedef void * lv_disp_drv_user_data_t;
typedef void * lv_indev_drv_user_data_t;
# 446 ".\\lv_conf.h"
typedef void * lv_font_user_data_t;
# 40 "./src/lv_misc/../lv_conf_internal.h" 2







# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 48 "./src/lv_misc/../lv_conf_internal.h" 2
# 17 "./src/lv_misc/lv_log.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 18 "./src/lv_misc/lv_log.h" 2
# 33 "./src/lv_misc/lv_log.h"
struct _silence_gcc_warning;
struct _silence_gcc_warning;
struct _silence_gcc_warning;
struct _silence_gcc_warning;
struct _silence_gcc_warning;
struct _silence_gcc_warning;

typedef int8_t lv_log_level_t;
# 50 "./src/lv_misc/lv_log.h"
typedef void (*lv_log_print_g_cb_t)(lv_log_level_t level, const char *, uint32_t, const char *, const char *);
# 62 "./src/lv_misc/lv_log.h"
void lv_log_register_print_cb(lv_log_print_g_cb_t print_cb);
# 73 "./src/lv_misc/lv_log.h"
void _lv_log_add(lv_log_level_t level, const char * file, int line, const char * func, const char * format, ...);
# 26 "lvgl.h" 2
# 1 "./src/lv_misc/lv_task.h" 1
# 19 "./src/lv_misc/lv_task.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 20 "./src/lv_misc/lv_task.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 21 "./src/lv_misc/lv_task.h" 2
# 1 "./src/lv_misc/lv_mem.h" 1
# 18 "./src/lv_misc/lv_mem.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 19 "./src/lv_misc/lv_mem.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stddef.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stddef.h" 2
# 20 "./src/lv_misc/lv_mem.h" 2

# 1 "./src/lv_misc/lv_types.h" 1
# 22 "./src/lv_misc/lv_types.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 23 "./src/lv_misc/lv_types.h" 2
# 45 "./src/lv_misc/lv_types.h"
enum {
    LV_RES_INV = 0,

    LV_RES_OK,
};
typedef uint8_t lv_res_t;



typedef uintptr_t lv_uintptr_t;
# 22 "./src/lv_misc/lv_mem.h" 2
# 42 "./src/lv_misc/lv_mem.h"
typedef struct {
    uint32_t total_size;
    uint32_t free_cnt;
    uint32_t free_size;
    uint32_t free_biggest_size;
    uint32_t used_cnt;
    uint32_t max_used;
    uint8_t used_pct;
    uint8_t frag_pct;
} lv_mem_monitor_t;

typedef struct {
    void * p;
    uint16_t size;
    uint8_t used : 1;
} lv_mem_buf_t;

typedef lv_mem_buf_t lv_mem_buf_arr_t[16];
extern lv_mem_buf_arr_t _lv_mem_buf;
# 69 "./src/lv_misc/lv_mem.h"
void _lv_mem_init(void);





void _lv_mem_deinit(void);






void * lv_mem_alloc(size_t size);





void lv_mem_free(const void * data);
# 97 "./src/lv_misc/lv_mem.h"
void * lv_mem_realloc(void * data_p, size_t new_size);




void lv_mem_defrag(void);





lv_res_t lv_mem_test(void);






void lv_mem_monitor(lv_mem_monitor_t * mon_p);






uint32_t _lv_mem_get_size(const void * data);





void * _lv_mem_buf_get(uint32_t size);





void _lv_mem_buf_release(void * p);




void _lv_mem_buf_free_all(void);
# 205 "./src/lv_misc/lv_mem.h"
                      void * _lv_memcpy(void * dst, const void * src, size_t len);







                      static inline void * _lv_memcpy_small(void * dst, const void * src, size_t len)
{
    uint8_t * d8 = (uint8_t *)dst;
    const uint8_t * s8 = (const uint8_t *)src;

    while(len) {
        *d8 = *s8;
        d8++;
        s8++;
        len--;
    }

    return dst;
}







                      void _lv_memset(void * dst, uint8_t v, size_t len);






                      void _lv_memset_00(void * dst, size_t len);






                      void _lv_memset_ff(void * dst, size_t len);
# 22 "./src/lv_misc/lv_task.h" 2
# 1 "./src/lv_misc/lv_ll.h" 1
# 17 "./src/lv_misc/lv_ll.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 18 "./src/lv_misc/lv_ll.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stddef.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stddef.h" 2
# 19 "./src/lv_misc/lv_ll.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 20 "./src/lv_misc/lv_ll.h" 2
# 30 "./src/lv_misc/lv_ll.h"
typedef uint8_t lv_ll_node_t;


typedef struct {
    uint32_t n_size;
    lv_ll_node_t * head;
    lv_ll_node_t * tail;
} lv_ll_t;
# 48 "./src/lv_misc/lv_ll.h"
void _lv_ll_init(lv_ll_t * ll_p, uint32_t node_size);






void * _lv_ll_ins_head(lv_ll_t * ll_p);







void * _lv_ll_ins_prev(lv_ll_t * ll_p, void * n_act);






void * _lv_ll_ins_tail(lv_ll_t * ll_p);







void _lv_ll_remove(lv_ll_t * ll_p, void * node_p);





void _lv_ll_clear(lv_ll_t * ll_p);
# 94 "./src/lv_misc/lv_ll.h"
void _lv_ll_chg_list(lv_ll_t * ll_ori_p, lv_ll_t * ll_new_p, void * node, bool head);






void * _lv_ll_get_head(const lv_ll_t * ll_p);






void * _lv_ll_get_tail(const lv_ll_t * ll_p);







void * _lv_ll_get_next(const lv_ll_t * ll_p, const void * n_act);







void * _lv_ll_get_prev(const lv_ll_t * ll_p, const void * n_act);






uint32_t _lv_ll_get_len(const lv_ll_t * ll_p);
# 147 "./src/lv_misc/lv_ll.h"
void _lv_ll_move_before(lv_ll_t * ll_p, void * n_act, void * n_after);






bool _lv_ll_is_empty(lv_ll_t * ll_p);
# 23 "./src/lv_misc/lv_task.h" 2
# 36 "./src/lv_misc/lv_task.h"
struct _lv_task_t;




typedef void (*lv_task_cb_t)(struct _lv_task_t *);




enum {
    LV_TASK_PRIO_OFF = 0,
    LV_TASK_PRIO_LOWEST,
    LV_TASK_PRIO_LOW,
    LV_TASK_PRIO_MID,
    LV_TASK_PRIO_HIGH,
    LV_TASK_PRIO_HIGHEST,
    _LV_TASK_PRIO_NUM,
};
typedef uint8_t lv_task_prio_t;




typedef struct _lv_task_t {
    uint32_t period;
    uint32_t last_run;
    lv_task_cb_t task_cb;

    void * user_data;

    int32_t repeat_count;
    uint8_t prio : 3;
} lv_task_t;
# 78 "./src/lv_misc/lv_task.h"
void _lv_task_core_init(void);







                          uint32_t lv_task_handler(void);
# 95 "./src/lv_misc/lv_task.h"
lv_task_t * lv_task_create_basic(void);
# 107 "./src/lv_misc/lv_task.h"
lv_task_t * lv_task_create(lv_task_cb_t task_xcb, uint32_t period, lv_task_prio_t prio, void * user_data);





void lv_task_del(lv_task_t * task);






void lv_task_set_cb(lv_task_t * task, lv_task_cb_t task_cb);






void lv_task_set_prio(lv_task_t * task, lv_task_prio_t prio);






void lv_task_set_period(lv_task_t * task, uint32_t period);





void lv_task_ready(lv_task_t * task);






void lv_task_set_repeat_count(lv_task_t * task, int32_t repeat_count);






void lv_task_reset(lv_task_t * task);





void lv_task_enable(bool en);





uint8_t lv_task_get_idle(void);






lv_task_t * lv_task_get_next(lv_task_t * task);
# 27 "lvgl.h" 2
# 1 "./src/lv_misc/lv_math.h" 1
# 17 "./src/lv_misc/lv_math.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 18 "./src/lv_misc/lv_math.h" 2
# 49 "./src/lv_misc/lv_math.h"
typedef struct {
    uint16_t i;
    uint16_t f;
} lv_sqrt_res_t;
# 64 "./src/lv_misc/lv_math.h"
                      int16_t _lv_trigo_sin(int16_t angle);
# 77 "./src/lv_misc/lv_math.h"
uint32_t _lv_bezier3(uint32_t t, uint32_t u0, uint32_t u1, uint32_t u2, uint32_t u3);







uint16_t _lv_atan2(int x, int y);
# 99 "./src/lv_misc/lv_math.h"
                      void _lv_sqrt(uint32_t x, lv_sqrt_res_t * q, uint32_t mask);
# 109 "./src/lv_misc/lv_math.h"
int64_t _lv_pow(int64_t base, int8_t exp);
# 120 "./src/lv_misc/lv_math.h"
int32_t _lv_map(int32_t x, int32_t min_in, int32_t max_in, int32_t min, int32_t max);
# 28 "lvgl.h" 2
# 1 "./src/lv_misc/lv_async.h" 1
# 31 "./src/lv_misc/lv_async.h"
typedef void (*lv_async_cb_t)(void *);
# 45 "./src/lv_misc/lv_async.h"
lv_res_t lv_async_call(lv_async_cb_t async_xcb, void * user_data);
# 29 "lvgl.h" 2

# 1 "./src/lv_hal/lv_hal.h" 1
# 16 "./src/lv_hal/lv_hal.h"
# 1 "./src/lv_hal/lv_hal_disp.h" 1
# 18 "./src/lv_hal/lv_hal_disp.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 19 "./src/lv_hal/lv_hal_disp.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 20 "./src/lv_hal/lv_hal_disp.h" 2
# 1 "./src/lv_hal/lv_hal.h" 1
# 21 "./src/lv_hal/lv_hal_disp.h" 2
# 1 "./src/lv_hal/../lv_misc/lv_color.h" 1
# 33 "./src/lv_hal/../lv_misc/lv_color.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 34 "./src/lv_hal/../lv_misc/lv_color.h" 2
# 60 "./src/lv_hal/../lv_misc/lv_color.h"
enum {
    LV_OPA_TRANSP = 0,
    LV_OPA_0 = 0,
    LV_OPA_10 = 25,
    LV_OPA_20 = 51,
    LV_OPA_30 = 76,
    LV_OPA_40 = 102,
    LV_OPA_50 = 127,
    LV_OPA_60 = 153,
    LV_OPA_70 = 178,
    LV_OPA_80 = 204,
    LV_OPA_90 = 229,
    LV_OPA_100 = 255,
    LV_OPA_COVER = 255,
};
# 225 "./src/lv_hal/../lv_misc/lv_color.h"
typedef union {
    uint8_t full;
    union {
        uint8_t blue : 1;
        uint8_t green : 1;
        uint8_t red : 1;
    } ch;
} lv_color1_t;

typedef union {
    struct {
        uint8_t blue : 2;
        uint8_t green : 3;
        uint8_t red : 3;
    } ch;
    uint8_t full;
} lv_color8_t;

typedef union {
    struct {

        uint16_t blue : 5;
        uint16_t green : 6;
        uint16_t red : 5;






    } ch;
    uint16_t full;
} lv_color16_t;

typedef union {
    struct {
        uint8_t blue;
        uint8_t green;
        uint8_t red;
        uint8_t alpha;
    } ch;
    uint32_t full;
} lv_color32_t;

typedef uint16_t lv_color_int_t;
typedef lv_color16_t lv_color_t;

typedef struct {
    uint16_t h;
    uint8_t s;
    uint8_t v;
} lv_color_hsv_t;



typedef uint8_t lv_opa_t;
# 300 "./src/lv_hal/../lv_misc/lv_color.h"
static inline uint8_t lv_color_to1(lv_color_t color)
{
# 312 "./src/lv_hal/../lv_misc/lv_color.h"
    if(((color).ch.red & 0x10) || ((color).ch.green & 0x20) || ((color).ch.blue & 0x10)) {
        return 1;
    }
    else {
        return 0;
    }
# 326 "./src/lv_hal/../lv_misc/lv_color.h"
}

static inline uint8_t lv_color_to8(lv_color_t color)
{
# 338 "./src/lv_hal/../lv_misc/lv_color.h"
    lv_color8_t ret;
    (ret).ch.red = (uint8_t)(((color).ch.red >> 2) & 0x7U);
    (ret).ch.green = (uint8_t)(((color).ch.green >> 3) & 0x7U);
    (ret).ch.blue = (uint8_t)(((color).ch.blue >> 3) & 0x3U);
    return ret.full;







}

static inline uint16_t lv_color_to16(lv_color_t color)
{
# 366 "./src/lv_hal/../lv_misc/lv_color.h"
    return color.full;







}

static inline uint32_t lv_color_to32(lv_color_t color)
{
# 420 "./src/lv_hal/../lv_misc/lv_color.h"
    lv_color32_t ret;
    (ret).ch.red = (uint8_t)((((color).ch.red * 263 + 7) >> 5) & 0xFF);
    (ret).ch.green = (uint8_t)((((color).ch.green * 259 + 3) >> 6) & 0xFF);
    (ret).ch.blue = (uint8_t)((((color).ch.blue * 263 + 7) >> 5) & 0xFF);
    (ret).ch.alpha = (uint8_t)((0xFF) & 0xFF);
    return ret.full;



}
# 440 "./src/lv_hal/../lv_misc/lv_color.h"
                      static inline lv_color_t lv_color_mix(lv_color_t c1, lv_color_t c2, uint8_t mix)
{
    lv_color_t ret;


    (ret).ch.red = (uint8_t)((((uint32_t)((uint32_t) ((uint16_t) (c1).ch.red * mix + (c2).ch.red * (255 - mix) + 128) * 0x8081) >> 0x17)) & 0x1FU);

    (ret).ch.green = (uint8_t)((((uint32_t)((uint32_t) ((uint16_t) (c1).ch.green * mix + (c2).ch.green * (255 - mix) + 128) * 0x8081) >> 0x17)) & 0x3FU);

    (ret).ch.blue = (uint8_t)((((uint32_t)((uint32_t) ((uint16_t) (c1).ch.blue * mix + (c2).ch.blue * (255 - mix) + 128) * 0x8081) >> 0x17)) & 0x1FU);

    do {} while(0);





    return ret;
}

                      static inline void lv_color_premult(lv_color_t c, uint8_t mix, uint16_t * out)
{

    out[0] = (uint16_t) (c).ch.red * mix;
    out[1] = (uint16_t) (c).ch.green * mix;
    out[2] = (uint16_t) (c).ch.blue * mix;
# 474 "./src/lv_hal/../lv_misc/lv_color.h"
}
# 485 "./src/lv_hal/../lv_misc/lv_color.h"
                      static inline lv_color_t lv_color_mix_premult(uint16_t * premult_c1, lv_color_t c2, uint8_t mix)
{
    lv_color_t ret;


    (ret).ch.red = (uint8_t)((((uint32_t)((uint32_t) (premult_c1[0] + (c2).ch.red * mix + 128) * 0x8081) >> 0x17)) & 0x1FU);
    (ret).ch.green = (uint8_t)((((uint32_t)((uint32_t) (premult_c1[1] + (c2).ch.green * mix + 128) * 0x8081) >> 0x17)) & 0x3FU);
    (ret).ch.blue = (uint8_t)((((uint32_t)((uint32_t) (premult_c1[2] + (c2).ch.blue * mix + 128) * 0x8081) >> 0x17)) & 0x1FU);
    do {} while(0);
# 504 "./src/lv_hal/../lv_misc/lv_color.h"
    return ret;
}
# 516 "./src/lv_hal/../lv_misc/lv_color.h"
                      static inline void lv_color_mix_with_alpha(lv_color_t bg_color, lv_opa_t bg_opa,
                                                                 lv_color_t fg_color, lv_opa_t fg_opa,
                                                                 lv_color_t * res_color, lv_opa_t * res_opa)
{

    if(fg_opa >= 253 || bg_opa <= 2) {
        res_color->full = fg_color.full;
        *res_opa = fg_opa;
    }

    else if(fg_opa <= 2) {
        res_color->full = bg_color.full;
        *res_opa = bg_opa;
    }

    else if(bg_opa >= 253) {
        *res_color = lv_color_mix(fg_color, bg_color, fg_opa);
        *res_opa = LV_OPA_COVER;
    }

    else {

        static lv_opa_t fg_opa_save = 0;
        static lv_opa_t bg_opa_save = 0;
        static lv_color_t fg_color_save = {{0x00, 0x00, 0x00}};
        static lv_color_t bg_color_save = {{0x00, 0x00, 0x00}};
        static lv_color_t res_color_saved = {{0x00, 0x00, 0x00}};
        static lv_opa_t res_opa_saved = 0;

        if(fg_opa != fg_opa_save || bg_opa != bg_opa_save || fg_color.full != fg_color_save.full ||
           bg_color.full != bg_color_save.full) {
            fg_opa_save = fg_opa;
            bg_opa_save = bg_opa;
            fg_color_save.full = fg_color.full;
            bg_color_save.full = bg_color.full;


            res_opa_saved = 255 - ((uint16_t)((uint16_t)(255 - fg_opa) * (255 - bg_opa)) >> 8);
            if(res_opa_saved == 0) {
                while(1)
                    ;
            }
            lv_opa_t ratio = (uint16_t)((uint16_t)fg_opa * 255) / res_opa_saved;
            res_color_saved = lv_color_mix(fg_color, bg_color, ratio);

        }

        res_color->full = res_color_saved.full;
        *res_opa = res_opa_saved;
    }
}
# 575 "./src/lv_hal/../lv_misc/lv_color.h"
static inline uint8_t lv_color_brightness(lv_color_t color)
{
    lv_color32_t c32;
    c32.full = lv_color_to32(color);
    uint16_t bright = (uint16_t)(3u * (c32).ch.red + (c32).ch.blue + 4u * (c32).ch.green);
    return (uint8_t)(bright >> 3);
}

static inline lv_color_t lv_color_make(uint8_t r, uint8_t g, uint8_t b)
{
    return ((lv_color_t){{(uint8_t)((b >> 3) & 0x1FU), (uint8_t)((g >> 2) & 0x3FU), (uint8_t)((r >> 3) & 0x1FU)}});
}

static inline lv_color_t lv_color_hex(uint32_t c)
{
    return lv_color_make((uint8_t)((c >> 16) & 0xFF), (uint8_t)((c >> 8) & 0xFF), (uint8_t)(c & 0xFF));
}

static inline lv_color_t lv_color_hex3(uint32_t c)
{
    return lv_color_make((uint8_t)(((c >> 4) & 0xF0) | ((c >> 8) & 0xF)), (uint8_t)((c & 0xF0) | ((c & 0xF0) >> 4)),
                         (uint8_t)((c & 0xF) | ((c & 0xF) << 4)));
}



                      void lv_color_fill(lv_color_t * buf, lv_color_t color, uint32_t px_num);


lv_color_t lv_color_lighten(lv_color_t c, lv_opa_t lvl);

lv_color_t lv_color_darken(lv_color_t c, lv_opa_t lvl);
# 615 "./src/lv_hal/../lv_misc/lv_color.h"
lv_color_t lv_color_hsv_to_rgb(uint16_t h, uint8_t s, uint8_t v);
# 624 "./src/lv_hal/../lv_misc/lv_color.h"
lv_color_hsv_t lv_color_rgb_to_hsv(uint8_t r8, uint8_t g8, uint8_t b8);






lv_color_hsv_t lv_color_to_hsv(lv_color_t color);
# 22 "./src/lv_hal/lv_hal_disp.h" 2
# 1 "./src/lv_hal/../lv_misc/lv_area.h" 1
# 17 "./src/lv_hal/../lv_misc/lv_area.h"
# 1 "../../../pycparser/utils/fake_libc_include\\string.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\string.h" 2
# 18 "./src/lv_hal/../lv_misc/lv_area.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 19 "./src/lv_hal/../lv_misc/lv_area.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 20 "./src/lv_hal/../lv_misc/lv_area.h" 2
# 29 "./src/lv_hal/../lv_misc/lv_area.h"
struct _silence_gcc_warning;
struct _silence_gcc_warning;
# 39 "./src/lv_hal/../lv_misc/lv_area.h"
typedef struct {
    lv_coord_t x;
    lv_coord_t y;
} lv_point_t;


typedef struct {
    lv_coord_t x1;
    lv_coord_t y1;
    lv_coord_t x2;
    lv_coord_t y2;
} lv_area_t;


enum {
    LV_ALIGN_CENTER = 0,
    LV_ALIGN_IN_TOP_LEFT,
    LV_ALIGN_IN_TOP_MID,
    LV_ALIGN_IN_TOP_RIGHT,
    LV_ALIGN_IN_BOTTOM_LEFT,
    LV_ALIGN_IN_BOTTOM_MID,
    LV_ALIGN_IN_BOTTOM_RIGHT,
    LV_ALIGN_IN_LEFT_MID,
    LV_ALIGN_IN_RIGHT_MID,
    LV_ALIGN_OUT_TOP_LEFT,
    LV_ALIGN_OUT_TOP_MID,
    LV_ALIGN_OUT_TOP_RIGHT,
    LV_ALIGN_OUT_BOTTOM_LEFT,
    LV_ALIGN_OUT_BOTTOM_MID,
    LV_ALIGN_OUT_BOTTOM_RIGHT,
    LV_ALIGN_OUT_LEFT_TOP,
    LV_ALIGN_OUT_LEFT_MID,
    LV_ALIGN_OUT_LEFT_BOTTOM,
    LV_ALIGN_OUT_RIGHT_TOP,
    LV_ALIGN_OUT_RIGHT_MID,
    LV_ALIGN_OUT_RIGHT_BOTTOM,
};
typedef uint8_t lv_align_t;
# 90 "./src/lv_hal/../lv_misc/lv_area.h"
void lv_area_set(lv_area_t * area_p, lv_coord_t x1, lv_coord_t y1, lv_coord_t x2, lv_coord_t y2);






inline static void lv_area_copy(lv_area_t * dest, const lv_area_t * src)
{
    _lv_memcpy_small(dest, src, sizeof(lv_area_t));
}






static inline lv_coord_t lv_area_get_width(const lv_area_t * area_p)
{
    return (lv_coord_t)(area_p->x2 - area_p->x1 + 1);
}






static inline lv_coord_t lv_area_get_height(const lv_area_t * area_p)
{
    return (lv_coord_t)(area_p->y2 - area_p->y1 + 1);
}






void lv_area_set_width(lv_area_t * area_p, lv_coord_t w);






void lv_area_set_height(lv_area_t * area_p, lv_coord_t h);







void _lv_area_set_pos(lv_area_t * area_p, lv_coord_t x, lv_coord_t y);






uint32_t lv_area_get_size(const lv_area_t * area_p);
# 158 "./src/lv_hal/../lv_misc/lv_area.h"
bool _lv_area_intersect(lv_area_t * res_p, const lv_area_t * a1_p, const lv_area_t * a2_p);







void _lv_area_join(lv_area_t * a_res_p, const lv_area_t * a1_p, const lv_area_t * a2_p);
# 175 "./src/lv_hal/../lv_misc/lv_area.h"
bool _lv_area_is_point_on(const lv_area_t * a_p, const lv_point_t * p_p, lv_coord_t radius);







bool _lv_area_is_on(const lv_area_t * a1_p, const lv_area_t * a2_p);
# 192 "./src/lv_hal/../lv_misc/lv_area.h"
bool _lv_area_is_in(const lv_area_t * ain_p, const lv_area_t * aholder_p, lv_coord_t radius);
# 201 "./src/lv_hal/../lv_misc/lv_area.h"
void _lv_area_align(const lv_area_t * base, const lv_area_t * to_align, lv_align_t align, lv_point_t * res);
# 23 "./src/lv_hal/lv_hal_disp.h" 2
# 41 "./src/lv_hal/lv_hal_disp.h"
struct _disp_t;
struct _disp_drv_t;




typedef struct {
    void * buf1;
    void * buf2;


    void * buf_act;
    uint32_t size;
    lv_area_t area;

    volatile int flushing;

    volatile int flushing_last;
    volatile uint32_t last_area : 1;
    volatile uint32_t last_part : 1;
} lv_disp_buf_t;


typedef enum {
    LV_DISP_ROT_NONE = 0,
    LV_DISP_ROT_90,
    LV_DISP_ROT_180,
    LV_DISP_ROT_270
} lv_disp_rot_t;




typedef struct _disp_drv_t {

    lv_coord_t hor_res;
    lv_coord_t ver_res;



    lv_disp_buf_t * buffer;


    uint32_t antialiasing : 1;

    uint32_t rotated : 2;
    uint32_t sw_rotate : 1;
# 98 "./src/lv_hal/lv_hal_disp.h"
    uint32_t dpi : 10;



    void (*flush_cb)(struct _disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p);



    void (*rounder_cb)(struct _disp_drv_t * disp_drv, lv_area_t * area);




    void (*set_px_cb)(struct _disp_drv_t * disp_drv, uint8_t * buf, lv_coord_t buf_w, lv_coord_t x, lv_coord_t y,
                      lv_color_t color, lv_opa_t opa);



    void (*monitor_cb)(struct _disp_drv_t * disp_drv, uint32_t time, uint32_t px);




    void (*wait_cb)(struct _disp_drv_t * disp_drv);


    void (*clean_dcache_cb)(struct _disp_drv_t * disp_drv);


    void (*gpu_wait_cb)(struct _disp_drv_t * disp_drv);
# 142 "./src/lv_hal/lv_hal_disp.h"
    lv_color_t color_chroma_key;





} lv_disp_drv_t;

struct _lv_obj_t;





typedef struct _disp_t {

    lv_disp_drv_t driver;


    lv_task_t * refr_task;


    lv_ll_t scr_ll;
    struct _lv_obj_t * act_scr;
    struct _lv_obj_t * prev_scr;

    struct _lv_obj_t * scr_to_load;

    struct _lv_obj_t * top_layer;
    struct _lv_obj_t * sys_layer;

uint8_t del_prev :
    1;

    lv_color_t bg_color;
    const void * bg_img;
    lv_opa_t bg_opa;


    lv_area_t inv_areas[32];
    uint8_t inv_area_joined[32];
    uint32_t inv_p : 10;


    uint32_t last_activity_time;
} lv_disp_t;

typedef enum {
    LV_DISP_SIZE_SMALL,
    LV_DISP_SIZE_MEDIUM,
    LV_DISP_SIZE_LARGE,
    LV_DISP_SIZE_EXTRA_LARGE,
} lv_disp_size_t;
# 206 "./src/lv_hal/lv_hal_disp.h"
void lv_disp_drv_init(lv_disp_drv_t * driver);
# 223 "./src/lv_hal/lv_hal_disp.h"
void lv_disp_buf_init(lv_disp_buf_t * disp_buf, void * buf1, void * buf2, uint32_t size_in_px_cnt);







lv_disp_t * lv_disp_drv_register(lv_disp_drv_t * driver);






void lv_disp_drv_update(lv_disp_t * disp, lv_disp_drv_t * new_drv);





void lv_disp_remove(lv_disp_t * disp);





void lv_disp_set_default(lv_disp_t * disp);





lv_disp_t * lv_disp_get_default(void);






lv_coord_t lv_disp_get_hor_res(lv_disp_t * disp);






lv_coord_t lv_disp_get_ver_res(lv_disp_t * disp);






bool lv_disp_get_antialiasing(lv_disp_t * disp);






lv_coord_t lv_disp_get_dpi(lv_disp_t * disp);






lv_disp_size_t lv_disp_get_size_category(lv_disp_t * disp);






void lv_disp_set_rotation(lv_disp_t * disp, lv_disp_rot_t rotation);






lv_disp_rot_t lv_disp_get_rotation(lv_disp_t * disp);







                         void lv_disp_flush_ready(lv_disp_drv_t * disp_drv);







                         bool lv_disp_flush_is_last(lv_disp_drv_t * disp_drv);
# 330 "./src/lv_hal/lv_hal_disp.h"
lv_disp_t * lv_disp_get_next(lv_disp_t * disp);






lv_disp_buf_t * lv_disp_get_buf(lv_disp_t * disp);





uint16_t lv_disp_get_inv_buf_size(lv_disp_t * disp);





void _lv_disp_pop_from_inv_buf(lv_disp_t * disp, uint16_t num);






bool lv_disp_is_double_buf(lv_disp_t * disp);







bool lv_disp_is_true_double_buf(lv_disp_t * disp);
# 17 "./src/lv_hal/lv_hal.h" 2
# 1 "./src/lv_hal/lv_hal_indev.h" 1
# 20 "./src/lv_hal/lv_hal_indev.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 21 "./src/lv_hal/lv_hal_indev.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 22 "./src/lv_hal/lv_hal_indev.h" 2
# 33 "./src/lv_hal/lv_hal_indev.h"
struct _lv_obj_t;
struct _disp_t;
struct _lv_indev_t;
struct _lv_indev_drv_t;


enum {
    LV_INDEV_TYPE_NONE,
    LV_INDEV_TYPE_POINTER,
    LV_INDEV_TYPE_KEYPAD,
    LV_INDEV_TYPE_BUTTON,

    LV_INDEV_TYPE_ENCODER,
};
typedef uint8_t lv_indev_type_t;


enum { LV_INDEV_STATE_REL = 0, LV_INDEV_STATE_PR };
typedef uint8_t lv_indev_state_t;

enum {
    LV_DRAG_DIR_HOR = 0x1,
    LV_DRAG_DIR_VER = 0x2,
    LV_DRAG_DIR_BOTH = 0x3,
    LV_DRAG_DIR_ONE = 0x4,
};

typedef uint8_t lv_drag_dir_t;

enum {
    LV_GESTURE_DIR_TOP,
    LV_GESTURE_DIR_BOTTOM,
    LV_GESTURE_DIR_LEFT,
    LV_GESTURE_DIR_RIGHT,
};
typedef uint8_t lv_gesture_dir_t;


typedef struct {
    lv_point_t point;
    uint32_t key;
    uint32_t btn_id;
    int16_t enc_diff;

    lv_indev_state_t state;
} lv_indev_data_t;


typedef struct _lv_indev_drv_t {


    lv_indev_type_t type;




    bool (*read_cb)(struct _lv_indev_drv_t * indev_drv, lv_indev_data_t * data);



    void (*feedback_cb)(struct _lv_indev_drv_t *, uint8_t);






    struct _disp_t * disp;


    lv_task_t * read_task;


    uint8_t drag_limit;


    uint8_t drag_throw;


    uint8_t gesture_min_velocity;


    uint8_t gesture_limit;


    uint16_t long_press_time;


    uint16_t long_press_rep_time;
} lv_indev_drv_t;




typedef struct _lv_indev_proc_t {
    lv_indev_state_t state;
    union {
        struct {

            lv_point_t act_point;
            lv_point_t last_point;
            lv_point_t last_raw_point;
            lv_point_t vect;
            lv_point_t drag_sum;
            lv_point_t drag_throw_vect;
            struct _lv_obj_t * act_obj;
            struct _lv_obj_t * last_obj;

            struct _lv_obj_t * last_pressed;

            lv_gesture_dir_t gesture_dir;
            lv_point_t gesture_sum;

            uint8_t drag_limit_out : 1;
            uint8_t drag_in_prog : 1;
            lv_drag_dir_t drag_dir : 3;
            uint8_t gesture_sent : 1;
        } pointer;
        struct {

            lv_indev_state_t last_state;
            uint32_t last_key;
        } keypad;
    } types;

    uint32_t pr_timestamp;
    uint32_t longpr_rep_timestamp;


    uint8_t long_pr_sent : 1;
    uint8_t reset_query : 1;
    uint8_t disabled : 1;
    uint8_t wait_until_release : 1;
} lv_indev_proc_t;

struct _lv_obj_t;
struct _lv_group_t;



typedef struct _lv_indev_t {
    lv_indev_drv_t driver;
    lv_indev_proc_t proc;
    struct _lv_obj_t * cursor;
    struct _lv_group_t * group;
    const lv_point_t * btn_points;

} lv_indev_t;
# 192 "./src/lv_hal/lv_hal_indev.h"
void lv_indev_drv_init(lv_indev_drv_t * driver);






lv_indev_t * lv_indev_drv_register(lv_indev_drv_t * driver);






void lv_indev_drv_update(lv_indev_t * indev, lv_indev_drv_t * new_drv);







lv_indev_t * lv_indev_get_next(lv_indev_t * indev);







bool _lv_indev_read(lv_indev_t * indev, lv_indev_data_t * data);
# 18 "./src/lv_hal/lv_hal.h" 2
# 1 "./src/lv_hal/lv_hal_tick.h" 1
# 18 "./src/lv_hal/lv_hal_tick.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 19 "./src/lv_hal/lv_hal_tick.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 20 "./src/lv_hal/lv_hal_tick.h" 2
# 42 "./src/lv_hal/lv_hal_tick.h"
                      void lv_tick_inc(uint32_t tick_period);







uint32_t lv_tick_get(void);






uint32_t lv_tick_elaps(uint32_t prev_tick);
# 19 "./src/lv_hal/lv_hal.h" 2
# 31 "lvgl.h" 2

# 1 "./src/lv_core/lv_obj.h" 1
# 18 "./src/lv_core/lv_obj.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stddef.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stddef.h" 2
# 19 "./src/lv_core/lv_obj.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 20 "./src/lv_core/lv_obj.h" 2
# 1 "./src/lv_core/lv_style.h" 1
# 16 "./src/lv_core/lv_style.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 17 "./src/lv_core/lv_style.h" 2
# 1 "./src/lv_core/../lv_font/lv_font.h" 1
# 17 "./src/lv_core/../lv_font/lv_font.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 18 "./src/lv_core/../lv_font/lv_font.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stddef.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stddef.h" 2
# 19 "./src/lv_core/../lv_font/lv_font.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 20 "./src/lv_core/../lv_font/lv_font.h" 2

# 1 "./src/lv_core/../lv_font/lv_symbol_def.h" 1
# 94 "./src/lv_core/../lv_font/lv_symbol_def.h"
enum {
    _LV_STR_SYMBOL_AUDIO,
    _LV_STR_SYMBOL_VIDEO,
    _LV_STR_SYMBOL_LIST,
    _LV_STR_SYMBOL_OK,
    _LV_STR_SYMBOL_CLOSE,
    _LV_STR_SYMBOL_POWER,
    _LV_STR_SYMBOL_SETTINGS,
    _LV_STR_SYMBOL_HOME,
    _LV_STR_SYMBOL_DOWNLOAD,
    _LV_STR_SYMBOL_DRIVE,
    _LV_STR_SYMBOL_REFRESH,
    _LV_STR_SYMBOL_MUTE,
    _LV_STR_SYMBOL_VOLUME_MID,
    _LV_STR_SYMBOL_VOLUME_MAX,
    _LV_STR_SYMBOL_IMAGE,
    _LV_STR_SYMBOL_EDIT,
    _LV_STR_SYMBOL_PREV,
    _LV_STR_SYMBOL_PLAY,
    _LV_STR_SYMBOL_PAUSE,
    _LV_STR_SYMBOL_STOP,
    _LV_STR_SYMBOL_NEXT,
    _LV_STR_SYMBOL_EJECT,
    _LV_STR_SYMBOL_LEFT,
    _LV_STR_SYMBOL_RIGHT,
    _LV_STR_SYMBOL_PLUS,
    _LV_STR_SYMBOL_MINUS,
    _LV_STR_SYMBOL_EYE_OPEN,
    _LV_STR_SYMBOL_EYE_CLOSE,
    _LV_STR_SYMBOL_WARNING,
    _LV_STR_SYMBOL_SHUFFLE,
    _LV_STR_SYMBOL_UP,
    _LV_STR_SYMBOL_DOWN,
    _LV_STR_SYMBOL_LOOP,
    _LV_STR_SYMBOL_DIRECTORY,
    _LV_STR_SYMBOL_UPLOAD,
    _LV_STR_SYMBOL_CALL,
    _LV_STR_SYMBOL_CUT,
    _LV_STR_SYMBOL_COPY,
    _LV_STR_SYMBOL_SAVE,
    _LV_STR_SYMBOL_CHARGE,
    _LV_STR_SYMBOL_PASTE,
    _LV_STR_SYMBOL_BELL,
    _LV_STR_SYMBOL_KEYBOARD,
    _LV_STR_SYMBOL_GPS,
    _LV_STR_SYMBOL_FILE,
    _LV_STR_SYMBOL_WIFI,
    _LV_STR_SYMBOL_BATTERY_FULL,
    _LV_STR_SYMBOL_BATTERY_3,
    _LV_STR_SYMBOL_BATTERY_2,
    _LV_STR_SYMBOL_BATTERY_1,
    _LV_STR_SYMBOL_BATTERY_EMPTY,
    _LV_STR_SYMBOL_USB,
    _LV_STR_SYMBOL_BLUETOOTH,
    _LV_STR_SYMBOL_TRASH,
    _LV_STR_SYMBOL_BACKSPACE,
    _LV_STR_SYMBOL_SD_CARD,
    _LV_STR_SYMBOL_NEW_LINE,
    _LV_STR_SYMBOL_DUMMY,
    _LV_STR_SYMBOL_BULLET,
};
# 22 "./src/lv_core/../lv_font/lv_font.h" 2
# 37 "./src/lv_core/../lv_font/lv_font.h"
typedef struct {
    uint16_t adv_w;
    uint16_t box_w;
    uint16_t box_h;
    int16_t ofs_x;
    int16_t ofs_y;
    uint8_t bpp;
} lv_font_glyph_dsc_t;


enum {
    LV_FONT_SUBPX_NONE,
    LV_FONT_SUBPX_HOR,
    LV_FONT_SUBPX_VER,
    LV_FONT_SUBPX_BOTH,
};

typedef uint8_t lv_font_subpx_t;


typedef struct _lv_font_struct {

    bool (*get_glyph_dsc)(const struct _lv_font_struct *, lv_font_glyph_dsc_t *, uint32_t letter, uint32_t letter_next);


    const uint8_t * (*get_glyph_bitmap)(const struct _lv_font_struct *, uint32_t);


    lv_coord_t line_height;
    lv_coord_t base_line;
    uint8_t subpx : 2;

    int8_t underline_position;
    int8_t underline_thickness;

    void * dsc;




} lv_font_t;
# 89 "./src/lv_core/../lv_font/lv_font.h"
const uint8_t * lv_font_get_glyph_bitmap(const lv_font_t * font_p, uint32_t letter);
# 99 "./src/lv_core/../lv_font/lv_font.h"
bool lv_font_get_glyph_dsc(const lv_font_t * font_p, lv_font_glyph_dsc_t * dsc_out, uint32_t letter,
                           uint32_t letter_next);
# 109 "./src/lv_core/../lv_font/lv_font.h"
uint16_t lv_font_get_glyph_width(const lv_font_t * font, uint32_t letter, uint32_t letter_next);






static inline lv_coord_t lv_font_get_line_height(const lv_font_t * font_p)
{
    return font_p->line_height;
}
# 140 "./src/lv_core/../lv_font/lv_font.h"
extern lv_font_t lv_font_montserrat_14;
# 18 "./src/lv_core/lv_style.h" 2


# 1 "./src/lv_core/../lv_misc/lv_anim.h" 1
# 18 "./src/lv_core/../lv_misc/lv_anim.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 19 "./src/lv_core/../lv_misc/lv_anim.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 20 "./src/lv_core/../lv_misc/lv_anim.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\string.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\string.h" 2
# 21 "./src/lv_core/../lv_misc/lv_anim.h" 2
# 32 "./src/lv_core/../lv_misc/lv_anim.h"
enum {
    LV_ANIM_OFF,
    LV_ANIM_ON,
};

typedef uint8_t lv_anim_enable_t;


typedef lv_coord_t lv_anim_value_t;





struct _lv_anim_t;
struct _lv_anim_path_t;

typedef lv_anim_value_t (*lv_anim_path_cb_t)(const struct _lv_anim_path_t *, const struct _lv_anim_t *);

typedef struct _lv_anim_path_t {
    lv_anim_path_cb_t cb;
    void * user_data;
} lv_anim_path_t;







typedef void (*lv_anim_exec_xcb_t)(void *, lv_anim_value_t);



typedef void (*lv_anim_custom_exec_cb_t)(struct _lv_anim_t *, lv_anim_value_t);


typedef void (*lv_anim_ready_cb_t)(struct _lv_anim_t *);


typedef void (*lv_anim_start_cb_t)(struct _lv_anim_t *);


typedef struct _lv_anim_t {
    void * var;
    lv_anim_exec_xcb_t exec_cb;
    lv_anim_start_cb_t start_cb;
    lv_anim_ready_cb_t ready_cb;



    lv_anim_path_t path;
    int32_t start;
    int32_t current;
    int32_t end;
    int32_t time;
    int32_t act_time;
    uint32_t playback_delay;
    uint32_t playback_time;
    uint32_t repeat_delay;
    uint16_t repeat_cnt;
    uint8_t early_apply : 1;


    uint8_t playback_now : 1;
    uint8_t run_round : 1;
    uint8_t start_cb_called : 1;
    uint32_t time_orig;
} lv_anim_t;
# 109 "./src/lv_core/../lv_misc/lv_anim.h"
void _lv_anim_core_init(void);
# 119 "./src/lv_core/../lv_misc/lv_anim.h"
void lv_anim_init(lv_anim_t * a);






static inline void lv_anim_set_var(lv_anim_t * a, void * var)
{
    a->var = var;
}
# 138 "./src/lv_core/../lv_misc/lv_anim.h"
static inline void lv_anim_set_exec_cb(lv_anim_t * a, lv_anim_exec_xcb_t exec_cb)
{
    a->exec_cb = exec_cb;
}






static inline void lv_anim_set_time(lv_anim_t * a, uint32_t duration)
{
    a->time = duration;
}






static inline void lv_anim_set_delay(lv_anim_t * a, uint32_t delay)
{
    a->act_time = -(int32_t)(delay);
}







static inline void lv_anim_set_values(lv_anim_t * a, lv_anim_value_t start, lv_anim_value_t end)
{
    a->start = start;
    a->current = start;
    a->end = end;
}
# 185 "./src/lv_core/../lv_misc/lv_anim.h"
static inline void lv_anim_set_custom_exec_cb(lv_anim_t * a, lv_anim_custom_exec_cb_t exec_cb)
{
    a->var = a;
    a->exec_cb = (lv_anim_exec_xcb_t)exec_cb;
}







static inline void lv_anim_set_path(lv_anim_t * a, const lv_anim_path_t * path)
{
    _lv_memcpy_small(&a->path, path, sizeof(lv_anim_path_t));
}






static inline void lv_anim_set_start_cb(lv_anim_t * a, lv_anim_ready_cb_t start_cb)
{
    a->start_cb = start_cb;
}






static inline void lv_anim_set_ready_cb(lv_anim_t * a, lv_anim_ready_cb_t ready_cb)
{
    a->ready_cb = ready_cb;
}






static inline void lv_anim_set_playback_time(lv_anim_t * a, uint32_t time)
{
    a->playback_time = time;
}






static inline void lv_anim_set_playback_delay(lv_anim_t * a, uint32_t delay)
{
    a->playback_delay = delay;
}






static inline void lv_anim_set_repeat_count(lv_anim_t * a, uint16_t cnt)
{
    a->repeat_cnt = cnt;
}






static inline void lv_anim_set_repeat_delay(lv_anim_t * a, uint32_t delay)
{
    a->repeat_delay = delay;
}





void lv_anim_start(lv_anim_t * a);





static inline void lv_anim_path_init(lv_anim_path_t * path)
{
    _lv_memset_00(path, sizeof(lv_anim_path_t));
}






static inline void lv_anim_path_set_cb(lv_anim_path_t * path, lv_anim_path_cb_t cb)
{
    path->cb = cb;
}






static inline void lv_anim_path_set_user_data(lv_anim_path_t * path, void * user_data)
{
    path->user_data = user_data;
}






static inline uint32_t lv_anim_get_delay(lv_anim_t * a)
{
    return -a->act_time;
}
# 314 "./src/lv_core/../lv_misc/lv_anim.h"
bool lv_anim_del(void * var, lv_anim_exec_xcb_t exec_cb);




void lv_anim_del_all(void);
# 328 "./src/lv_core/../lv_misc/lv_anim.h"
lv_anim_t * lv_anim_get(void * var, lv_anim_exec_xcb_t exec_cb);
# 341 "./src/lv_core/../lv_misc/lv_anim.h"
static inline bool lv_anim_custom_del(lv_anim_t * a, lv_anim_custom_exec_cb_t exec_cb)
{
    return lv_anim_del(a->var, (lv_anim_exec_xcb_t)exec_cb);
}





uint16_t lv_anim_count_running(void);
# 359 "./src/lv_core/../lv_misc/lv_anim.h"
uint32_t lv_anim_speed_to_time(uint32_t speed, lv_anim_value_t start, lv_anim_value_t end);







void lv_anim_refr_now(void);






lv_anim_value_t lv_anim_path_linear(const lv_anim_path_t * path, const lv_anim_t * a);






lv_anim_value_t lv_anim_path_ease_in(const lv_anim_path_t * path, const lv_anim_t * a);






lv_anim_value_t lv_anim_path_ease_out(const lv_anim_path_t * path, const lv_anim_t * a);






lv_anim_value_t lv_anim_path_ease_in_out(const lv_anim_path_t * path, const lv_anim_t * a);






lv_anim_value_t lv_anim_path_overshoot(const lv_anim_path_t * path, const lv_anim_t * a);






lv_anim_value_t lv_anim_path_bounce(const lv_anim_path_t * path, const lv_anim_t * a);







lv_anim_value_t lv_anim_path_step(const lv_anim_path_t * path, const lv_anim_t * a);




extern const lv_anim_path_t lv_anim_path_def;
# 21 "./src/lv_core/lv_style.h" 2

# 1 "./src/lv_core/../lv_misc/lv_debug.h" 1
# 19 "./src/lv_core/../lv_misc/lv_debug.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 20 "./src/lv_core/../lv_misc/lv_debug.h" 2
# 32 "./src/lv_core/../lv_misc/lv_debug.h"
bool lv_debug_check_null(const void * p);

bool lv_debug_check_mem_integrity(void);

bool lv_debug_check_str(const void * str);

void lv_debug_log_error(const char * msg, uint64_t value);
# 23 "./src/lv_core/lv_style.h" 2
# 1 "./src/lv_core/../lv_draw/lv_draw_blend.h" 1
# 18 "./src/lv_core/../lv_draw/lv_draw_blend.h"
# 1 "./src/lv_core/../lv_draw/lv_draw_mask.h" 1
# 16 "./src/lv_core/../lv_draw/lv_draw_mask.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 17 "./src/lv_core/../lv_draw/lv_draw_mask.h" 2
# 30 "./src/lv_core/../lv_draw/lv_draw_mask.h"
enum {
    LV_DRAW_MASK_RES_TRANSP,
    LV_DRAW_MASK_RES_FULL_COVER,
    LV_DRAW_MASK_RES_CHANGED,
    LV_DRAW_MASK_RES_UNKNOWN
};

typedef uint8_t lv_draw_mask_res_t;

enum {
    LV_DRAW_MASK_TYPE_LINE,
    LV_DRAW_MASK_TYPE_ANGLE,
    LV_DRAW_MASK_TYPE_RADIUS,
    LV_DRAW_MASK_TYPE_FADE,
    LV_DRAW_MASK_TYPE_MAP,
};

typedef uint8_t lv_draw_mask_type_t;

enum {
    LV_DRAW_MASK_LINE_SIDE_LEFT = 0,
    LV_DRAW_MASK_LINE_SIDE_RIGHT,
    LV_DRAW_MASK_LINE_SIDE_TOP,
    LV_DRAW_MASK_LINE_SIDE_BOTTOM,
};





typedef lv_draw_mask_res_t (*lv_draw_mask_xcb_t)(lv_opa_t * mask_buf, lv_coord_t abs_x, lv_coord_t abs_y,
                                                 lv_coord_t len,
                                                 void * p);

typedef uint8_t lv_draw_mask_line_side_t;

typedef struct {
    lv_draw_mask_xcb_t cb;
    lv_draw_mask_type_t type;
} lv_draw_mask_common_dsc_t;

typedef struct {

    lv_draw_mask_common_dsc_t dsc;

    struct {

        lv_point_t p1;


        lv_point_t p2;


        lv_draw_mask_line_side_t side : 2;
    } cfg;


    lv_point_t origo;


    int32_t xy_steep;


    int32_t yx_steep;


    int32_t steep;


    int32_t spx;


    uint8_t flat : 1;



    uint8_t inv: 1;
} lv_draw_mask_line_param_t;

typedef struct {

    lv_draw_mask_common_dsc_t dsc;

    struct {
        lv_point_t vertex_p;
        lv_coord_t start_angle;
        lv_coord_t end_angle;
    } cfg;

    lv_draw_mask_line_param_t start_line;
    lv_draw_mask_line_param_t end_line;
    uint16_t delta_deg;
} lv_draw_mask_angle_param_t;

typedef struct {

    lv_draw_mask_common_dsc_t dsc;

    struct {
        lv_area_t rect;
        lv_coord_t radius;

        uint8_t outer: 1;
    } cfg;
    int32_t y_prev;
    lv_sqrt_res_t y_prev_x;

} lv_draw_mask_radius_param_t;

typedef struct {

    lv_draw_mask_common_dsc_t dsc;

    struct {
        lv_area_t coords;
        lv_coord_t y_top;
        lv_coord_t y_bottom;
        lv_opa_t opa_top;
        lv_opa_t opa_bottom;
    } cfg;

} lv_draw_mask_fade_param_t;

typedef struct _lv_draw_mask_map_param_t {

    lv_draw_mask_common_dsc_t dsc;

    struct {
        lv_area_t coords;
        const lv_opa_t * map;
    } cfg;
} lv_draw_mask_map_param_t;

typedef struct {
    void * param;
    void * custom_id;
} _lv_draw_mask_saved_t;

typedef _lv_draw_mask_saved_t _lv_draw_mask_saved_arr_t[16];
# 180 "./src/lv_core/../lv_draw/lv_draw_mask.h"
int16_t lv_draw_mask_add(void * param, void * custom_id);
# 195 "./src/lv_core/../lv_draw/lv_draw_mask.h"
                      lv_draw_mask_res_t lv_draw_mask_apply(lv_opa_t * mask_buf, lv_coord_t abs_x, lv_coord_t abs_y,
                                                            lv_coord_t len);
# 206 "./src/lv_core/../lv_draw/lv_draw_mask.h"
void * lv_draw_mask_remove_id(int16_t id);







void * lv_draw_mask_remove_custom(void * custom_id);







                      uint8_t lv_draw_mask_get_cnt(void);
# 237 "./src/lv_core/../lv_draw/lv_draw_mask.h"
void lv_draw_mask_line_points_init(lv_draw_mask_line_param_t * param, lv_coord_t p1x, lv_coord_t p1y, lv_coord_t p2x,
                                   lv_coord_t p2y, lv_draw_mask_line_side_t side);
# 250 "./src/lv_core/../lv_draw/lv_draw_mask.h"
void lv_draw_mask_line_angle_init(lv_draw_mask_line_param_t * param, lv_coord_t p1x, lv_coord_t py, int16_t angle,
                                  lv_draw_mask_line_side_t side);
# 261 "./src/lv_core/../lv_draw/lv_draw_mask.h"
void lv_draw_mask_angle_init(lv_draw_mask_angle_param_t * param, lv_coord_t vertex_x, lv_coord_t vertex_y,
                             lv_coord_t start_angle, lv_coord_t end_angle);
# 271 "./src/lv_core/../lv_draw/lv_draw_mask.h"
void lv_draw_mask_radius_init(lv_draw_mask_radius_param_t * param, const lv_area_t * rect, lv_coord_t radius, bool inv);
# 282 "./src/lv_core/../lv_draw/lv_draw_mask.h"
void lv_draw_mask_fade_init(lv_draw_mask_fade_param_t * param, const lv_area_t * coords, lv_opa_t opa_top,
                            lv_coord_t y_top,
                            lv_opa_t opa_bottom, lv_coord_t y_bottom);







void lv_draw_mask_map_init(lv_draw_mask_map_param_t * param, const lv_area_t * coords, const lv_opa_t * map);
# 19 "./src/lv_core/../lv_draw/lv_draw_blend.h" 2








enum {
    LV_BLEND_MODE_NORMAL,

    LV_BLEND_MODE_ADDITIVE,
    LV_BLEND_MODE_SUBTRACTIVE,

};

typedef uint8_t lv_blend_mode_t;






                      void _lv_blend_fill(const lv_area_t * clip_area, const lv_area_t * fill_area, lv_color_t color,
                                          lv_opa_t * mask, lv_draw_mask_res_t mask_res, lv_opa_t opa, lv_blend_mode_t mode);

                      void _lv_blend_map(const lv_area_t * clip_area, const lv_area_t * map_area,
                                         const lv_color_t * map_buf,
                                         lv_opa_t * mask, lv_draw_mask_res_t mask_res, lv_opa_t opa, lv_blend_mode_t mode);
# 24 "./src/lv_core/lv_style.h" 2






struct _silence_gcc_warning;
# 53 "./src/lv_core/lv_style.h"
enum {
    LV_BORDER_SIDE_NONE = 0x00,
    LV_BORDER_SIDE_BOTTOM = 0x01,
    LV_BORDER_SIDE_TOP = 0x02,
    LV_BORDER_SIDE_LEFT = 0x04,
    LV_BORDER_SIDE_RIGHT = 0x08,
    LV_BORDER_SIDE_FULL = 0x0F,
    LV_BORDER_SIDE_INTERNAL = 0x10,
    _LV_BORDER_SIDE_LAST
};
typedef uint8_t lv_border_side_t;

enum {
    LV_GRAD_DIR_NONE,
    LV_GRAD_DIR_VER,
    LV_GRAD_DIR_HOR,
    _LV_GRAD_DIR_LAST
};

typedef uint8_t lv_grad_dir_t;


enum {
    LV_TEXT_DECOR_NONE = 0x00,
    LV_TEXT_DECOR_UNDERLINE = 0x01,
    LV_TEXT_DECOR_STRIKETHROUGH = 0x02,
    _LV_TEXT_DECOR_LAST
};

typedef uint8_t lv_text_decor_t;

typedef uint8_t lv_style_attr_t;
# 94 "./src/lv_core/lv_style.h"
enum {

    LV_STYLE_RADIUS = (((0x0 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_CLIP_CORNER = (((0x0 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_SIZE = (((0x0 << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_TRANSFORM_WIDTH = (((0x0 << 4) + 0x0 + 4) | ((0) << 8)),
    LV_STYLE_TRANSFORM_HEIGHT = (((0x0 << 4) + 0x0 + 5) | ((0) << 8)),
    LV_STYLE_TRANSFORM_ANGLE = (((0x0 << 4) + 0x0 + 6) | ((0) << 8)),
    LV_STYLE_TRANSFORM_ZOOM = (((0x0 << 4) + 0x0 + 7) | ((0) << 8)),
    LV_STYLE_OPA_SCALE = (((0x0 << 4) + 0xC + 0) | (((1 << 7)) << 8)),

    LV_STYLE_PAD_TOP = (((0x1 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_PAD_BOTTOM = (((0x1 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_PAD_LEFT = (((0x1 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_PAD_RIGHT = (((0x1 << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_PAD_INNER = (((0x1 << 4) + 0x0 + 4) | ((0) << 8)),
    LV_STYLE_MARGIN_TOP = (((0x1 << 4) + 0x0 + 5) | ((0) << 8)),
    LV_STYLE_MARGIN_BOTTOM = (((0x1 << 4) + 0x0 + 6) | ((0) << 8)),
    LV_STYLE_MARGIN_LEFT = (((0x1 << 4) + 0x0 + 7) | ((0) << 8)),
    LV_STYLE_MARGIN_RIGHT = (((0x1 << 4) + 0x0 + 8) | ((0) << 8)),

    LV_STYLE_BG_BLEND_MODE = (((0x2 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_BG_MAIN_STOP = (((0x2 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_BG_GRAD_STOP = (((0x2 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_BG_GRAD_DIR = (((0x2 << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_BG_COLOR = (((0x2 << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_BG_GRAD_COLOR = (((0x2 << 4) + 0x9 + 1) | ((0) << 8)),
    LV_STYLE_BG_OPA = (((0x2 << 4) + 0xC + 0) | ((0) << 8)),

    LV_STYLE_BORDER_WIDTH = (((0x3 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_BORDER_SIDE = (((0x3 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_BORDER_BLEND_MODE = (((0x3 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_BORDER_POST = (((0x3 << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_BORDER_COLOR = (((0x3 << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_BORDER_OPA = (((0x3 << 4) + 0xC + 0) | ((0) << 8)),

    LV_STYLE_OUTLINE_WIDTH = (((0x4 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_OUTLINE_PAD = (((0x4 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_OUTLINE_BLEND_MODE = (((0x4 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_OUTLINE_COLOR = (((0x4 << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_OUTLINE_OPA = (((0x4 << 4) + 0xC + 0) | ((0) << 8)),

    LV_STYLE_SHADOW_WIDTH = (((0x5 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_SHADOW_OFS_X = (((0x5 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_SHADOW_OFS_Y = (((0x5 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_SHADOW_SPREAD = (((0x5 << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_SHADOW_BLEND_MODE = (((0x5 << 4) + 0x0 + 4) | ((0) << 8)),
    LV_STYLE_SHADOW_COLOR = (((0x5 << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_SHADOW_OPA = (((0x5 << 4) + 0xC + 0) | ((0) << 8)),

    LV_STYLE_PATTERN_BLEND_MODE = (((0x6 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_PATTERN_REPEAT = (((0x6 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_PATTERN_RECOLOR = (((0x6 << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_PATTERN_OPA = (((0x6 << 4) + 0xC + 0) | ((0) << 8)),
    LV_STYLE_PATTERN_RECOLOR_OPA = (((0x6 << 4) + 0xC + 1) | ((0) << 8)),
    LV_STYLE_PATTERN_IMAGE = (((0x6 << 4) + 0xE + 0) | ((0) << 8)),

    LV_STYLE_VALUE_LETTER_SPACE = (((0x7 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_VALUE_LINE_SPACE = (((0x7 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_VALUE_BLEND_MODE = (((0x7 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_VALUE_OFS_X = (((0x7 << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_VALUE_OFS_Y = (((0x7 << 4) + 0x0 + 4) | ((0) << 8)),
    LV_STYLE_VALUE_ALIGN = (((0x7 << 4) + 0x0 + 5) | ((0) << 8)),
    LV_STYLE_VALUE_COLOR = (((0x7 << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_VALUE_OPA = (((0x7 << 4) + 0xC + 0) | ((0) << 8)),
    LV_STYLE_VALUE_FONT = (((0x7 << 4) + 0xE + 0) | ((0) << 8)),
    LV_STYLE_VALUE_STR = (((0x7 << 4) + 0xE + 1) | ((0) << 8)),

    LV_STYLE_TEXT_LETTER_SPACE = (((0x8 << 4) + 0x0 + 0) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_LINE_SPACE = (((0x8 << 4) + 0x0 + 1) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_DECOR = (((0x8 << 4) + 0x0 + 2) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_BLEND_MODE = (((0x8 << 4) + 0x0 + 3) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_COLOR = (((0x8 << 4) + 0x9 + 0) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_SEL_COLOR = (((0x8 << 4) + 0x9 + 1) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_SEL_BG_COLOR = (((0x8 << 4) + 0x9 + 2) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_OPA = (((0x8 << 4) + 0xC + 0) | (((1 << 7)) << 8)),
    LV_STYLE_TEXT_FONT = (((0x8 << 4) + 0xE + 0) | (((1 << 7)) << 8)),

    LV_STYLE_LINE_WIDTH = (((0x9 << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_LINE_BLEND_MODE = (((0x9 << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_LINE_DASH_WIDTH = (((0x9 << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_LINE_DASH_GAP = (((0x9 << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_LINE_ROUNDED = (((0x9 << 4) + 0x0 + 4) | ((0) << 8)),
    LV_STYLE_LINE_COLOR = (((0x9 << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_LINE_OPA = (((0x9 << 4) + 0xC + 0) | ((0) << 8)),

    LV_STYLE_IMAGE_BLEND_MODE = (((0xA << 4) + 0x0 + 0) | (((1 << 7)) << 8)),
    LV_STYLE_IMAGE_RECOLOR = (((0xA << 4) + 0x9 + 0) | (((1 << 7)) << 8)),
    LV_STYLE_IMAGE_OPA = (((0xA << 4) + 0xC + 0) | (((1 << 7)) << 8)),
    LV_STYLE_IMAGE_RECOLOR_OPA = (((0xA << 4) + 0xC + 1) | (((1 << 7)) << 8)),

    LV_STYLE_TRANSITION_TIME = (((0xB << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_TRANSITION_DELAY = (((0xB << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_TRANSITION_PROP_1 = (((0xB << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_TRANSITION_PROP_2 = (((0xB << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_TRANSITION_PROP_3 = (((0xB << 4) + 0x0 + 4) | ((0) << 8)),
    LV_STYLE_TRANSITION_PROP_4 = (((0xB << 4) + 0x0 + 5) | ((0) << 8)),
    LV_STYLE_TRANSITION_PROP_5 = (((0xB << 4) + 0x0 + 6) | ((0) << 8)),
    LV_STYLE_TRANSITION_PROP_6 = (((0xB << 4) + 0x0 + 7) | ((0) << 8)),
    LV_STYLE_TRANSITION_PATH = (((0xB << 4) + 0xE + 0) | ((0) << 8)),

    LV_STYLE_SCALE_WIDTH = (((0xC << 4) + 0x0 + 0) | ((0) << 8)),
    LV_STYLE_SCALE_BORDER_WIDTH = (((0xC << 4) + 0x0 + 1) | ((0) << 8)),
    LV_STYLE_SCALE_END_BORDER_WIDTH = (((0xC << 4) + 0x0 + 2) | ((0) << 8)),
    LV_STYLE_SCALE_END_LINE_WIDTH = (((0xC << 4) + 0x0 + 3) | ((0) << 8)),
    LV_STYLE_SCALE_GRAD_COLOR = (((0xC << 4) + 0x9 + 0) | ((0) << 8)),
    LV_STYLE_SCALE_END_COLOR = (((0xC << 4) + 0x9 + 1) | ((0) << 8)),
};

typedef uint16_t lv_style_property_t;





typedef uint16_t lv_style_state_t;

typedef struct {
    uint8_t * map;



} lv_style_t;

typedef int16_t lv_style_int_t;

typedef struct {
    lv_style_t ** style_list;



    uint32_t style_cnt : 6;
    uint32_t has_local : 1;
    uint32_t has_trans : 1;
    uint32_t skip_trans : 1;
    uint32_t ignore_trans : 1;
    uint32_t valid_cache : 1;
    uint32_t ignore_cache : 1;

    uint32_t radius_zero : 1;
    uint32_t opa_scale_cover : 1;
    uint32_t clip_corner_off : 1;
    uint32_t transform_all_zero : 1;
    uint32_t pad_all_zero : 1;
    uint32_t margin_all_zero : 1;
    uint32_t blend_mode_all_normal : 1;
    uint32_t bg_opa_transp : 1;
    uint32_t bg_opa_cover : 1;

    uint32_t border_width_zero : 1;
    uint32_t border_side_full : 1;
    uint32_t border_post_off : 1;

    uint32_t outline_width_zero : 1;
    uint32_t pattern_img_null : 1;
    uint32_t shadow_width_zero : 1;
    uint32_t value_txt_str : 1;
    uint32_t img_recolor_opa_transp : 1;

    uint32_t text_space_zero : 1;
    uint32_t text_decor_none : 1;
    uint32_t text_font_normal : 1;
} lv_style_list_t;
# 266 "./src/lv_core/lv_style.h"
void lv_style_init(lv_style_t * style);






void lv_style_copy(lv_style_t * style_dest, const lv_style_t * style_src);





void lv_style_list_init(lv_style_list_t * list);






void lv_style_list_copy(lv_style_list_t * list_dest, const lv_style_list_t * list_src);
# 295 "./src/lv_core/lv_style.h"
void _lv_style_list_add_style(lv_style_list_t * list, lv_style_t * style);






void _lv_style_list_remove_style(lv_style_list_t * list, lv_style_t * style);






void _lv_style_list_reset(lv_style_list_t * style_list);

static inline lv_style_t * lv_style_list_get_style(lv_style_list_t * list, uint8_t id)
{
    if(list->has_trans && list->skip_trans) id++;
    if(list->style_cnt == 0 || id >= list->style_cnt) return 0;
    return list->style_list[id];
}





void lv_style_reset(lv_style_t * style);






uint16_t _lv_style_get_mem_size(const lv_style_t * style);
# 338 "./src/lv_core/lv_style.h"
bool lv_style_remove_prop(lv_style_t * style, lv_style_property_t prop);
# 350 "./src/lv_core/lv_style.h"
void _lv_style_set_int(lv_style_t * style, lv_style_property_t prop, lv_style_int_t value);
# 362 "./src/lv_core/lv_style.h"
void _lv_style_set_color(lv_style_t * style, lv_style_property_t prop, lv_color_t color);
# 374 "./src/lv_core/lv_style.h"
void _lv_style_set_opa(lv_style_t * style, lv_style_property_t prop, lv_opa_t opa);
# 386 "./src/lv_core/lv_style.h"
void _lv_style_set_ptr(lv_style_t * style, lv_style_property_t prop, const void * p);
# 401 "./src/lv_core/lv_style.h"
int16_t _lv_style_get_int(const lv_style_t * style, lv_style_property_t prop, lv_style_int_t * res);
# 416 "./src/lv_core/lv_style.h"
int16_t _lv_style_get_color(const lv_style_t * style, lv_style_property_t prop, lv_color_t * res);
# 431 "./src/lv_core/lv_style.h"
int16_t _lv_style_get_opa(const lv_style_t * style, lv_style_property_t prop, lv_opa_t * res);
# 446 "./src/lv_core/lv_style.h"
int16_t _lv_style_get_ptr(const lv_style_t * style, lv_style_property_t prop, const void ** res);






lv_style_t * lv_style_list_get_local_style(lv_style_list_t * list);






lv_style_t * _lv_style_list_get_transition_style(lv_style_list_t * list);






lv_style_t * _lv_style_list_add_trans_style(lv_style_list_t * list);
# 477 "./src/lv_core/lv_style.h"
void _lv_style_list_set_local_int(lv_style_list_t * list, lv_style_property_t prop, lv_style_int_t value);
# 487 "./src/lv_core/lv_style.h"
void _lv_style_list_set_local_color(lv_style_list_t * list, lv_style_property_t prop, lv_color_t value);
# 497 "./src/lv_core/lv_style.h"
void _lv_style_list_set_local_opa(lv_style_list_t * list, lv_style_property_t prop, lv_opa_t value);
# 507 "./src/lv_core/lv_style.h"
void _lv_style_list_set_local_ptr(lv_style_list_t * list, lv_style_property_t prop, const void * value);
# 520 "./src/lv_core/lv_style.h"
lv_res_t _lv_style_list_get_int(lv_style_list_t * list, lv_style_property_t prop, lv_style_int_t * res);
# 533 "./src/lv_core/lv_style.h"
lv_res_t _lv_style_list_get_color(lv_style_list_t * list, lv_style_property_t prop, lv_color_t * res);
# 546 "./src/lv_core/lv_style.h"
lv_res_t _lv_style_list_get_opa(lv_style_list_t * list, lv_style_property_t prop, lv_opa_t * res);
# 559 "./src/lv_core/lv_style.h"
lv_res_t _lv_style_list_get_ptr(lv_style_list_t * list, lv_style_property_t prop, const void ** res);






bool lv_debug_check_style(const lv_style_t * style);






bool lv_debug_check_style_list(const lv_style_list_t * list);
# 21 "./src/lv_core/lv_obj.h" 2





# 1 "./src/lv_core/../lv_draw/lv_draw_rect.h" 1
# 26 "./src/lv_core/../lv_draw/lv_draw_rect.h"
typedef struct {
    lv_style_int_t radius;


    lv_color_t bg_color;
    lv_color_t bg_grad_color;
    lv_grad_dir_t bg_grad_dir;
    lv_style_int_t bg_main_color_stop;
    lv_style_int_t bg_grad_color_stop;
    lv_opa_t bg_opa;
    lv_blend_mode_t bg_blend_mode;


    lv_color_t border_color;
    lv_style_int_t border_width;
    lv_style_int_t border_side;
    lv_opa_t border_opa;
    lv_blend_mode_t border_blend_mode;
    uint8_t border_post : 1;


    lv_color_t outline_color;
    lv_style_int_t outline_width;
    lv_style_int_t outline_pad;
    lv_opa_t outline_opa;
    lv_blend_mode_t outline_blend_mode;


    lv_color_t shadow_color;
    lv_style_int_t shadow_width;
    lv_style_int_t shadow_ofs_x;
    lv_style_int_t shadow_ofs_y;
    lv_style_int_t shadow_spread;
    lv_opa_t shadow_opa;
    lv_blend_mode_t shadow_blend_mode;


    const void * pattern_image;
    const lv_font_t * pattern_font;
    lv_color_t pattern_recolor;
    lv_opa_t pattern_opa;
    lv_opa_t pattern_recolor_opa;
    uint8_t pattern_repeat : 1;
    lv_blend_mode_t pattern_blend_mode;


    const char * value_str;
    const lv_font_t * value_font;
    lv_opa_t value_opa;
    lv_color_t value_color;
    lv_style_int_t value_ofs_x;
    lv_style_int_t value_ofs_y;
    lv_style_int_t value_letter_space;
    lv_style_int_t value_line_space;
    lv_align_t value_align;
    lv_blend_mode_t value_blend_mode;
} lv_draw_rect_dsc_t;





                      void lv_draw_rect_dsc_init(lv_draw_rect_dsc_t * dsc);
# 98 "./src/lv_core/../lv_draw/lv_draw_rect.h"
void lv_draw_rect(const lv_area_t * coords, const lv_area_t * mask, const lv_draw_rect_dsc_t * dsc);







void lv_draw_px(const lv_point_t * point, const lv_area_t * clip_area, const lv_style_t * style);
# 27 "./src/lv_core/lv_obj.h" 2
# 1 "./src/lv_core/../lv_draw/lv_draw_label.h" 1
# 16 "./src/lv_core/../lv_draw/lv_draw_label.h"
# 1 "./src/lv_core/../lv_draw/../lv_misc/lv_bidi.h" 1
# 18 "./src/lv_core/../lv_draw/../lv_misc/lv_bidi.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 19 "./src/lv_core/../lv_draw/../lv_misc/lv_bidi.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 20 "./src/lv_core/../lv_draw/../lv_misc/lv_bidi.h" 2
# 32 "./src/lv_core/../lv_draw/../lv_misc/lv_bidi.h"
enum {

    LV_BIDI_DIR_LTR = 0x00,
    LV_BIDI_DIR_RTL = 0x01,
    LV_BIDI_DIR_AUTO = 0x02,
    LV_BIDI_DIR_INHERIT = 0x03,

    LV_BIDI_DIR_NEUTRAL = 0x20,
    LV_BIDI_DIR_WEAK = 0x21,
};

typedef uint8_t lv_bidi_dir_t;
# 17 "./src/lv_core/../lv_draw/lv_draw_label.h" 2
# 1 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h" 1
# 18 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 19 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdarg.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdarg.h" 2
# 20 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h" 2


# 1 "./src/lv_misc/lv_printf.h" 1
# 60 "./src/lv_misc/lv_printf.h"
# 1 "../../lua/include\\printf.h" 1
# 35 "../../lua/include\\printf.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdarg.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdarg.h" 2
# 36 "../../lua/include\\printf.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stddef.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stddef.h" 2
# 37 "../../lua/include\\printf.h" 2
# 49 "../../lua/include\\printf.h"
void _putchar(char character);
# 61 "../../lua/include\\printf.h"
int printf_(const char* format, ...);
# 72 "../../lua/include\\printf.h"
int sprintf_(char* buffer, const char* format, ...);
# 87 "../../lua/include\\printf.h"
int snprintf_(char* buffer, size_t count, const char* format, ...);
int vsnprintf_(char* buffer, size_t count, const char* format, va_list va);
# 98 "../../lua/include\\printf.h"
int vprintf_(const char* format, va_list va);
# 109 "../../lua/include\\printf.h"
int fctprintf(void (*out)(char character, void* arg), void* arg, const char* format, ...);
# 61 "./src/lv_misc/lv_printf.h" 2
# 23 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h" 2
# 40 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
enum {
    LV_TXT_FLAG_NONE = 0x00,
    LV_TXT_FLAG_RECOLOR = 0x01,
    LV_TXT_FLAG_EXPAND = 0x02,
    LV_TXT_FLAG_CENTER = 0x04,
    LV_TXT_FLAG_RIGHT = 0x08,
    LV_TXT_FLAG_FIT = 0x10,
};
typedef uint8_t lv_txt_flag_t;



enum {
    LV_TXT_CMD_STATE_WAIT,
    LV_TXT_CMD_STATE_PAR,
    LV_TXT_CMD_STATE_IN,
};
typedef uint8_t lv_txt_cmd_state_t;
# 74 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
void _lv_txt_get_size(lv_point_t * size_res, const char * text, const lv_font_t * font, lv_coord_t letter_space,
                      lv_coord_t line_space, lv_coord_t max_width, lv_txt_flag_t flag);
# 88 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
uint32_t _lv_txt_get_next_line(const char * txt, const lv_font_t * font, lv_coord_t letter_space, lv_coord_t max_width,
                               lv_txt_flag_t flag);
# 101 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
lv_coord_t _lv_txt_get_width(const char * txt, uint32_t length, const lv_font_t * font, lv_coord_t letter_space,
                             lv_txt_flag_t flag);
# 112 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
bool _lv_txt_is_cmd(lv_txt_cmd_state_t * state, uint32_t c);







void _lv_txt_ins(char * txt_buf, uint32_t pos, const char * ins_txt);
# 129 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
void _lv_txt_cut(char * txt, uint32_t pos, uint32_t len);






char * _lv_txt_set_text_vfmt(const char * fmt, va_list ap);
# 147 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
extern uint8_t (*_lv_txt_encoded_size)(const char *);






extern uint32_t (*_lv_txt_unicode_to_encoded)(uint32_t);






extern uint32_t (*_lv_txt_encoded_conv_wc)(uint32_t c);
# 171 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
extern uint32_t (*_lv_txt_encoded_next)(const char *, uint32_t *);
# 180 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
extern uint32_t (*_lv_txt_encoded_prev)(const char *, uint32_t *);
# 189 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
extern uint32_t (*_lv_txt_encoded_get_byte_id)(const char *, uint32_t);
# 198 "./src/lv_core/../lv_draw/../lv_misc/lv_txt.h"
extern uint32_t (*_lv_txt_encoded_get_char_id)(const char *, uint32_t);







extern uint32_t (*_lv_txt_get_encoded_length)(const char *);
# 18 "./src/lv_core/../lv_draw/lv_draw_label.h" 2
# 29 "./src/lv_core/../lv_draw/lv_draw_label.h"
typedef struct {
    lv_color_t color;
    lv_color_t sel_color;
    lv_color_t sel_bg_color;
    const lv_font_t * font;
    lv_opa_t opa;
    lv_style_int_t line_space;
    lv_style_int_t letter_space;
    uint32_t sel_start;
    uint32_t sel_end;
    lv_coord_t ofs_x;
    lv_coord_t ofs_y;
    lv_bidi_dir_t bidi_dir;
    lv_txt_flag_t flag;
    lv_text_decor_t decor;
    lv_blend_mode_t blend_mode;
} lv_draw_label_dsc_t;






typedef struct {

    int32_t line_start;


    int32_t y;



    int32_t coord_y;
} lv_draw_label_hint_t;







                      void lv_draw_label_dsc_init(lv_draw_label_dsc_t * dsc);
# 81 "./src/lv_core/../lv_draw/lv_draw_label.h"
                      void lv_draw_label(const lv_area_t * coords, const lv_area_t * mask,
                                         const lv_draw_label_dsc_t * dsc,
                                         const char * txt, lv_draw_label_hint_t * hint);





extern const uint8_t _lv_bpp2_opa_table[];
extern const uint8_t _lv_bpp3_opa_table[];
extern const uint8_t _lv_bpp1_opa_table[];
extern const uint8_t _lv_bpp4_opa_table[];
extern const uint8_t _lv_bpp8_opa_table[];
# 28 "./src/lv_core/lv_obj.h" 2
# 1 "./src/lv_core/../lv_draw/lv_draw_line.h" 1
# 25 "./src/lv_core/../lv_draw/lv_draw_line.h"
typedef struct {
    lv_color_t color;
    lv_style_int_t width;
    lv_style_int_t dash_width;
    lv_style_int_t dash_gap;
    lv_opa_t opa;
    lv_blend_mode_t blend_mode : 2;
    uint8_t round_start : 1;
    uint8_t round_end : 1;
    uint8_t raw_end : 1;
} lv_draw_line_dsc_t;
# 49 "./src/lv_core/../lv_draw/lv_draw_line.h"
                      void lv_draw_line(const lv_point_t * point1, const lv_point_t * point2, const lv_area_t * clip,
                                        const lv_draw_line_dsc_t * dsc);

                      void lv_draw_line_dsc_init(lv_draw_line_dsc_t * dsc);
# 29 "./src/lv_core/lv_obj.h" 2
# 1 "./src/lv_core/../lv_draw/lv_draw_img.h" 1
# 16 "./src/lv_core/../lv_draw/lv_draw_img.h"
# 1 "./src/lv_core/../lv_draw/lv_img_decoder.h" 1
# 18 "./src/lv_core/../lv_draw/lv_img_decoder.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 19 "./src/lv_core/../lv_draw/lv_img_decoder.h" 2
# 1 "./src/lv_core/../lv_draw/lv_img_buf.h" 1
# 16 "./src/lv_core/../lv_draw/lv_img_buf.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 17 "./src/lv_core/../lv_draw/lv_img_buf.h" 2
# 58 "./src/lv_core/../lv_draw/lv_img_buf.h"
enum {
    LV_IMG_CF_UNKNOWN = 0,

    LV_IMG_CF_RAW,
    LV_IMG_CF_RAW_ALPHA,

    LV_IMG_CF_RAW_CHROMA_KEYED,


    LV_IMG_CF_TRUE_COLOR,
    LV_IMG_CF_TRUE_COLOR_ALPHA,
    LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED,


    LV_IMG_CF_INDEXED_1BIT,
    LV_IMG_CF_INDEXED_2BIT,
    LV_IMG_CF_INDEXED_4BIT,
    LV_IMG_CF_INDEXED_8BIT,

    LV_IMG_CF_ALPHA_1BIT,
    LV_IMG_CF_ALPHA_2BIT,
    LV_IMG_CF_ALPHA_4BIT,
    LV_IMG_CF_ALPHA_8BIT,

    LV_IMG_CF_RESERVED_15,
    LV_IMG_CF_RESERVED_16,
    LV_IMG_CF_RESERVED_17,
    LV_IMG_CF_RESERVED_18,
    LV_IMG_CF_RESERVED_19,
    LV_IMG_CF_RESERVED_20,
    LV_IMG_CF_RESERVED_21,
    LV_IMG_CF_RESERVED_22,
    LV_IMG_CF_RESERVED_23,

    LV_IMG_CF_USER_ENCODED_0,
    LV_IMG_CF_USER_ENCODED_1,
    LV_IMG_CF_USER_ENCODED_2,
    LV_IMG_CF_USER_ENCODED_3,
    LV_IMG_CF_USER_ENCODED_4,
    LV_IMG_CF_USER_ENCODED_5,
    LV_IMG_CF_USER_ENCODED_6,
    LV_IMG_CF_USER_ENCODED_7,
};
typedef uint8_t lv_img_cf_t;
# 123 "./src/lv_core/../lv_draw/lv_img_buf.h"
typedef struct {

    uint32_t cf : 5;
    uint32_t always_zero : 3;


    uint32_t reserved : 2;

    uint32_t w : 11;
    uint32_t h : 11;
} lv_img_header_t;




typedef struct {
    lv_img_header_t header;
    uint32_t data_size;
    const uint8_t * data;
} lv_img_dsc_t;

typedef struct {
    struct {
        const void * src;
        lv_coord_t src_w;
        lv_coord_t src_h;
        lv_coord_t pivot_x;
        lv_coord_t pivot_y;
        int16_t angle;
        uint16_t zoom;
        lv_color_t color;
        lv_img_cf_t cf;
        bool antialias;
    } cfg;

    struct {
        lv_color_t color;
        lv_opa_t opa;
    } res;

    struct {
        lv_img_dsc_t img_dsc;
        int32_t pivot_x_256;
        int32_t pivot_y_256;
        int32_t sinma;
        int32_t cosma;

        uint8_t chroma_keyed : 1;
        uint8_t has_alpha : 1;
        uint8_t native_color : 1;

        uint32_t zoom_inv;


        lv_coord_t xs;
        lv_coord_t ys;
        lv_coord_t xs_int;
        lv_coord_t ys_int;
        uint32_t pxi;
        uint8_t px_size;
    } tmp;
} lv_img_transform_dsc_t;
# 197 "./src/lv_core/../lv_draw/lv_img_buf.h"
lv_img_dsc_t * lv_img_buf_alloc(lv_coord_t w, lv_coord_t h, lv_img_cf_t cf);
# 209 "./src/lv_core/../lv_draw/lv_img_buf.h"
lv_color_t lv_img_buf_get_px_color(lv_img_dsc_t * dsc, lv_coord_t x, lv_coord_t y, lv_color_t color);
# 219 "./src/lv_core/../lv_draw/lv_img_buf.h"
lv_opa_t lv_img_buf_get_px_alpha(lv_img_dsc_t * dsc, lv_coord_t x, lv_coord_t y);
# 229 "./src/lv_core/../lv_draw/lv_img_buf.h"
void lv_img_buf_set_px_color(lv_img_dsc_t * dsc, lv_coord_t x, lv_coord_t y, lv_color_t c);
# 239 "./src/lv_core/../lv_draw/lv_img_buf.h"
void lv_img_buf_set_px_alpha(lv_img_dsc_t * dsc, lv_coord_t x, lv_coord_t y, lv_opa_t opa);
# 251 "./src/lv_core/../lv_draw/lv_img_buf.h"
void lv_img_buf_set_palette(lv_img_dsc_t * dsc, uint8_t id, lv_color_t c);





void lv_img_buf_free(lv_img_dsc_t * dsc);
# 266 "./src/lv_core/../lv_draw/lv_img_buf.h"
uint32_t lv_img_buf_get_img_size(lv_coord_t w, lv_coord_t h, lv_img_cf_t cf);






void _lv_img_buf_transform_init(lv_img_transform_dsc_t * dsc);





bool _lv_img_buf_transform_anti_alias(lv_img_transform_dsc_t * dsc);
# 289 "./src/lv_core/../lv_draw/lv_img_buf.h"
static inline bool _lv_img_buf_transform(lv_img_transform_dsc_t * dsc, lv_coord_t x, lv_coord_t y)
{
    const uint8_t * src_u8 = (const uint8_t *)dsc->cfg.src;


    int32_t xt = x - dsc->cfg.pivot_x;
    int32_t yt = y - dsc->cfg.pivot_y;

    int32_t xs;
    int32_t ys;
    if(dsc->cfg.zoom == 256) {

        xs = ((dsc->tmp.cosma * xt - dsc->tmp.sinma * yt) >> (10 - 8)) + dsc->tmp.pivot_x_256;
        ys = ((dsc->tmp.sinma * xt + dsc->tmp.cosma * yt) >> (10 - 8)) + dsc->tmp.pivot_y_256;
    }
    else if(dsc->cfg.angle == 0) {
        xt = (int32_t)((int32_t)xt * dsc->tmp.zoom_inv) >> 5;
        yt = (int32_t)((int32_t)yt * dsc->tmp.zoom_inv) >> 5;
        xs = xt + dsc->tmp.pivot_x_256;
        ys = yt + dsc->tmp.pivot_y_256;
    }
    else {
        xt = (int32_t)((int32_t)xt * dsc->tmp.zoom_inv) >> 5;
        yt = (int32_t)((int32_t)yt * dsc->tmp.zoom_inv) >> 5;
        xs = ((dsc->tmp.cosma * xt - dsc->tmp.sinma * yt) >> (10)) + dsc->tmp.pivot_x_256;
        ys = ((dsc->tmp.sinma * xt + dsc->tmp.cosma * yt) >> (10)) + dsc->tmp.pivot_y_256;
    }


    int32_t xs_int = xs >> 8;
    int32_t ys_int = ys >> 8;

    if(xs_int >= dsc->cfg.src_w) return 0;
    else if(xs_int < 0) return 0;

    if(ys_int >= dsc->cfg.src_h) return 0;
    else if(ys_int < 0) return 0;

    uint8_t px_size;
    uint32_t pxi;
    if(dsc->tmp.native_color) {
        if(dsc->tmp.has_alpha == 0) {
            px_size = 16 >> 3;

            pxi = dsc->cfg.src_w * ys_int * px_size + xs_int * px_size;
            _lv_memcpy_small(&dsc->res.color, &src_u8[pxi], px_size);
        }
        else {
            px_size = 3;
            pxi = dsc->cfg.src_w * ys_int * px_size + xs_int * px_size;
            _lv_memcpy_small(&dsc->res.color, &src_u8[pxi], px_size - 1);
            dsc->res.opa = src_u8[pxi + px_size - 1];
        }
    }
    else {
        pxi = 0;
        px_size = 0;
        dsc->res.color = lv_img_buf_get_px_color(&dsc->tmp.img_dsc, xs_int, ys_int, dsc->cfg.color);
        dsc->res.opa = lv_img_buf_get_px_alpha(&dsc->tmp.img_dsc, xs_int, ys_int);
    }

    if(dsc->tmp.chroma_keyed) {
        lv_color_t ct = ((lv_color_t){{(uint8_t)((0x00 >> 3) & 0x1FU), (uint8_t)((0xFF >> 2) & 0x3FU), (uint8_t)((0x00 >> 3) & 0x1FU)}});
        if(dsc->res.color.full == ct.full) return 0;
    }

    if(dsc->cfg.antialias == 0) return 1;

    dsc->tmp.xs = xs;
    dsc->tmp.ys = ys;
    dsc->tmp.xs_int = xs_int;
    dsc->tmp.ys_int = ys_int;
    dsc->tmp.pxi = pxi;
    dsc->tmp.px_size = px_size;

    bool ret;
    ret = _lv_img_buf_transform_anti_alias(dsc);

    return ret;
}
# 379 "./src/lv_core/../lv_draw/lv_img_buf.h"
void _lv_img_buf_get_transformed_area(lv_area_t * res, lv_coord_t w, lv_coord_t h, int16_t angle, uint16_t zoom,
                                      const lv_point_t * pivot);
# 20 "./src/lv_core/../lv_draw/lv_img_decoder.h" 2
# 1 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h" 1
# 20 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 21 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 22 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h" 2
# 37 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
enum {
    LV_FS_RES_OK = 0,
    LV_FS_RES_HW_ERR,
    LV_FS_RES_FS_ERR,
    LV_FS_RES_NOT_EX,
    LV_FS_RES_FULL,
    LV_FS_RES_LOCKED,
    LV_FS_RES_DENIED,
    LV_FS_RES_BUSY,
    LV_FS_RES_TOUT,
    LV_FS_RES_NOT_IMP,
    LV_FS_RES_OUT_OF_MEM,
    LV_FS_RES_INV_PARAM,
    LV_FS_RES_UNKNOWN,
};
typedef uint8_t lv_fs_res_t;




enum {
    LV_FS_MODE_WR = 0x01,
    LV_FS_MODE_RD = 0x02,
};
typedef uint8_t lv_fs_mode_t;

typedef struct _lv_fs_drv_t {
    char letter;
    uint16_t file_size;
    uint16_t rddir_size;
    bool (*ready_cb)(struct _lv_fs_drv_t * drv);

    lv_fs_res_t (*open_cb)(struct _lv_fs_drv_t * drv, void * file_p, const char * path, lv_fs_mode_t mode);
    lv_fs_res_t (*close_cb)(struct _lv_fs_drv_t * drv, void * file_p);
    lv_fs_res_t (*remove_cb)(struct _lv_fs_drv_t * drv, const char * fn);
    lv_fs_res_t (*read_cb)(struct _lv_fs_drv_t * drv, void * file_p, void * buf, uint32_t btr, uint32_t * br);
    lv_fs_res_t (*write_cb)(struct _lv_fs_drv_t * drv, void * file_p, const void * buf, uint32_t btw, uint32_t * bw);
    lv_fs_res_t (*seek_cb)(struct _lv_fs_drv_t * drv, void * file_p, uint32_t pos);
    lv_fs_res_t (*tell_cb)(struct _lv_fs_drv_t * drv, void * file_p, uint32_t * pos_p);
    lv_fs_res_t (*trunc_cb)(struct _lv_fs_drv_t * drv, void * file_p);
    lv_fs_res_t (*size_cb)(struct _lv_fs_drv_t * drv, void * file_p, uint32_t * size_p);
    lv_fs_res_t (*rename_cb)(struct _lv_fs_drv_t * drv, const char * oldname, const char * newname);
    lv_fs_res_t (*free_space_cb)(struct _lv_fs_drv_t * drv, uint32_t * total_p, uint32_t * free_p);

    lv_fs_res_t (*dir_open_cb)(struct _lv_fs_drv_t * drv, void * rddir_p, const char * path);
    lv_fs_res_t (*dir_read_cb)(struct _lv_fs_drv_t * drv, void * rddir_p, char * fn);
    lv_fs_res_t (*dir_close_cb)(struct _lv_fs_drv_t * drv, void * rddir_p);




} lv_fs_drv_t;

typedef struct {
    void * file_d;
    lv_fs_drv_t * drv;
} lv_fs_file_t;

typedef struct {
    void * dir_d;
    lv_fs_drv_t * drv;
} lv_fs_dir_t;
# 107 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
void _lv_fs_init(void);







void lv_fs_drv_init(lv_fs_drv_t * drv);






void lv_fs_drv_register(lv_fs_drv_t * drv_p);






lv_fs_drv_t * lv_fs_get_drv(char letter);







bool lv_fs_is_ready(char letter);
# 146 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
lv_fs_res_t lv_fs_open(lv_fs_file_t * file_p, const char * path, lv_fs_mode_t mode);






lv_fs_res_t lv_fs_close(lv_fs_file_t * file_p);






lv_fs_res_t lv_fs_remove(const char * path);
# 170 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
lv_fs_res_t lv_fs_read(lv_fs_file_t * file_p, void * buf, uint32_t btr, uint32_t * br);
# 180 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
lv_fs_res_t lv_fs_write(lv_fs_file_t * file_p, const void * buf, uint32_t btw, uint32_t * bw);







lv_fs_res_t lv_fs_seek(lv_fs_file_t * file_p, uint32_t pos);







lv_fs_res_t lv_fs_tell(lv_fs_file_t * file_p, uint32_t * pos);







lv_fs_res_t lv_fs_trunc(lv_fs_file_t * file_p);







lv_fs_res_t lv_fs_size(lv_fs_file_t * file_p, uint32_t * size);







lv_fs_res_t lv_fs_rename(const char * oldname, const char * newname);







lv_fs_res_t lv_fs_dir_open(lv_fs_dir_t * rddir_p, const char * path);
# 237 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
lv_fs_res_t lv_fs_dir_read(lv_fs_dir_t * rddir_p, char * fn);






lv_fs_res_t lv_fs_dir_close(lv_fs_dir_t * rddir_p);
# 253 "./src/lv_core/../lv_draw/../lv_misc/lv_fs.h"
lv_fs_res_t lv_fs_free_space(char letter, uint32_t * total_p, uint32_t * free_p);






char * lv_fs_get_letters(char * buf);






const char * lv_fs_get_ext(const char * fn);






char * lv_fs_up(char * path);






const char * lv_fs_get_last(const char * path);
# 21 "./src/lv_core/../lv_draw/lv_img_decoder.h" 2
# 35 "./src/lv_core/../lv_draw/lv_img_decoder.h"
enum {
    LV_IMG_SRC_VARIABLE,
    LV_IMG_SRC_FILE,
    LV_IMG_SRC_SYMBOL,
    LV_IMG_SRC_UNKNOWN,
};

typedef uint8_t lv_img_src_t;



struct _lv_img_decoder;
struct _lv_img_decoder_dsc;
# 56 "./src/lv_core/../lv_draw/lv_img_decoder.h"
typedef lv_res_t (*lv_img_decoder_info_f_t)(struct _lv_img_decoder * decoder, const void * src,
                                            lv_img_header_t * header);






typedef lv_res_t (*lv_img_decoder_open_f_t)(struct _lv_img_decoder * decoder, struct _lv_img_decoder_dsc * dsc);
# 77 "./src/lv_core/../lv_draw/lv_img_decoder.h"
typedef lv_res_t (*lv_img_decoder_read_line_f_t)(struct _lv_img_decoder * decoder, struct _lv_img_decoder_dsc * dsc,
                                                 lv_coord_t x, lv_coord_t y, lv_coord_t len, uint8_t * buf);






typedef void (*lv_img_decoder_close_f_t)(struct _lv_img_decoder * decoder, struct _lv_img_decoder_dsc * dsc);

typedef struct _lv_img_decoder {
    lv_img_decoder_info_f_t info_cb;
    lv_img_decoder_open_f_t open_cb;
    lv_img_decoder_read_line_f_t read_line_cb;
    lv_img_decoder_close_f_t close_cb;




} lv_img_decoder_t;


typedef struct _lv_img_decoder_dsc {

    lv_img_decoder_t * decoder;


    const void * src;


    lv_color_t color;


    lv_img_src_t src_type;


    lv_img_header_t header;



    const uint8_t * img_data;



    uint32_t time_to_open;



    const char * error_msg;


    void * user_data;
} lv_img_decoder_dsc_t;
# 138 "./src/lv_core/../lv_draw/lv_img_decoder.h"
void _lv_img_decoder_init(void);
# 150 "./src/lv_core/../lv_draw/lv_img_decoder.h"
lv_res_t lv_img_decoder_get_info(const char * src, lv_img_header_t * header);
# 164 "./src/lv_core/../lv_draw/lv_img_decoder.h"
lv_res_t lv_img_decoder_open(lv_img_decoder_dsc_t * dsc, const void * src, lv_color_t color);
# 175 "./src/lv_core/../lv_draw/lv_img_decoder.h"
lv_res_t lv_img_decoder_read_line(lv_img_decoder_dsc_t * dsc, lv_coord_t x, lv_coord_t y, lv_coord_t len,
                                  uint8_t * buf);





void lv_img_decoder_close(lv_img_decoder_dsc_t * dsc);





lv_img_decoder_t * lv_img_decoder_create(void);





void lv_img_decoder_delete(lv_img_decoder_t * decoder);






void lv_img_decoder_set_info_cb(lv_img_decoder_t * decoder, lv_img_decoder_info_f_t info_cb);






void lv_img_decoder_set_open_cb(lv_img_decoder_t * decoder, lv_img_decoder_open_f_t open_cb);






void lv_img_decoder_set_read_line_cb(lv_img_decoder_t * decoder, lv_img_decoder_read_line_f_t read_line_cb);






void lv_img_decoder_set_close_cb(lv_img_decoder_t * decoder, lv_img_decoder_close_f_t close_cb);
# 231 "./src/lv_core/../lv_draw/lv_img_decoder.h"
lv_res_t lv_img_decoder_built_in_info(lv_img_decoder_t * decoder, const void * src, lv_img_header_t * header);







lv_res_t lv_img_decoder_built_in_open(lv_img_decoder_t * decoder, lv_img_decoder_dsc_t * dsc);
# 252 "./src/lv_core/../lv_draw/lv_img_decoder.h"
lv_res_t lv_img_decoder_built_in_read_line(lv_img_decoder_t * decoder, lv_img_decoder_dsc_t * dsc, lv_coord_t x,
                                           lv_coord_t y, lv_coord_t len, uint8_t * buf);






void lv_img_decoder_built_in_close(lv_img_decoder_t * decoder, lv_img_decoder_dsc_t * dsc);
# 17 "./src/lv_core/../lv_draw/lv_draw_img.h" 2
# 32 "./src/lv_core/../lv_draw/lv_draw_img.h"
typedef struct {
    lv_opa_t opa;

    uint16_t angle;
    lv_point_t pivot;
    uint16_t zoom;

    lv_opa_t recolor_opa;
    lv_color_t recolor;

    lv_blend_mode_t blend_mode;

    uint8_t antialias : 1;
} lv_draw_img_dsc_t;





void lv_draw_img_dsc_init(lv_draw_img_dsc_t * dsc);







void lv_draw_img(const lv_area_t * coords, const lv_area_t * mask, const void * src, const lv_draw_img_dsc_t * dsc);
# 69 "./src/lv_core/../lv_draw/lv_draw_img.h"
lv_img_src_t lv_img_src_get_type(const void * src);






uint8_t lv_img_cf_get_px_size(lv_img_cf_t cf);






bool lv_img_cf_is_chroma_keyed(lv_img_cf_t cf);






bool lv_img_cf_has_alpha(lv_img_cf_t cf);
# 30 "./src/lv_core/lv_obj.h" 2
# 57 "./src/lv_core/lv_obj.h"
struct _lv_obj_t;


enum {
    LV_DESIGN_DRAW_MAIN,
    LV_DESIGN_DRAW_POST,
    LV_DESIGN_COVER_CHK,
};
typedef uint8_t lv_design_mode_t;


enum {
    LV_DESIGN_RES_OK,
    LV_DESIGN_RES_COVER,
    LV_DESIGN_RES_NOT_COVER,
    LV_DESIGN_RES_MASKED,
};
typedef uint8_t lv_design_res_t;





typedef lv_design_res_t (*lv_design_cb_t)(struct _lv_obj_t * obj, const lv_area_t * clip_area, lv_design_mode_t mode);

enum {
    LV_EVENT_PRESSED,
    LV_EVENT_PRESSING,
    LV_EVENT_PRESS_LOST,
    LV_EVENT_SHORT_CLICKED,
    LV_EVENT_LONG_PRESSED,
    LV_EVENT_LONG_PRESSED_REPEAT,

    LV_EVENT_CLICKED,
    LV_EVENT_RELEASED,
    LV_EVENT_DRAG_BEGIN,
    LV_EVENT_DRAG_END,
    LV_EVENT_DRAG_THROW_BEGIN,
    LV_EVENT_GESTURE,
    LV_EVENT_KEY,
    LV_EVENT_FOCUSED,
    LV_EVENT_DEFOCUSED,
    LV_EVENT_LEAVE,
    LV_EVENT_VALUE_CHANGED,
    LV_EVENT_INSERT,
    LV_EVENT_REFRESH,
    LV_EVENT_APPLY,
    LV_EVENT_CANCEL,
    LV_EVENT_DELETE,
    _LV_EVENT_LAST
};
typedef uint8_t lv_event_t;






typedef void (*lv_event_cb_t)(struct _lv_obj_t * obj, lv_event_t event);




enum {

    LV_SIGNAL_CLEANUP,
    LV_SIGNAL_CHILD_CHG,
    LV_SIGNAL_COORD_CHG,
    LV_SIGNAL_PARENT_SIZE_CHG,
    LV_SIGNAL_STYLE_CHG,
    LV_SIGNAL_BASE_DIR_CHG,
    LV_SIGNAL_REFR_EXT_DRAW_PAD,
    LV_SIGNAL_GET_TYPE,
    LV_SIGNAL_GET_STYLE,
    LV_SIGNAL_GET_STATE_DSC,


    LV_SIGNAL_HIT_TEST,
    LV_SIGNAL_PRESSED,
    LV_SIGNAL_PRESSING,
    LV_SIGNAL_PRESS_LOST,
    LV_SIGNAL_RELEASED,
    LV_SIGNAL_LONG_PRESS,
    LV_SIGNAL_LONG_PRESS_REP,
    LV_SIGNAL_DRAG_BEGIN,
    LV_SIGNAL_DRAG_THROW_BEGIN,
    LV_SIGNAL_DRAG_END,
    LV_SIGNAL_GESTURE,
    LV_SIGNAL_LEAVE,


    LV_SIGNAL_FOCUS,
    LV_SIGNAL_DEFOCUS,
    LV_SIGNAL_CONTROL,
    LV_SIGNAL_GET_EDITABLE,
};
typedef uint8_t lv_signal_t;

typedef lv_res_t (*lv_signal_cb_t)(struct _lv_obj_t * obj, lv_signal_t sign, void * param);


typedef struct {
    const struct _lv_obj_t * base;
    lv_coord_t xofs;
    lv_coord_t yofs;
    lv_align_t align;
    uint8_t auto_realign : 1;
    uint8_t mid_align : 1;

} lv_realign_t;



enum {
    LV_PROTECT_NONE = 0x00,
    LV_PROTECT_CHILD_CHG = 0x01,
    LV_PROTECT_PARENT = 0x02,
    LV_PROTECT_POS = 0x04,
    LV_PROTECT_FOLLOW = 0x08,

    LV_PROTECT_PRESS_LOST = 0x10,

    LV_PROTECT_CLICK_FOCUS = 0x20,
    LV_PROTECT_EVENT_TO_DISABLED = 0x40,
};
typedef uint8_t lv_protect_t;

enum {
    LV_STATE_DEFAULT = 0x00,
    LV_STATE_CHECKED = 0x01,
    LV_STATE_FOCUSED = 0x02,
    LV_STATE_EDITED = 0x04,
    LV_STATE_HOVERED = 0x08,
    LV_STATE_PRESSED = 0x10,
    LV_STATE_DISABLED = 0x20,
};

typedef uint8_t lv_state_t;

typedef struct _lv_obj_t {
    struct _lv_obj_t * parent;
    lv_ll_t child_ll;

    lv_area_t coords;

    lv_event_cb_t event_cb;
    lv_signal_cb_t signal_cb;
    lv_design_cb_t design_cb;

    void * ext_attr;
    lv_style_list_t style_list;


    uint8_t ext_click_pad_hor;
    uint8_t ext_click_pad_ver;




    lv_coord_t ext_draw_pad;


    uint8_t click : 1;
    uint8_t drag : 1;
    uint8_t drag_throw : 1;
    uint8_t drag_parent : 1;
    uint8_t hidden : 1;
    uint8_t top : 1;
    uint8_t parent_event : 1;
    uint8_t adv_hittest : 1;
    uint8_t gesture_parent : 1;
    uint8_t focus_parent : 1;

    lv_drag_dir_t drag_dir : 3;
    lv_bidi_dir_t base_dir : 2;


    void * group_p;


    uint8_t protect;

    lv_state_t state;


    lv_realign_t realign;






} lv_obj_t;

enum {
    LV_OBJ_PART_MAIN,
    _LV_OBJ_PART_VIRTUAL_LAST = 0x01,
    _LV_OBJ_PART_REAL_LAST = 0x40,
    LV_OBJ_PART_ALL = 0xFF,
};

typedef uint8_t lv_obj_part_t;


typedef struct {
    const char * type[8];

} lv_obj_type_t;

typedef struct {
    lv_point_t * point;
    bool result;
} lv_hit_test_info_t;

typedef struct {
    uint8_t part;
    lv_style_list_t * result;
} lv_get_style_info_t;

typedef struct {
    uint8_t part;
    lv_state_t result;
} lv_get_state_info_t;
# 288 "./src/lv_core/lv_obj.h"
void lv_init(void);
# 309 "./src/lv_core/lv_obj.h"
lv_obj_t * lv_obj_create(lv_obj_t * parent, const lv_obj_t * copy);






lv_res_t lv_obj_del(lv_obj_t * obj);






void lv_obj_del_anim_ready_cb(lv_anim_t * a);
# 332 "./src/lv_core/lv_obj.h"
void lv_obj_del_async(struct _lv_obj_t * obj);





void lv_obj_clean(lv_obj_t * obj);







void lv_obj_invalidate_area(const lv_obj_t * obj, const lv_area_t * area);





void lv_obj_invalidate(const lv_obj_t * obj);







bool lv_obj_area_is_visible(const lv_obj_t * obj, lv_area_t * area);






bool lv_obj_is_visible(const lv_obj_t * obj);
# 382 "./src/lv_core/lv_obj.h"
void lv_obj_set_parent(lv_obj_t * obj, lv_obj_t * parent);





void lv_obj_move_foreground(lv_obj_t * obj);





void lv_obj_move_background(lv_obj_t * obj);
# 406 "./src/lv_core/lv_obj.h"
void lv_obj_set_pos(lv_obj_t * obj, lv_coord_t x, lv_coord_t y);






void lv_obj_set_x(lv_obj_t * obj, lv_coord_t x);






void lv_obj_set_y(lv_obj_t * obj, lv_coord_t y);







void lv_obj_set_size(lv_obj_t * obj, lv_coord_t w, lv_coord_t h);






void lv_obj_set_width(lv_obj_t * obj, lv_coord_t w);






void lv_obj_set_height(lv_obj_t * obj, lv_coord_t h);






void lv_obj_set_width_fit(lv_obj_t * obj, lv_coord_t w);






void lv_obj_set_height_fit(lv_obj_t * obj, lv_coord_t h);







void lv_obj_set_width_margin(lv_obj_t * obj, lv_coord_t w);







void lv_obj_set_height_margin(lv_obj_t * obj, lv_coord_t h);
# 482 "./src/lv_core/lv_obj.h"
void lv_obj_align(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t x_ofs, lv_coord_t y_ofs);
# 491 "./src/lv_core/lv_obj.h"
void lv_obj_align_x(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t x_ofs);
# 500 "./src/lv_core/lv_obj.h"
void lv_obj_align_y(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t y_ofs);
# 510 "./src/lv_core/lv_obj.h"
void lv_obj_align_mid(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t x_ofs, lv_coord_t y_ofs);
# 519 "./src/lv_core/lv_obj.h"
void lv_obj_align_mid_x(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t x_ofs);
# 528 "./src/lv_core/lv_obj.h"
void lv_obj_align_mid_y(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t y_ofs);





void lv_obj_realign(lv_obj_t * obj);







void lv_obj_set_auto_realign(lv_obj_t * obj, bool en);
# 552 "./src/lv_core/lv_obj.h"
void lv_obj_set_ext_click_area(lv_obj_t * obj, lv_coord_t left, lv_coord_t right, lv_coord_t top, lv_coord_t bottom);
# 565 "./src/lv_core/lv_obj.h"
void lv_obj_add_style(lv_obj_t * obj, uint8_t part, lv_style_t * style);
# 574 "./src/lv_core/lv_obj.h"
void lv_obj_remove_style(lv_obj_t * obj, uint8_t part, lv_style_t * style);
# 584 "./src/lv_core/lv_obj.h"
void lv_obj_clean_style_list(lv_obj_t * obj, uint8_t part);
# 594 "./src/lv_core/lv_obj.h"
void lv_obj_reset_style_list(lv_obj_t * obj, uint8_t part);






void lv_obj_refresh_style(lv_obj_t * obj, uint8_t part, lv_style_property_t prop);






void lv_obj_report_style_mod(lv_style_t * style);
# 622 "./src/lv_core/lv_obj.h"
void _lv_obj_set_style_local_color(lv_obj_t * obj, uint8_t type, lv_style_property_t prop, lv_color_t color);
# 636 "./src/lv_core/lv_obj.h"
void _lv_obj_set_style_local_int(lv_obj_t * obj, uint8_t type, lv_style_property_t prop, lv_style_int_t value);
# 650 "./src/lv_core/lv_obj.h"
void _lv_obj_set_style_local_opa(lv_obj_t * obj, uint8_t type, lv_style_property_t prop, lv_opa_t opa);
# 664 "./src/lv_core/lv_obj.h"
void _lv_obj_set_style_local_ptr(lv_obj_t * obj, uint8_t type, lv_style_property_t prop, const void * value);
# 677 "./src/lv_core/lv_obj.h"
bool lv_obj_remove_style_local_prop(lv_obj_t * obj, uint8_t part, lv_style_property_t prop);






void _lv_obj_disable_style_caching(lv_obj_t * obj, bool dis);
# 695 "./src/lv_core/lv_obj.h"
void lv_obj_set_hidden(lv_obj_t * obj, bool en);






void lv_obj_set_adv_hittest(lv_obj_t * obj, bool en);






void lv_obj_set_click(lv_obj_t * obj, bool en);







void lv_obj_set_top(lv_obj_t * obj, bool en);






void lv_obj_set_drag(lv_obj_t * obj, bool en);






void lv_obj_set_drag_dir(lv_obj_t * obj, lv_drag_dir_t drag_dir);






void lv_obj_set_drag_throw(lv_obj_t * obj, bool en);







void lv_obj_set_drag_parent(lv_obj_t * obj, bool en);







void lv_obj_set_focus_parent(lv_obj_t * obj, bool en);







void lv_obj_set_gesture_parent(lv_obj_t * obj, bool en);






void lv_obj_set_parent_event(lv_obj_t * obj, bool en);







void lv_obj_set_base_dir(lv_obj_t * obj, lv_bidi_dir_t dir);






void lv_obj_add_protect(lv_obj_t * obj, uint8_t prot);






void lv_obj_clear_protect(lv_obj_t * obj, uint8_t prot);
# 800 "./src/lv_core/lv_obj.h"
void lv_obj_set_state(lv_obj_t * obj, lv_state_t state);
# 809 "./src/lv_core/lv_obj.h"
void lv_obj_add_state(lv_obj_t * obj, lv_state_t state);
# 818 "./src/lv_core/lv_obj.h"
void lv_obj_clear_state(lv_obj_t * obj, lv_state_t state);







void lv_obj_finish_transitions(lv_obj_t * obj, uint8_t part);
# 835 "./src/lv_core/lv_obj.h"
void lv_obj_set_event_cb(lv_obj_t * obj, lv_event_cb_t event_cb);
# 844 "./src/lv_core/lv_obj.h"
lv_res_t lv_event_send(lv_obj_t * obj, lv_event_t event, const void * data);






lv_res_t lv_event_send_refresh(lv_obj_t * obj);





void lv_event_send_refresh_recursive(lv_obj_t * obj);
# 869 "./src/lv_core/lv_obj.h"
lv_res_t lv_event_send_func(lv_event_cb_t event_xcb, lv_obj_t * obj, lv_event_t event, const void * data);





const void * lv_event_get_data(void);







void lv_obj_set_signal_cb(lv_obj_t * obj, lv_signal_cb_t signal_cb);







lv_res_t lv_signal_send(lv_obj_t * obj, lv_signal_t signal, void * param);






void lv_obj_set_design_cb(lv_obj_t * obj, lv_design_cb_t design_cb);
# 910 "./src/lv_core/lv_obj.h"
void * lv_obj_allocate_ext_attr(lv_obj_t * obj, uint16_t ext_size);






void lv_obj_refresh_ext_draw_pad(lv_obj_t * obj);
# 928 "./src/lv_core/lv_obj.h"
lv_obj_t * lv_obj_get_screen(const lv_obj_t * obj);





lv_disp_t * lv_obj_get_disp(const lv_obj_t * obj);
# 945 "./src/lv_core/lv_obj.h"
lv_obj_t * lv_obj_get_parent(const lv_obj_t * obj);
# 954 "./src/lv_core/lv_obj.h"
lv_obj_t * lv_obj_get_child(const lv_obj_t * obj, const lv_obj_t * child);
# 963 "./src/lv_core/lv_obj.h"
lv_obj_t * lv_obj_get_child_back(const lv_obj_t * obj, const lv_obj_t * child);






uint16_t lv_obj_count_children(const lv_obj_t * obj);





uint16_t lv_obj_count_children_recursive(const lv_obj_t * obj);
# 987 "./src/lv_core/lv_obj.h"
void lv_obj_get_coords(const lv_obj_t * obj, lv_area_t * cords_p);






void lv_obj_get_inner_coords(const lv_obj_t * obj, lv_area_t * coords_p);






lv_coord_t lv_obj_get_x(const lv_obj_t * obj);






lv_coord_t lv_obj_get_y(const lv_obj_t * obj);






lv_coord_t lv_obj_get_width(const lv_obj_t * obj);






lv_coord_t lv_obj_get_height(const lv_obj_t * obj);






lv_coord_t lv_obj_get_width_fit(const lv_obj_t * obj);






lv_coord_t lv_obj_get_height_fit(const lv_obj_t * obj);







lv_coord_t lv_obj_get_height_margin(lv_obj_t * obj);







lv_coord_t lv_obj_get_width_margin(lv_obj_t * obj);
# 1065 "./src/lv_core/lv_obj.h"
lv_coord_t lv_obj_get_width_grid(lv_obj_t * obj, uint8_t div, uint8_t span);
# 1078 "./src/lv_core/lv_obj.h"
lv_coord_t lv_obj_get_height_grid(lv_obj_t * obj, uint8_t div, uint8_t span);






bool lv_obj_get_auto_realign(const lv_obj_t * obj);






lv_coord_t lv_obj_get_ext_click_pad_left(const lv_obj_t * obj);






lv_coord_t lv_obj_get_ext_click_pad_right(const lv_obj_t * obj);






lv_coord_t lv_obj_get_ext_click_pad_top(const lv_obj_t * obj);






lv_coord_t lv_obj_get_ext_click_pad_bottom(const lv_obj_t * obj);






lv_coord_t lv_obj_get_ext_draw_pad(const lv_obj_t * obj);
# 1133 "./src/lv_core/lv_obj.h"
lv_style_list_t * lv_obj_get_style_list(const lv_obj_t * obj, uint8_t part);
# 1149 "./src/lv_core/lv_obj.h"
lv_style_int_t _lv_obj_get_style_int(const lv_obj_t * obj, uint8_t part, lv_style_property_t prop);
# 1165 "./src/lv_core/lv_obj.h"
lv_color_t _lv_obj_get_style_color(const lv_obj_t * obj, uint8_t part, lv_style_property_t prop);
# 1181 "./src/lv_core/lv_obj.h"
lv_opa_t _lv_obj_get_style_opa(const lv_obj_t * obj, uint8_t part, lv_style_property_t prop);
# 1197 "./src/lv_core/lv_obj.h"
const void * _lv_obj_get_style_ptr(const lv_obj_t * obj, uint8_t part, lv_style_property_t prop);
# 1206 "./src/lv_core/lv_obj.h"
lv_style_t * lv_obj_get_local_style(lv_obj_t * obj, uint8_t part);


# 1 "./src/lv_core/lv_obj_style_dec.h" 1
# 79 "./src/lv_core/lv_obj_style_dec.h"
static inline lv_style_int_t lv_obj_get_style_radius(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_RADIUS); } static inline void lv_obj_set_style_local_radius(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_RADIUS | (state << 8), value); } static inline void lv_style_set_radius(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_RADIUS | (state << 8), value); }
static inline bool lv_obj_get_style_clip_corner(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_CLIP_CORNER); } static inline void lv_obj_set_style_local_clip_corner(lv_obj_t * obj, uint8_t part, lv_state_t state, bool value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_CLIP_CORNER | (state << 8), value); } static inline void lv_style_set_clip_corner(lv_style_t * style, lv_state_t state, bool value) { _lv_style_set_int(style, LV_STYLE_CLIP_CORNER | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_size(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SIZE); } static inline void lv_obj_set_style_local_size(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SIZE | (state << 8), value); } static inline void lv_style_set_size(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SIZE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transform_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSFORM_WIDTH); } static inline void lv_obj_set_style_local_transform_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSFORM_WIDTH | (state << 8), value); } static inline void lv_style_set_transform_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSFORM_WIDTH | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transform_height(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSFORM_HEIGHT); } static inline void lv_obj_set_style_local_transform_height(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSFORM_HEIGHT | (state << 8), value); } static inline void lv_style_set_transform_height(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSFORM_HEIGHT | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transform_angle(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSFORM_ANGLE); } static inline void lv_obj_set_style_local_transform_angle(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSFORM_ANGLE | (state << 8), value); } static inline void lv_style_set_transform_angle(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSFORM_ANGLE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transform_zoom(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSFORM_ZOOM); } static inline void lv_obj_set_style_local_transform_zoom(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSFORM_ZOOM | (state << 8), value); } static inline void lv_style_set_transform_zoom(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSFORM_ZOOM | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_opa_scale(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_OPA_SCALE); } static inline void lv_obj_set_style_local_opa_scale(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_OPA_SCALE | (state << 8), value); } static inline void lv_style_set_opa_scale(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_OPA_SCALE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_pad_top(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_PAD_TOP); } static inline void lv_obj_set_style_local_pad_top(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_PAD_TOP | (state << 8), value); } static inline void lv_style_set_pad_top(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_PAD_TOP | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_pad_bottom(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_PAD_BOTTOM); } static inline void lv_obj_set_style_local_pad_bottom(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_PAD_BOTTOM | (state << 8), value); } static inline void lv_style_set_pad_bottom(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_PAD_BOTTOM | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_pad_left(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_PAD_LEFT); } static inline void lv_obj_set_style_local_pad_left(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_PAD_LEFT | (state << 8), value); } static inline void lv_style_set_pad_left(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_PAD_LEFT | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_pad_right(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_PAD_RIGHT); } static inline void lv_obj_set_style_local_pad_right(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_PAD_RIGHT | (state << 8), value); } static inline void lv_style_set_pad_right(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_PAD_RIGHT | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_pad_inner(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_PAD_INNER); } static inline void lv_obj_set_style_local_pad_inner(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_PAD_INNER | (state << 8), value); } static inline void lv_style_set_pad_inner(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_PAD_INNER | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_margin_top(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_MARGIN_TOP); } static inline void lv_obj_set_style_local_margin_top(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_MARGIN_TOP | (state << 8), value); } static inline void lv_style_set_margin_top(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_MARGIN_TOP | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_margin_bottom(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_MARGIN_BOTTOM); } static inline void lv_obj_set_style_local_margin_bottom(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_MARGIN_BOTTOM | (state << 8), value); } static inline void lv_style_set_margin_bottom(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_MARGIN_BOTTOM | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_margin_left(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_MARGIN_LEFT); } static inline void lv_obj_set_style_local_margin_left(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_MARGIN_LEFT | (state << 8), value); } static inline void lv_style_set_margin_left(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_MARGIN_LEFT | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_margin_right(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_MARGIN_RIGHT); } static inline void lv_obj_set_style_local_margin_right(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_MARGIN_RIGHT | (state << 8), value); } static inline void lv_style_set_margin_right(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_MARGIN_RIGHT | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_bg_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BG_BLEND_MODE); } static inline void lv_obj_set_style_local_bg_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BG_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_bg_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_BG_BLEND_MODE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_bg_main_stop(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BG_MAIN_STOP); } static inline void lv_obj_set_style_local_bg_main_stop(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BG_MAIN_STOP | (state << 8), value); } static inline void lv_style_set_bg_main_stop(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_BG_MAIN_STOP | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_bg_grad_stop(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BG_GRAD_STOP); } static inline void lv_obj_set_style_local_bg_grad_stop(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BG_GRAD_STOP | (state << 8), value); } static inline void lv_style_set_bg_grad_stop(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_BG_GRAD_STOP | (state << 8), value); }
static inline lv_grad_dir_t lv_obj_get_style_bg_grad_dir(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BG_GRAD_DIR); } static inline void lv_obj_set_style_local_bg_grad_dir(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_grad_dir_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BG_GRAD_DIR | (state << 8), value); } static inline void lv_style_set_bg_grad_dir(lv_style_t * style, lv_state_t state, lv_grad_dir_t value) { _lv_style_set_int(style, LV_STYLE_BG_GRAD_DIR | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_bg_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_BG_COLOR); } static inline void lv_obj_set_style_local_bg_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_BG_COLOR | (state << 8), value); } static inline void lv_style_set_bg_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_BG_COLOR | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_bg_grad_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_BG_GRAD_COLOR); } static inline void lv_obj_set_style_local_bg_grad_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_BG_GRAD_COLOR | (state << 8), value); } static inline void lv_style_set_bg_grad_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_BG_GRAD_COLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_bg_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_BG_OPA); } static inline void lv_obj_set_style_local_bg_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_BG_OPA | (state << 8), value); } static inline void lv_style_set_bg_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_BG_OPA | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_border_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BORDER_WIDTH); } static inline void lv_obj_set_style_local_border_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BORDER_WIDTH | (state << 8), value); } static inline void lv_style_set_border_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_BORDER_WIDTH | (state << 8), value); }
static inline lv_border_side_t lv_obj_get_style_border_side(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BORDER_SIDE); } static inline void lv_obj_set_style_local_border_side(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_border_side_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BORDER_SIDE | (state << 8), value); } static inline void lv_style_set_border_side(lv_style_t * style, lv_state_t state, lv_border_side_t value) { _lv_style_set_int(style, LV_STYLE_BORDER_SIDE | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_border_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BORDER_BLEND_MODE); } static inline void lv_obj_set_style_local_border_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BORDER_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_border_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_BORDER_BLEND_MODE | (state << 8), value); }
static inline bool lv_obj_get_style_border_post(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_BORDER_POST); } static inline void lv_obj_set_style_local_border_post(lv_obj_t * obj, uint8_t part, lv_state_t state, bool value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_BORDER_POST | (state << 8), value); } static inline void lv_style_set_border_post(lv_style_t * style, lv_state_t state, bool value) { _lv_style_set_int(style, LV_STYLE_BORDER_POST | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_border_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_BORDER_COLOR); } static inline void lv_obj_set_style_local_border_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_BORDER_COLOR | (state << 8), value); } static inline void lv_style_set_border_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_BORDER_COLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_border_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_BORDER_OPA); } static inline void lv_obj_set_style_local_border_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_BORDER_OPA | (state << 8), value); } static inline void lv_style_set_border_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_BORDER_OPA | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_outline_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_OUTLINE_WIDTH); } static inline void lv_obj_set_style_local_outline_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_OUTLINE_WIDTH | (state << 8), value); } static inline void lv_style_set_outline_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_OUTLINE_WIDTH | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_outline_pad(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_OUTLINE_PAD); } static inline void lv_obj_set_style_local_outline_pad(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_OUTLINE_PAD | (state << 8), value); } static inline void lv_style_set_outline_pad(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_OUTLINE_PAD | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_outline_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_OUTLINE_BLEND_MODE); } static inline void lv_obj_set_style_local_outline_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_OUTLINE_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_outline_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_OUTLINE_BLEND_MODE | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_outline_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_OUTLINE_COLOR); } static inline void lv_obj_set_style_local_outline_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_OUTLINE_COLOR | (state << 8), value); } static inline void lv_style_set_outline_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_OUTLINE_COLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_outline_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_OUTLINE_OPA); } static inline void lv_obj_set_style_local_outline_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_OUTLINE_OPA | (state << 8), value); } static inline void lv_style_set_outline_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_OUTLINE_OPA | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_shadow_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SHADOW_WIDTH); } static inline void lv_obj_set_style_local_shadow_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SHADOW_WIDTH | (state << 8), value); } static inline void lv_style_set_shadow_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SHADOW_WIDTH | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_shadow_ofs_x(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SHADOW_OFS_X); } static inline void lv_obj_set_style_local_shadow_ofs_x(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SHADOW_OFS_X | (state << 8), value); } static inline void lv_style_set_shadow_ofs_x(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SHADOW_OFS_X | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_shadow_ofs_y(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SHADOW_OFS_Y); } static inline void lv_obj_set_style_local_shadow_ofs_y(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SHADOW_OFS_Y | (state << 8), value); } static inline void lv_style_set_shadow_ofs_y(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SHADOW_OFS_Y | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_shadow_spread(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SHADOW_SPREAD); } static inline void lv_obj_set_style_local_shadow_spread(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SHADOW_SPREAD | (state << 8), value); } static inline void lv_style_set_shadow_spread(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SHADOW_SPREAD | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_shadow_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SHADOW_BLEND_MODE); } static inline void lv_obj_set_style_local_shadow_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SHADOW_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_shadow_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_SHADOW_BLEND_MODE | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_shadow_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_SHADOW_COLOR); } static inline void lv_obj_set_style_local_shadow_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_SHADOW_COLOR | (state << 8), value); } static inline void lv_style_set_shadow_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_SHADOW_COLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_shadow_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_SHADOW_OPA); } static inline void lv_obj_set_style_local_shadow_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_SHADOW_OPA | (state << 8), value); } static inline void lv_style_set_shadow_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_SHADOW_OPA | (state << 8), value); }
static inline bool lv_obj_get_style_pattern_repeat(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_PATTERN_REPEAT); } static inline void lv_obj_set_style_local_pattern_repeat(lv_obj_t * obj, uint8_t part, lv_state_t state, bool value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_PATTERN_REPEAT | (state << 8), value); } static inline void lv_style_set_pattern_repeat(lv_style_t * style, lv_state_t state, bool value) { _lv_style_set_int(style, LV_STYLE_PATTERN_REPEAT | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_pattern_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_PATTERN_BLEND_MODE); } static inline void lv_obj_set_style_local_pattern_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_PATTERN_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_pattern_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_PATTERN_BLEND_MODE | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_pattern_recolor(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_PATTERN_RECOLOR); } static inline void lv_obj_set_style_local_pattern_recolor(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_PATTERN_RECOLOR | (state << 8), value); } static inline void lv_style_set_pattern_recolor(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_PATTERN_RECOLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_pattern_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_PATTERN_OPA); } static inline void lv_obj_set_style_local_pattern_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_PATTERN_OPA | (state << 8), value); } static inline void lv_style_set_pattern_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_PATTERN_OPA | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_pattern_recolor_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_PATTERN_RECOLOR_OPA); } static inline void lv_obj_set_style_local_pattern_recolor_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_PATTERN_RECOLOR_OPA | (state << 8), value); } static inline void lv_style_set_pattern_recolor_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_PATTERN_RECOLOR_OPA | (state << 8), value); }
static inline const void * lv_obj_get_style_pattern_image(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_ptr(obj, part, LV_STYLE_PATTERN_IMAGE); } static inline void lv_obj_set_style_local_pattern_image(lv_obj_t * obj, uint8_t part, lv_state_t state, const void * value) { _lv_obj_set_style_local_ptr(obj, part, LV_STYLE_PATTERN_IMAGE | (state << 8), value); } static inline void lv_style_set_pattern_image(lv_style_t * style, lv_state_t state, const void * value) { _lv_style_set_ptr(style, LV_STYLE_PATTERN_IMAGE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_value_letter_space(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_VALUE_LETTER_SPACE); } static inline void lv_obj_set_style_local_value_letter_space(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_VALUE_LETTER_SPACE | (state << 8), value); } static inline void lv_style_set_value_letter_space(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_VALUE_LETTER_SPACE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_value_line_space(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_VALUE_LINE_SPACE); } static inline void lv_obj_set_style_local_value_line_space(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_VALUE_LINE_SPACE | (state << 8), value); } static inline void lv_style_set_value_line_space(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_VALUE_LINE_SPACE | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_value_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_VALUE_BLEND_MODE); } static inline void lv_obj_set_style_local_value_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_VALUE_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_value_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_VALUE_BLEND_MODE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_value_ofs_x(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_VALUE_OFS_X); } static inline void lv_obj_set_style_local_value_ofs_x(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_VALUE_OFS_X | (state << 8), value); } static inline void lv_style_set_value_ofs_x(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_VALUE_OFS_X | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_value_ofs_y(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_VALUE_OFS_Y); } static inline void lv_obj_set_style_local_value_ofs_y(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_VALUE_OFS_Y | (state << 8), value); } static inline void lv_style_set_value_ofs_y(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_VALUE_OFS_Y | (state << 8), value); }
static inline lv_align_t lv_obj_get_style_value_align(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_VALUE_ALIGN); } static inline void lv_obj_set_style_local_value_align(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_align_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_VALUE_ALIGN | (state << 8), value); } static inline void lv_style_set_value_align(lv_style_t * style, lv_state_t state, lv_align_t value) { _lv_style_set_int(style, LV_STYLE_VALUE_ALIGN | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_value_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_VALUE_COLOR); } static inline void lv_obj_set_style_local_value_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_VALUE_COLOR | (state << 8), value); } static inline void lv_style_set_value_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_VALUE_COLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_value_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_VALUE_OPA); } static inline void lv_obj_set_style_local_value_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_VALUE_OPA | (state << 8), value); } static inline void lv_style_set_value_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_VALUE_OPA | (state << 8), value); }
static inline const lv_font_t * lv_obj_get_style_value_font(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_ptr(obj, part, LV_STYLE_VALUE_FONT); } static inline void lv_obj_set_style_local_value_font(lv_obj_t * obj, uint8_t part, lv_state_t state, const lv_font_t * value) { _lv_obj_set_style_local_ptr(obj, part, LV_STYLE_VALUE_FONT | (state << 8), value); } static inline void lv_style_set_value_font(lv_style_t * style, lv_state_t state, const lv_font_t * value) { _lv_style_set_ptr(style, LV_STYLE_VALUE_FONT | (state << 8), value); }
static inline const char * lv_obj_get_style_value_str(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_ptr(obj, part, LV_STYLE_VALUE_STR); } static inline void lv_obj_set_style_local_value_str(lv_obj_t * obj, uint8_t part, lv_state_t state, const char * value) { _lv_obj_set_style_local_ptr(obj, part, LV_STYLE_VALUE_STR | (state << 8), value); } static inline void lv_style_set_value_str(lv_style_t * style, lv_state_t state, const char * value) { _lv_style_set_ptr(style, LV_STYLE_VALUE_STR | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_text_letter_space(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TEXT_LETTER_SPACE); } static inline void lv_obj_set_style_local_text_letter_space(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TEXT_LETTER_SPACE | (state << 8), value); } static inline void lv_style_set_text_letter_space(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TEXT_LETTER_SPACE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_text_line_space(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TEXT_LINE_SPACE); } static inline void lv_obj_set_style_local_text_line_space(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TEXT_LINE_SPACE | (state << 8), value); } static inline void lv_style_set_text_line_space(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TEXT_LINE_SPACE | (state << 8), value); }
static inline lv_text_decor_t lv_obj_get_style_text_decor(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TEXT_DECOR); } static inline void lv_obj_set_style_local_text_decor(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_text_decor_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TEXT_DECOR | (state << 8), value); } static inline void lv_style_set_text_decor(lv_style_t * style, lv_state_t state, lv_text_decor_t value) { _lv_style_set_int(style, LV_STYLE_TEXT_DECOR | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_text_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TEXT_BLEND_MODE); } static inline void lv_obj_set_style_local_text_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TEXT_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_text_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_TEXT_BLEND_MODE | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_text_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_TEXT_COLOR); } static inline void lv_obj_set_style_local_text_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_TEXT_COLOR | (state << 8), value); } static inline void lv_style_set_text_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_TEXT_COLOR | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_text_sel_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_TEXT_SEL_COLOR); } static inline void lv_obj_set_style_local_text_sel_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_TEXT_SEL_COLOR | (state << 8), value); } static inline void lv_style_set_text_sel_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_TEXT_SEL_COLOR | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_text_sel_bg_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_TEXT_SEL_BG_COLOR); } static inline void lv_obj_set_style_local_text_sel_bg_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_TEXT_SEL_BG_COLOR | (state << 8), value); } static inline void lv_style_set_text_sel_bg_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_TEXT_SEL_BG_COLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_text_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_TEXT_OPA); } static inline void lv_obj_set_style_local_text_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_TEXT_OPA | (state << 8), value); } static inline void lv_style_set_text_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_TEXT_OPA | (state << 8), value); }
static inline const lv_font_t * lv_obj_get_style_text_font(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_ptr(obj, part, LV_STYLE_TEXT_FONT); } static inline void lv_obj_set_style_local_text_font(lv_obj_t * obj, uint8_t part, lv_state_t state, const lv_font_t * value) { _lv_obj_set_style_local_ptr(obj, part, LV_STYLE_TEXT_FONT | (state << 8), value); } static inline void lv_style_set_text_font(lv_style_t * style, lv_state_t state, const lv_font_t * value) { _lv_style_set_ptr(style, LV_STYLE_TEXT_FONT | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_line_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_LINE_WIDTH); } static inline void lv_obj_set_style_local_line_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_LINE_WIDTH | (state << 8), value); } static inline void lv_style_set_line_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_LINE_WIDTH | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_line_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_LINE_BLEND_MODE); } static inline void lv_obj_set_style_local_line_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_LINE_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_line_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_LINE_BLEND_MODE | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_line_dash_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_LINE_DASH_WIDTH); } static inline void lv_obj_set_style_local_line_dash_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_LINE_DASH_WIDTH | (state << 8), value); } static inline void lv_style_set_line_dash_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_LINE_DASH_WIDTH | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_line_dash_gap(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_LINE_DASH_GAP); } static inline void lv_obj_set_style_local_line_dash_gap(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_LINE_DASH_GAP | (state << 8), value); } static inline void lv_style_set_line_dash_gap(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_LINE_DASH_GAP | (state << 8), value); }
static inline bool lv_obj_get_style_line_rounded(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_LINE_ROUNDED); } static inline void lv_obj_set_style_local_line_rounded(lv_obj_t * obj, uint8_t part, lv_state_t state, bool value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_LINE_ROUNDED | (state << 8), value); } static inline void lv_style_set_line_rounded(lv_style_t * style, lv_state_t state, bool value) { _lv_style_set_int(style, LV_STYLE_LINE_ROUNDED | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_line_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_LINE_COLOR); } static inline void lv_obj_set_style_local_line_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_LINE_COLOR | (state << 8), value); } static inline void lv_style_set_line_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_LINE_COLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_line_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_LINE_OPA); } static inline void lv_obj_set_style_local_line_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_LINE_OPA | (state << 8), value); } static inline void lv_style_set_line_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_LINE_OPA | (state << 8), value); }
static inline lv_blend_mode_t lv_obj_get_style_image_blend_mode(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_IMAGE_BLEND_MODE); } static inline void lv_obj_set_style_local_image_blend_mode(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_blend_mode_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_IMAGE_BLEND_MODE | (state << 8), value); } static inline void lv_style_set_image_blend_mode(lv_style_t * style, lv_state_t state, lv_blend_mode_t value) { _lv_style_set_int(style, LV_STYLE_IMAGE_BLEND_MODE | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_image_recolor(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_IMAGE_RECOLOR); } static inline void lv_obj_set_style_local_image_recolor(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_IMAGE_RECOLOR | (state << 8), value); } static inline void lv_style_set_image_recolor(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_IMAGE_RECOLOR | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_image_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_IMAGE_OPA); } static inline void lv_obj_set_style_local_image_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_IMAGE_OPA | (state << 8), value); } static inline void lv_style_set_image_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_IMAGE_OPA | (state << 8), value); }
static inline lv_opa_t lv_obj_get_style_image_recolor_opa(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_opa(obj, part, LV_STYLE_IMAGE_RECOLOR_OPA); } static inline void lv_obj_set_style_local_image_recolor_opa(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_opa_t value) { _lv_obj_set_style_local_opa(obj, part, LV_STYLE_IMAGE_RECOLOR_OPA | (state << 8), value); } static inline void lv_style_set_image_recolor_opa(lv_style_t * style, lv_state_t state, lv_opa_t value) { _lv_style_set_opa(style, LV_STYLE_IMAGE_RECOLOR_OPA | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_time(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_TIME); } static inline void lv_obj_set_style_local_transition_time(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_TIME | (state << 8), value); } static inline void lv_style_set_transition_time(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_TIME | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_delay(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_DELAY); } static inline void lv_obj_set_style_local_transition_delay(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_DELAY | (state << 8), value); } static inline void lv_style_set_transition_delay(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_DELAY | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_prop_1(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_PROP_1); } static inline void lv_obj_set_style_local_transition_prop_1(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_PROP_1 | (state << 8), value); } static inline void lv_style_set_transition_prop_1(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_PROP_1 | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_prop_2(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_PROP_2); } static inline void lv_obj_set_style_local_transition_prop_2(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_PROP_2 | (state << 8), value); } static inline void lv_style_set_transition_prop_2(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_PROP_2 | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_prop_3(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_PROP_3); } static inline void lv_obj_set_style_local_transition_prop_3(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_PROP_3 | (state << 8), value); } static inline void lv_style_set_transition_prop_3(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_PROP_3 | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_prop_4(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_PROP_4); } static inline void lv_obj_set_style_local_transition_prop_4(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_PROP_4 | (state << 8), value); } static inline void lv_style_set_transition_prop_4(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_PROP_4 | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_prop_5(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_PROP_5); } static inline void lv_obj_set_style_local_transition_prop_5(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_PROP_5 | (state << 8), value); } static inline void lv_style_set_transition_prop_5(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_PROP_5 | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_transition_prop_6(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_TRANSITION_PROP_6); } static inline void lv_obj_set_style_local_transition_prop_6(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_TRANSITION_PROP_6 | (state << 8), value); } static inline void lv_style_set_transition_prop_6(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_TRANSITION_PROP_6 | (state << 8), value); }

static inline const lv_anim_path_t * lv_obj_get_style_transition_path(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_ptr(obj, part, LV_STYLE_TRANSITION_PATH); } static inline void lv_obj_set_style_local_transition_path(lv_obj_t * obj, uint8_t part, lv_state_t state, const lv_anim_path_t * value) { _lv_obj_set_style_local_ptr(obj, part, LV_STYLE_TRANSITION_PATH | (state << 8), value); } static inline void lv_style_set_transition_path(lv_style_t * style, lv_state_t state, const lv_anim_path_t * value) { _lv_style_set_ptr(style, LV_STYLE_TRANSITION_PATH | (state << 8), value); }




static inline lv_style_int_t lv_obj_get_style_scale_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SCALE_WIDTH); } static inline void lv_obj_set_style_local_scale_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SCALE_WIDTH | (state << 8), value); } static inline void lv_style_set_scale_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SCALE_WIDTH | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_scale_border_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SCALE_BORDER_WIDTH); } static inline void lv_obj_set_style_local_scale_border_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SCALE_BORDER_WIDTH | (state << 8), value); } static inline void lv_style_set_scale_border_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SCALE_BORDER_WIDTH | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_scale_end_border_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SCALE_END_BORDER_WIDTH); } static inline void lv_obj_set_style_local_scale_end_border_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SCALE_END_BORDER_WIDTH | (state << 8), value); } static inline void lv_style_set_scale_end_border_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SCALE_END_BORDER_WIDTH | (state << 8), value); }
static inline lv_style_int_t lv_obj_get_style_scale_end_line_width(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_int(obj, part, LV_STYLE_SCALE_END_LINE_WIDTH); } static inline void lv_obj_set_style_local_scale_end_line_width(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value) { _lv_obj_set_style_local_int(obj, part, LV_STYLE_SCALE_END_LINE_WIDTH | (state << 8), value); } static inline void lv_style_set_scale_end_line_width(lv_style_t * style, lv_state_t state, lv_style_int_t value) { _lv_style_set_int(style, LV_STYLE_SCALE_END_LINE_WIDTH | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_scale_grad_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_SCALE_GRAD_COLOR); } static inline void lv_obj_set_style_local_scale_grad_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_SCALE_GRAD_COLOR | (state << 8), value); } static inline void lv_style_set_scale_grad_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_SCALE_GRAD_COLOR | (state << 8), value); }
static inline lv_color_t lv_obj_get_style_scale_end_color(const lv_obj_t * obj, uint8_t part) { return _lv_obj_get_style_color(obj, part, LV_STYLE_SCALE_END_COLOR); } static inline void lv_obj_set_style_local_scale_end_color(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_color_t value) { _lv_obj_set_style_local_color(obj, part, LV_STYLE_SCALE_END_COLOR | (state << 8), value); } static inline void lv_style_set_scale_end_color(lv_style_t * style, lv_state_t state, lv_color_t value) { _lv_style_set_color(style, LV_STYLE_SCALE_END_COLOR | (state << 8), value); }






static inline void lv_obj_set_style_local_pad_all(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value)
{
    lv_obj_set_style_local_pad_top(obj, part, state, value);
    lv_obj_set_style_local_pad_bottom(obj, part, state, value);
    lv_obj_set_style_local_pad_left(obj, part, state, value);
    lv_obj_set_style_local_pad_right(obj, part, state, value);
}

static inline void lv_style_set_pad_all(lv_style_t * style, lv_state_t state, lv_style_int_t value)
{
    lv_style_set_pad_top(style, state, value);
    lv_style_set_pad_bottom(style, state, value);
    lv_style_set_pad_left(style, state, value);
    lv_style_set_pad_right(style, state, value);
}

static inline void lv_obj_set_style_local_pad_hor(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value)
{
    lv_obj_set_style_local_pad_left(obj, part, state, value);
    lv_obj_set_style_local_pad_right(obj, part, state, value);
}

static inline void lv_style_set_pad_hor(lv_style_t * style, lv_state_t state, lv_style_int_t value)
{
    lv_style_set_pad_left(style, state, value);
    lv_style_set_pad_right(style, state, value);
}

static inline void lv_obj_set_style_local_pad_ver(lv_obj_t * obj, uint8_t part, lv_state_t state, lv_style_int_t value)
{
    lv_obj_set_style_local_pad_top(obj, part, state, value);
    lv_obj_set_style_local_pad_bottom(obj, part, state, value);
}

static inline void lv_style_set_pad_ver(lv_style_t * style, lv_state_t state, lv_style_int_t value)
{
    lv_style_set_pad_top(style, state, value);
    lv_style_set_pad_bottom(style, state, value);
}

static inline void lv_obj_set_style_local_margin_all(lv_obj_t * obj, uint8_t part, lv_state_t state,
                                                     lv_style_int_t value)
{
    lv_obj_set_style_local_margin_top(obj, part, state, value);
    lv_obj_set_style_local_margin_bottom(obj, part, state, value);
    lv_obj_set_style_local_margin_left(obj, part, state, value);
    lv_obj_set_style_local_margin_right(obj, part, state, value);
}

static inline void lv_style_set_margin_all(lv_style_t * style, lv_state_t state, lv_style_int_t value)
{
    lv_style_set_margin_top(style, state, value);
    lv_style_set_margin_bottom(style, state, value);
    lv_style_set_margin_left(style, state, value);
    lv_style_set_margin_right(style, state, value);
}

static inline void lv_obj_set_style_local_margin_hor(lv_obj_t * obj, uint8_t part, lv_state_t state,
                                                     lv_style_int_t value)
{
    lv_obj_set_style_local_margin_left(obj, part, state, value);
    lv_obj_set_style_local_margin_right(obj, part, state, value);
}

static inline void lv_style_set_margin_hor(lv_style_t * style, lv_state_t state, lv_style_int_t value)
{
    lv_style_set_margin_left(style, state, value);
    lv_style_set_margin_right(style, state, value);
}

static inline void lv_obj_set_style_local_margin_ver(lv_obj_t * obj, uint8_t part, lv_state_t state,
                                                     lv_style_int_t value)
{
    lv_obj_set_style_local_margin_top(obj, part, state, value);
    lv_obj_set_style_local_margin_bottom(obj, part, state, value);
}

static inline void lv_style_set_margin_ver(lv_style_t * style, lv_state_t state, lv_style_int_t value)
{
    lv_style_set_margin_top(style, state, value);
    lv_style_set_margin_bottom(style, state, value);
}
# 1209 "./src/lv_core/lv_obj.h" 2
# 1219 "./src/lv_core/lv_obj.h"
bool lv_obj_get_hidden(const lv_obj_t * obj);






bool lv_obj_get_adv_hittest(const lv_obj_t * obj);






bool lv_obj_get_click(const lv_obj_t * obj);






bool lv_obj_get_top(const lv_obj_t * obj);






bool lv_obj_get_drag(const lv_obj_t * obj);






lv_drag_dir_t lv_obj_get_drag_dir(const lv_obj_t * obj);






bool lv_obj_get_drag_throw(const lv_obj_t * obj);






bool lv_obj_get_drag_parent(const lv_obj_t * obj);






bool lv_obj_get_focus_parent(const lv_obj_t * obj);






bool lv_obj_get_parent_event(const lv_obj_t * obj);






bool lv_obj_get_gesture_parent(const lv_obj_t * obj);

lv_bidi_dir_t lv_obj_get_base_dir(const lv_obj_t * obj);






uint8_t lv_obj_get_protect(const lv_obj_t * obj);







bool lv_obj_is_protected(const lv_obj_t * obj, uint8_t prot);

lv_state_t lv_obj_get_state(const lv_obj_t * obj, uint8_t part);






lv_signal_cb_t lv_obj_get_signal_cb(const lv_obj_t * obj);






lv_design_cb_t lv_obj_get_design_cb(const lv_obj_t * obj);






lv_event_cb_t lv_obj_get_event_cb(const lv_obj_t * obj);
# 1343 "./src/lv_core/lv_obj.h"
bool lv_obj_is_point_on_coords(lv_obj_t * obj, const lv_point_t * point);







bool lv_obj_hittest(lv_obj_t * obj, lv_point_t * point);







void * lv_obj_get_ext_attr(const lv_obj_t * obj);







void lv_obj_get_type(const lv_obj_t * obj, lv_obj_type_t * buf);
# 1398 "./src/lv_core/lv_obj.h"
void * lv_obj_get_group(const lv_obj_t * obj);






bool lv_obj_is_focused(const lv_obj_t * obj);






lv_obj_t * lv_obj_get_focused_obj(const lv_obj_t * obj);
# 1424 "./src/lv_core/lv_obj.h"
lv_res_t lv_obj_handle_get_type_signal(lv_obj_type_t * buf, const char * name);
# 1434 "./src/lv_core/lv_obj.h"
void lv_obj_init_draw_rect_dsc(lv_obj_t * obj, uint8_t type, lv_draw_rect_dsc_t * draw_dsc);

void lv_obj_init_draw_label_dsc(lv_obj_t * obj, uint8_t type, lv_draw_label_dsc_t * draw_dsc);

void lv_obj_init_draw_img_dsc(lv_obj_t * obj, uint8_t part, lv_draw_img_dsc_t * draw_dsc);

void lv_obj_init_draw_line_dsc(lv_obj_t * obj, uint8_t part, lv_draw_line_dsc_t * draw_dsc);






lv_coord_t lv_obj_get_draw_rect_ext_pad_size(lv_obj_t * obj, uint8_t part);







void lv_obj_fade_in(lv_obj_t * obj, uint32_t time, uint32_t delay);







void lv_obj_fade_out(lv_obj_t * obj, uint32_t time, uint32_t delay);







bool lv_debug_check_obj_type(const lv_obj_t * obj, const char * obj_type);







bool lv_debug_check_obj_valid(const lv_obj_t * obj);
# 33 "lvgl.h" 2
# 1 "./src/lv_core/lv_group.h" 1
# 25 "./src/lv_core/lv_group.h"
enum {
    LV_KEY_UP = 17,
    LV_KEY_DOWN = 18,
    LV_KEY_RIGHT = 19,
    LV_KEY_LEFT = 20,
    LV_KEY_ESC = 27,
    LV_KEY_DEL = 127,
    LV_KEY_BACKSPACE = 8,
    LV_KEY_ENTER = 10,
    LV_KEY_NEXT = 9,
    LV_KEY_PREV = 11,
    LV_KEY_HOME = 2,
    LV_KEY_END = 3,
};
typedef uint8_t lv_key_t;





struct _lv_group_t;

typedef void (*lv_group_style_mod_cb_t)(struct _lv_group_t *, lv_style_t *);
typedef void (*lv_group_focus_cb_t)(struct _lv_group_t *);





typedef struct _lv_group_t {
    lv_ll_t obj_ll;
    lv_obj_t ** obj_focus;

    lv_group_focus_cb_t focus_cb;




    uint8_t frozen : 1;
    uint8_t editing : 1;
    uint8_t click_focus : 1;

    uint8_t refocus_policy : 1;

    uint8_t wrap : 1;

} lv_group_t;

enum { LV_GROUP_REFOCUS_POLICY_NEXT = 0, LV_GROUP_REFOCUS_POLICY_PREV = 1 };
typedef uint8_t lv_group_refocus_policy_t;
# 84 "./src/lv_core/lv_group.h"
void _lv_group_init(void);





lv_group_t * lv_group_create(void);





void lv_group_del(lv_group_t * group);






void lv_group_add_obj(lv_group_t * group, lv_obj_t * obj);





void lv_group_remove_obj(lv_obj_t * obj);





void lv_group_remove_all_objs(lv_group_t * group);





void lv_group_focus_obj(lv_obj_t * obj);





void lv_group_focus_next(lv_group_t * group);





void lv_group_focus_prev(lv_group_t * group);






void lv_group_focus_freeze(lv_group_t * group, bool en);







lv_res_t lv_group_send_data(lv_group_t * group, uint32_t c);






void lv_group_set_focus_cb(lv_group_t * group, lv_group_focus_cb_t focus_cb);







void lv_group_set_refocus_policy(lv_group_t * group, lv_group_refocus_policy_t policy);






void lv_group_set_editing(lv_group_t * group, bool edit);






void lv_group_set_click_focus(lv_group_t * group, bool en);






void lv_group_set_wrap(lv_group_t * group, bool en);






lv_obj_t * lv_group_get_focused(const lv_group_t * group);
# 208 "./src/lv_core/lv_group.h"
lv_group_focus_cb_t lv_group_get_focus_cb(const lv_group_t * group);






bool lv_group_get_editing(const lv_group_t * group);






bool lv_group_get_click_focus(const lv_group_t * group);






bool lv_group_get_wrap(lv_group_t * group);
# 34 "lvgl.h" 2
# 1 "./src/lv_core/lv_indev.h" 1
# 35 "./src/lv_core/lv_indev.h"
void _lv_indev_init(void);





void _lv_indev_read_task(lv_task_t * task);






lv_indev_t * lv_indev_get_act(void);






lv_indev_type_t lv_indev_get_type(const lv_indev_t * indev);






void lv_indev_reset(lv_indev_t * indev, lv_obj_t * obj);





void lv_indev_reset_long_press(lv_indev_t * indev);






void lv_indev_enable(lv_indev_t * indev, bool en);






void lv_indev_set_cursor(lv_indev_t * indev, lv_obj_t * cur_obj);







void lv_indev_set_group(lv_indev_t * indev, lv_group_t * group);
# 99 "./src/lv_core/lv_indev.h"
void lv_indev_set_button_points(lv_indev_t * indev, const lv_point_t points[]);






void lv_indev_get_point(const lv_indev_t * indev, lv_point_t * point);






lv_gesture_dir_t lv_indev_get_gesture_dir(const lv_indev_t * indev);






uint32_t lv_indev_get_key(const lv_indev_t * indev);







bool lv_indev_is_dragging(const lv_indev_t * indev);







void lv_indev_get_vect(const lv_indev_t * indev, lv_point_t * point);







lv_res_t lv_indev_finish_drag(lv_indev_t * indev);





void lv_indev_wait_release(lv_indev_t * indev);






lv_obj_t * lv_indev_get_obj_act(void);







lv_obj_t * lv_indev_search_obj(lv_obj_t * obj, lv_point_t * point);







lv_task_t * lv_indev_get_read_task(lv_disp_t * indev);
# 35 "lvgl.h" 2

# 1 "./src/lv_core/lv_refr.h" 1
# 17 "./src/lv_core/lv_refr.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 18 "./src/lv_core/lv_refr.h" 2
# 48 "./src/lv_core/lv_refr.h"
void _lv_refr_init(void);
# 57 "./src/lv_core/lv_refr.h"
void lv_refr_now(lv_disp_t * disp);







void _lv_inv_area(lv_disp_t * disp, const lv_area_t * area_p);





lv_disp_t * _lv_refr_get_disp_refreshing(void);







void _lv_refr_set_disp_refreshing(lv_disp_t * disp);
# 93 "./src/lv_core/lv_refr.h"
void _lv_disp_refr_task(lv_task_t * task);
# 37 "lvgl.h" 2
# 1 "./src/lv_core/lv_disp.h" 1
# 27 "./src/lv_core/lv_disp.h"
typedef enum {
    LV_SCR_LOAD_ANIM_NONE,
    LV_SCR_LOAD_ANIM_OVER_LEFT,
    LV_SCR_LOAD_ANIM_OVER_RIGHT,
    LV_SCR_LOAD_ANIM_OVER_TOP,
    LV_SCR_LOAD_ANIM_OVER_BOTTOM,
    LV_SCR_LOAD_ANIM_MOVE_LEFT,
    LV_SCR_LOAD_ANIM_MOVE_RIGHT,
    LV_SCR_LOAD_ANIM_MOVE_TOP,
    LV_SCR_LOAD_ANIM_MOVE_BOTTOM,
    LV_SCR_LOAD_ANIM_FADE_ON,
} lv_scr_load_anim_t;
# 50 "./src/lv_core/lv_disp.h"
lv_obj_t * lv_disp_get_scr_act(lv_disp_t * disp);







lv_obj_t * lv_disp_get_scr_prev(lv_disp_t * disp);





void lv_disp_load_scr(lv_obj_t * scr);






lv_obj_t * lv_disp_get_layer_top(lv_disp_t * disp);







lv_obj_t * lv_disp_get_layer_sys(lv_disp_t * disp);






void lv_disp_assign_screen(lv_disp_t * disp, lv_obj_t * scr);






void lv_disp_set_bg_color(lv_disp_t * disp, lv_color_t color);






void lv_disp_set_bg_image(lv_disp_t * disp, const void * img_src);






void lv_disp_set_bg_opa(lv_disp_t * disp, lv_opa_t opa);
# 119 "./src/lv_core/lv_disp.h"
void lv_scr_load_anim(lv_obj_t * scr, lv_scr_load_anim_t anim_type, uint32_t time, uint32_t delay, bool auto_del);







uint32_t lv_disp_get_inactive_time(const lv_disp_t * disp);





void lv_disp_trig_activity(lv_disp_t * disp);





void lv_disp_clean_dcache(lv_disp_t * disp);







lv_task_t * _lv_disp_get_refr_task(lv_disp_t * disp);
# 158 "./src/lv_core/lv_disp.h"
static inline lv_obj_t * lv_scr_act(void)
{
    return lv_disp_get_scr_act(lv_disp_get_default());
}





static inline lv_obj_t * lv_layer_top(void)
{
    return lv_disp_get_layer_top(lv_disp_get_default());
}





static inline lv_obj_t * lv_layer_sys(void)
{
    return lv_disp_get_layer_sys(lv_disp_get_default());
}

static inline void lv_scr_load(lv_obj_t * scr)
{
    lv_disp_load_scr(scr);
}
# 217 "./src/lv_core/lv_disp.h"
static inline lv_coord_t lv_dpx(lv_coord_t n)
{
    return (n == 0 ? 0 :(((( lv_disp_get_dpi(0) * (n) + 80) / 160)) > (1) ? ((( lv_disp_get_dpi(0) * (n) + 80) / 160)) : (1)));
}
# 38 "lvgl.h" 2

# 1 "./src/lv_themes/lv_theme.h" 1
# 34 "./src/lv_themes/lv_theme.h"
typedef enum {
    LV_THEME_NONE = 0,
    LV_THEME_SCR,
    LV_THEME_OBJ,

    LV_THEME_ARC,


    LV_THEME_BAR,


    LV_THEME_BTN,


    LV_THEME_BTNMATRIX,


    LV_THEME_CALENDAR,


    LV_THEME_CANVAS,


    LV_THEME_CHECKBOX,


    LV_THEME_CHART,


    LV_THEME_CONT,


    LV_THEME_CPICKER,


    LV_THEME_DROPDOWN,


    LV_THEME_GAUGE,


    LV_THEME_IMAGE,


    LV_THEME_IMGBTN,


    LV_THEME_KEYBOARD,


    LV_THEME_LABEL,


    LV_THEME_LED,


    LV_THEME_LINE,


    LV_THEME_LIST,
    LV_THEME_LIST_BTN,


    LV_THEME_LINEMETER,


    LV_THEME_MSGBOX,
    LV_THEME_MSGBOX_BTNS,


    LV_THEME_OBJMASK,


    LV_THEME_PAGE,


    LV_THEME_ROLLER,


    LV_THEME_SLIDER,


    LV_THEME_SPINBOX,
    LV_THEME_SPINBOX_BTN,


    LV_THEME_SPINNER,


    LV_THEME_SWITCH,


    LV_THEME_TABLE,


    LV_THEME_TABVIEW,
    LV_THEME_TABVIEW_PAGE,


    LV_THEME_TEXTAREA,


    LV_THEME_TILEVIEW,


    LV_THEME_WIN,
    LV_THEME_WIN_BTN,


    _LV_THEME_BUILTIN_LAST,
    LV_THEME_CUSTOM_START = _LV_THEME_BUILTIN_LAST,
    _LV_THEME_CUSTOM_LAST = 0xFFFF,

} lv_theme_style_t;

struct _lv_theme_t;

typedef void (*lv_theme_apply_cb_t)(struct _lv_theme_t *, lv_obj_t *, lv_theme_style_t);
typedef void (*lv_theme_apply_xcb_t)(lv_obj_t *, lv_theme_style_t);

typedef struct _lv_theme_t {
    lv_theme_apply_cb_t apply_cb;
    lv_theme_apply_xcb_t apply_xcb;
    struct _lv_theme_t * base;
    lv_color_t color_primary;
    lv_color_t color_secondary;
    const lv_font_t * font_small;
    const lv_font_t * font_normal;
    const lv_font_t * font_subtitle;
    const lv_font_t * font_title;
    uint32_t flags;
    void * user_data;
} lv_theme_t;
# 177 "./src/lv_themes/lv_theme.h"
void lv_theme_set_act(lv_theme_t * th);





lv_theme_t * lv_theme_get_act(void);






void lv_theme_apply(lv_obj_t * obj, lv_theme_style_t name);







void lv_theme_copy(lv_theme_t * theme, const lv_theme_t * copy);
# 207 "./src/lv_themes/lv_theme.h"
void lv_theme_set_base(lv_theme_t * new_theme, lv_theme_t * base);







void lv_theme_set_apply_cb(lv_theme_t * theme, lv_theme_apply_cb_t apply_cb);





const lv_font_t * lv_theme_get_font_small(void);





const lv_font_t * lv_theme_get_font_normal(void);





const lv_font_t * lv_theme_get_font_subtitle(void);





const lv_font_t * lv_theme_get_font_title(void);





lv_color_t lv_theme_get_color_primary(void);





lv_color_t lv_theme_get_color_secondary(void);





uint32_t lv_theme_get_flags(void);
# 266 "./src/lv_themes/lv_theme.h"
# 1 "./src/lv_themes/lv_theme_empty.h" 1
# 43 "./src/lv_themes/lv_theme_empty.h"
lv_theme_t * lv_theme_empty_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags,
                                 const lv_font_t * font_small, const lv_font_t * font_normal, const lv_font_t * font_subtitle,
                                 const lv_font_t * font_title);
# 267 "./src/lv_themes/lv_theme.h" 2
# 1 "./src/lv_themes/lv_theme_template.h" 1
# 43 "./src/lv_themes/lv_theme_template.h"
lv_theme_t * lv_theme_template_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags,
                                    const lv_font_t * font_small, const lv_font_t * font_normal, const lv_font_t * font_subtitle,
                                    const lv_font_t * font_title);
# 268 "./src/lv_themes/lv_theme.h" 2
# 1 "./src/lv_themes/lv_theme_material.h" 1
# 23 "./src/lv_themes/lv_theme_material.h"
typedef enum {
    LV_THEME_MATERIAL_FLAG_DARK = 0x01,
    LV_THEME_MATERIAL_FLAG_LIGHT = 0x02,
    LV_THEME_MATERIAL_FLAG_NO_TRANSITION = 0x10,
    LV_THEME_MATERIAL_FLAG_NO_FOCUS = 0x20,
} lv_theme_material_flag_t;
# 49 "./src/lv_themes/lv_theme_material.h"
lv_theme_t * lv_theme_material_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags,
                                    const lv_font_t * font_small, const lv_font_t * font_normal, const lv_font_t * font_subtitle,
                                    const lv_font_t * font_title);
# 269 "./src/lv_themes/lv_theme.h" 2
# 1 "./src/lv_themes/lv_theme_mono.h" 1
# 43 "./src/lv_themes/lv_theme_mono.h"
lv_theme_t * lv_theme_mono_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags,
                                const lv_font_t * font_small, const lv_font_t * font_normal, const lv_font_t * font_subtitle,
                                const lv_font_t * font_title);
# 270 "./src/lv_themes/lv_theme.h" 2
# 40 "lvgl.h" 2


# 1 "./src/lv_font/lv_font_loader.h" 1
# 31 "./src/lv_font/lv_font_loader.h"
lv_font_t * lv_font_load(const char * fontName);
void lv_font_free(lv_font_t * font);
# 43 "lvgl.h" 2
# 1 "./src/lv_font/lv_font_fmt_txt.h" 1
# 16 "./src/lv_font/lv_font_fmt_txt.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdint.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdint.h" 2
# 17 "./src/lv_font/lv_font_fmt_txt.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stddef.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stddef.h" 2
# 18 "./src/lv_font/lv_font_fmt_txt.h" 2
# 1 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdbool.h" 2
# 19 "./src/lv_font/lv_font_fmt_txt.h" 2
# 30 "./src/lv_font/lv_font_fmt_txt.h"
typedef struct {

    uint32_t bitmap_index : 20;
    uint32_t adv_w : 12;
    uint8_t box_w;
    uint8_t box_h;
    int8_t ofs_x;
    int8_t ofs_y;
# 46 "./src/lv_font/lv_font_fmt_txt.h"
} lv_font_fmt_txt_glyph_dsc_t;


enum {
    LV_FONT_FMT_TXT_CMAP_FORMAT0_FULL,
    LV_FONT_FMT_TXT_CMAP_SPARSE_FULL,
    LV_FONT_FMT_TXT_CMAP_FORMAT0_TINY,
    LV_FONT_FMT_TXT_CMAP_SPARSE_TINY,
};

typedef uint8_t lv_font_fmt_txt_cmap_type_t;





typedef struct {

    uint32_t range_start;



    uint16_t range_length;


    uint16_t glyph_id_start;
# 100 "./src/lv_font/lv_font_fmt_txt.h"
    const uint16_t * unicode_list;




    const void * glyph_id_ofs_list;


    uint16_t list_length;


    lv_font_fmt_txt_cmap_type_t type;
} lv_font_fmt_txt_cmap_t;


typedef struct {







    const void * glyph_ids;
    const int8_t * values;
    uint32_t pair_cnt : 30;
    uint32_t glyph_ids_size : 2;
} lv_font_fmt_txt_kern_pair_t;


typedef struct {
# 139 "./src/lv_font/lv_font_fmt_txt.h"
    const int8_t * class_pair_values;
    const uint8_t * left_class_mapping;
    const uint8_t * right_class_mapping;
    uint8_t left_class_cnt;
    uint8_t right_class_cnt;
} lv_font_fmt_txt_kern_classes_t;


typedef enum {
    LV_FONT_FMT_TXT_PLAIN = 0,
    LV_FONT_FMT_TXT_COMPRESSED = 1,
    LV_FONT_FMT_TXT_COMPRESSED_NO_PREFILTER = 1,
} lv_font_fmt_txt_bitmap_format_t;


typedef struct {

    const uint8_t * glyph_bitmap;


    const lv_font_fmt_txt_glyph_dsc_t * glyph_dsc;



    const lv_font_fmt_txt_cmap_t * cmaps;





    const void * kern_dsc;


    uint16_t kern_scale;


    uint16_t cmap_num : 9;


    uint16_t bpp : 4;


    uint16_t kern_classes : 1;





    uint16_t bitmap_format : 2;


    uint32_t last_letter;
    uint32_t last_glyph_id;

} lv_font_fmt_txt_dsc_t;
# 205 "./src/lv_font/lv_font_fmt_txt.h"
const uint8_t * lv_font_get_bitmap_fmt_txt(const lv_font_t * font, uint32_t letter);
# 215 "./src/lv_font/lv_font_fmt_txt.h"
bool lv_font_get_glyph_dsc_fmt_txt(const lv_font_t * font, lv_font_glyph_dsc_t * dsc_out, uint32_t unicode_letter,
                                   uint32_t unicode_letter_next);




void _lv_font_clean_up_fmt_txt(void);
# 44 "lvgl.h" 2


# 1 "./src/lv_widgets/lv_btn.h" 1
# 25 "./src/lv_widgets/lv_btn.h"
# 1 "./src/lv_widgets/lv_cont.h" 1
# 31 "./src/lv_widgets/lv_cont.h"
enum {
    LV_LAYOUT_OFF = 0,
    LV_LAYOUT_CENTER,







    LV_LAYOUT_COLUMN_LEFT,
    LV_LAYOUT_COLUMN_MID,
    LV_LAYOUT_COLUMN_RIGHT,
# 53 "./src/lv_widgets/lv_cont.h"
    LV_LAYOUT_ROW_TOP,
    LV_LAYOUT_ROW_MID,
    LV_LAYOUT_ROW_BOTTOM,
# 66 "./src/lv_widgets/lv_cont.h"
    LV_LAYOUT_PRETTY_TOP,
    LV_LAYOUT_PRETTY_MID,
    LV_LAYOUT_PRETTY_BOTTOM,
# 80 "./src/lv_widgets/lv_cont.h"
    LV_LAYOUT_GRID,

    _LV_LAYOUT_LAST
};
typedef uint8_t lv_layout_t;




enum {
    LV_FIT_NONE,
    LV_FIT_TIGHT,
    LV_FIT_PARENT,
    LV_FIT_MAX,

    _LV_FIT_LAST
};
typedef uint8_t lv_fit_t;

typedef struct {


    lv_layout_t layout : 4;
    lv_fit_t fit_left : 2;
    lv_fit_t fit_right : 2;
    lv_fit_t fit_top : 2;
    lv_fit_t fit_bottom : 2;
} lv_cont_ext_t;


enum {
    LV_CONT_PART_MAIN = LV_OBJ_PART_MAIN,
    _LV_CONT_PART_VIRTUAL_LAST = _LV_OBJ_PART_VIRTUAL_LAST,
    _LV_CONT_PART_REAL_LAST = _LV_OBJ_PART_REAL_LAST,
};
# 126 "./src/lv_widgets/lv_cont.h"
lv_obj_t * lv_cont_create(lv_obj_t * par, const lv_obj_t * copy);
# 137 "./src/lv_widgets/lv_cont.h"
void lv_cont_set_layout(lv_obj_t * cont, lv_layout_t layout);
# 148 "./src/lv_widgets/lv_cont.h"
void lv_cont_set_fit4(lv_obj_t * cont, lv_fit_t left, lv_fit_t right, lv_fit_t top, lv_fit_t bottom);
# 157 "./src/lv_widgets/lv_cont.h"
static inline void lv_cont_set_fit2(lv_obj_t * cont, lv_fit_t hor, lv_fit_t ver)
{
    lv_cont_set_fit4(cont, hor, hor, ver, ver);
}







static inline void lv_cont_set_fit(lv_obj_t * cont, lv_fit_t fit)
{
    lv_cont_set_fit4(cont, fit, fit, fit, fit);
}
# 182 "./src/lv_widgets/lv_cont.h"
lv_layout_t lv_cont_get_layout(const lv_obj_t * cont);






lv_fit_t lv_cont_get_fit_left(const lv_obj_t * cont);






lv_fit_t lv_cont_get_fit_right(const lv_obj_t * cont);






lv_fit_t lv_cont_get_fit_top(const lv_obj_t * cont);






lv_fit_t lv_cont_get_fit_bottom(const lv_obj_t * cont);
# 26 "./src/lv_widgets/lv_btn.h" 2
# 38 "./src/lv_widgets/lv_btn.h"
enum {
    LV_BTN_STATE_RELEASED,
    LV_BTN_STATE_PRESSED,
    LV_BTN_STATE_DISABLED,
    LV_BTN_STATE_CHECKED_RELEASED,
    LV_BTN_STATE_CHECKED_PRESSED,
    LV_BTN_STATE_CHECKED_DISABLED,
    _LV_BTN_STATE_LAST,
};
typedef uint8_t lv_btn_state_t;


typedef struct {

    lv_cont_ext_t cont;


    uint8_t checkable : 1;
} lv_btn_ext_t;


enum {
    LV_BTN_PART_MAIN = LV_OBJ_PART_MAIN,
    _LV_BTN_PART_VIRTUAL_LAST,
    _LV_BTN_PART_REAL_LAST = _LV_OBJ_PART_REAL_LAST,
};
typedef uint8_t lv_btn_part_t;
# 76 "./src/lv_widgets/lv_btn.h"
lv_obj_t * lv_btn_create(lv_obj_t * par, const lv_obj_t * copy);
# 87 "./src/lv_widgets/lv_btn.h"
void lv_btn_set_checkable(lv_obj_t * btn, bool tgl);






void lv_btn_set_state(lv_obj_t * btn, lv_btn_state_t state);





void lv_btn_toggle(lv_obj_t * btn);






static inline void lv_btn_set_layout(lv_obj_t * btn, lv_layout_t layout)
{
    lv_cont_set_layout(btn, layout);
}
# 121 "./src/lv_widgets/lv_btn.h"
static inline void lv_btn_set_fit4(lv_obj_t * btn, lv_fit_t left, lv_fit_t right, lv_fit_t top, lv_fit_t bottom)
{
    lv_cont_set_fit4(btn, left, right, top, bottom);
}
# 133 "./src/lv_widgets/lv_btn.h"
static inline void lv_btn_set_fit2(lv_obj_t * btn, lv_fit_t hor, lv_fit_t ver)
{
    lv_cont_set_fit2(btn, hor, ver);
}







static inline void lv_btn_set_fit(lv_obj_t * btn, lv_fit_t fit)
{
    lv_cont_set_fit(btn, fit);
}
# 159 "./src/lv_widgets/lv_btn.h"
lv_btn_state_t lv_btn_get_state(const lv_obj_t * btn);






bool lv_btn_get_checkable(const lv_obj_t * btn);






static inline lv_layout_t lv_btn_get_layout(const lv_obj_t * btn)
{
    return lv_cont_get_layout(btn);
}






static inline lv_fit_t lv_btn_get_fit_left(const lv_obj_t * btn)
{
    return lv_cont_get_fit_left(btn);
}






static inline lv_fit_t lv_btn_get_fit_right(const lv_obj_t * btn)
{
    return lv_cont_get_fit_right(btn);
}






static inline lv_fit_t lv_btn_get_fit_top(const lv_obj_t * btn)
{
    return lv_cont_get_fit_top(btn);
}






static inline lv_fit_t lv_btn_get_fit_bottom(const lv_obj_t * btn)
{
    return lv_cont_get_fit_bottom(btn);
}
# 47 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_imgbtn.h" 1
# 37 "./src/lv_widgets/lv_imgbtn.h"
typedef struct {
    lv_btn_ext_t btn;

    const void * img_src_mid[_LV_BTN_STATE_LAST];




    lv_img_cf_t act_cf;
    uint8_t tiled : 1;
} lv_imgbtn_ext_t;


enum {
    LV_IMGBTN_PART_MAIN = LV_BTN_PART_MAIN,
};
typedef uint8_t lv_imgbtn_part_t;
# 66 "./src/lv_widgets/lv_imgbtn.h"
lv_obj_t * lv_imgbtn_create(lv_obj_t * par, const lv_obj_t * copy);
# 82 "./src/lv_widgets/lv_imgbtn.h"
void lv_imgbtn_set_src(lv_obj_t * imgbtn, lv_btn_state_t state, const void * src);
# 106 "./src/lv_widgets/lv_imgbtn.h"
void lv_imgbtn_set_state(lv_obj_t * imgbtn, lv_btn_state_t state);





void lv_imgbtn_toggle(lv_obj_t * imgbtn);






static inline void lv_imgbtn_set_checkable(lv_obj_t * imgbtn, bool tgl)
{
    lv_btn_set_checkable(imgbtn, tgl);
}
# 135 "./src/lv_widgets/lv_imgbtn.h"
const void * lv_imgbtn_get_src(lv_obj_t * imgbtn, lv_btn_state_t state);
# 169 "./src/lv_widgets/lv_imgbtn.h"
static inline lv_btn_state_t lv_imgbtn_get_state(const lv_obj_t * imgbtn)
{
    return lv_btn_get_state(imgbtn);
}






static inline bool lv_imgbtn_get_checkable(const lv_obj_t * imgbtn)
{
    return lv_btn_get_checkable(imgbtn);
}
# 48 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_img.h" 1
# 22 "./src/lv_widgets/lv_img.h"
# 1 "./src/lv_widgets/lv_label.h" 1
# 20 "./src/lv_widgets/lv_label.h"
# 1 "../../../pycparser/utils/fake_libc_include\\stdarg.h" 1
# 1 "../../../pycparser/utils/fake_libc_include/_fake_defines.h" 1
# 2 "../../../pycparser/utils/fake_libc_include\\stdarg.h" 2
# 21 "./src/lv_widgets/lv_label.h" 2




# 1 "./src/lv_widgets/../lv_draw/lv_draw.h" 1
# 26 "./src/lv_widgets/../lv_draw/lv_draw.h"
# 1 "./src/lv_core/../lv_draw/lv_draw_triangle.h" 1
# 36 "./src/lv_core/../lv_draw/lv_draw_triangle.h"
void lv_draw_triangle(const lv_point_t points[], const lv_area_t * clip, const lv_draw_rect_dsc_t * draw_dsc);
# 45 "./src/lv_core/../lv_draw/lv_draw_triangle.h"
void lv_draw_polygon(const lv_point_t points[], uint16_t point_cnt, const lv_area_t * mask,
                     const lv_draw_rect_dsc_t * draw_dsc);
# 27 "./src/lv_widgets/../lv_draw/lv_draw.h" 2
# 1 "./src/lv_core/../lv_draw/lv_draw_arc.h" 1
# 41 "./src/lv_core/../lv_draw/lv_draw_arc.h"
void lv_draw_arc(lv_coord_t center_x, lv_coord_t center_y, uint16_t radius, uint16_t start_angle, uint16_t end_angle,
                 const lv_area_t * clip_area, const lv_draw_line_dsc_t * dsc);
# 28 "./src/lv_widgets/../lv_draw/lv_draw.h" 2
# 26 "./src/lv_widgets/lv_label.h" 2








struct _silence_gcc_warning;
struct _silence_gcc_warning;
struct _silence_gcc_warning;






enum {
    LV_LABEL_LONG_EXPAND,
    LV_LABEL_LONG_BREAK,

    LV_LABEL_LONG_DOT,
    LV_LABEL_LONG_SROLL,
    LV_LABEL_LONG_SROLL_CIRC,
    LV_LABEL_LONG_CROP,
};
typedef uint8_t lv_label_long_mode_t;


enum {
    LV_LABEL_ALIGN_LEFT,
    LV_LABEL_ALIGN_CENTER,
    LV_LABEL_ALIGN_RIGHT,
    LV_LABEL_ALIGN_AUTO,
};
typedef uint8_t lv_label_align_t;


typedef struct {


    char * text;

    union {
        char * tmp_ptr;

        char tmp[3 + 1];
    } dot;

    uint32_t dot_end;


    uint16_t anim_speed;


    lv_point_t offset;
# 92 "./src/lv_widgets/lv_label.h"
    lv_label_long_mode_t long_mode : 3;
    uint8_t static_txt : 1;
    uint8_t align : 2;
    uint8_t recolor : 1;
    uint8_t expand : 1;
    uint8_t dot_tmp_alloc : 1;

} lv_label_ext_t;


enum {
    LV_LABEL_PART_MAIN,
};

typedef uint8_t lv_label_part_t;
# 118 "./src/lv_widgets/lv_label.h"
lv_obj_t * lv_label_create(lv_obj_t * par, const lv_obj_t * copy);
# 129 "./src/lv_widgets/lv_label.h"
void lv_label_set_text(lv_obj_t * label, const char * text);






void lv_label_set_text_fmt(lv_obj_t * label, const char * fmt, ...);







void lv_label_set_text_static(lv_obj_t * label, const char * text);
# 153 "./src/lv_widgets/lv_label.h"
void lv_label_set_long_mode(lv_obj_t * label, lv_label_long_mode_t long_mode);






void lv_label_set_align(lv_obj_t * label, lv_label_align_t align);






void lv_label_set_recolor(lv_obj_t * label, bool en);






void lv_label_set_anim_speed(lv_obj_t * label, uint16_t anim_speed);






void lv_label_set_text_sel_start(lv_obj_t * label, uint32_t index);






void lv_label_set_text_sel_end(lv_obj_t * label, uint32_t index);
# 198 "./src/lv_widgets/lv_label.h"
char * lv_label_get_text(const lv_obj_t * label);






lv_label_long_mode_t lv_label_get_long_mode(const lv_obj_t * label);






lv_label_align_t lv_label_get_align(const lv_obj_t * label);






bool lv_label_get_recolor(const lv_obj_t * label);






uint16_t lv_label_get_anim_speed(const lv_obj_t * label);
# 235 "./src/lv_widgets/lv_label.h"
void lv_label_get_letter_pos(const lv_obj_t * label, uint32_t index, lv_point_t * pos);
# 244 "./src/lv_widgets/lv_label.h"
uint32_t lv_label_get_letter_on(const lv_obj_t * label, lv_point_t * pos);







bool lv_label_is_char_under_pos(const lv_obj_t * label, lv_point_t * pos);






uint32_t lv_label_get_text_sel_start(const lv_obj_t * label);






uint32_t lv_label_get_text_sel_end(const lv_obj_t * label);

lv_style_list_t * lv_label_get_style(lv_obj_t * label, uint8_t type);
# 281 "./src/lv_widgets/lv_label.h"
void lv_label_ins_text(lv_obj_t * label, uint32_t pos, const char * txt);
# 290 "./src/lv_widgets/lv_label.h"
void lv_label_cut_text(lv_obj_t * label, uint32_t pos, uint32_t cnt);





void lv_label_refr_text(lv_obj_t * label);
# 23 "./src/lv_widgets/lv_img.h" 2
# 33 "./src/lv_widgets/lv_img.h"
typedef struct {


    const void * src;
    lv_point_t offset;
    lv_coord_t w;
    lv_coord_t h;
    uint16_t angle;
    lv_point_t pivot;
    uint16_t zoom;
    uint8_t src_type : 2;
    uint8_t auto_size : 1;
    uint8_t cf : 5;
    uint8_t antialias : 1;
} lv_img_ext_t;


enum {
    LV_IMG_PART_MAIN,
};
typedef uint8_t lv_img_part_t;
# 65 "./src/lv_widgets/lv_img.h"
lv_obj_t * lv_img_create(lv_obj_t * par, const lv_obj_t * copy);
# 76 "./src/lv_widgets/lv_img.h"
void lv_img_set_src(lv_obj_t * img, const void * src_img);







void lv_img_set_auto_size(lv_obj_t * img, bool autosize_en);







void lv_img_set_offset_x(lv_obj_t * img, lv_coord_t x);







void lv_img_set_offset_y(lv_obj_t * img, lv_coord_t y);
# 109 "./src/lv_widgets/lv_img.h"
void lv_img_set_pivot(lv_obj_t * img, lv_coord_t pivot_x, lv_coord_t pivot_y);







void lv_img_set_angle(lv_obj_t * img, int16_t angle);
# 129 "./src/lv_widgets/lv_img.h"
void lv_img_set_zoom(lv_obj_t * img, uint16_t zoom);






void lv_img_set_antialias(lv_obj_t * img, bool antialias);
# 147 "./src/lv_widgets/lv_img.h"
const void * lv_img_get_src(lv_obj_t * img);






const char * lv_img_get_file_name(const lv_obj_t * img);






bool lv_img_get_auto_size(const lv_obj_t * img);






lv_coord_t lv_img_get_offset_x(lv_obj_t * img);






lv_coord_t lv_img_get_offset_y(lv_obj_t * img);






uint16_t lv_img_get_angle(lv_obj_t * img);






void lv_img_get_pivot(lv_obj_t * img, lv_point_t * center);






uint16_t lv_img_get_zoom(lv_obj_t * img);






bool lv_img_get_antialias(lv_obj_t * img);
# 49 "lvgl.h" 2

# 1 "./src/lv_widgets/lv_line.h" 1
# 31 "./src/lv_widgets/lv_line.h"
typedef struct {

    const lv_point_t * point_array;
    uint16_t point_num;
    uint8_t auto_size : 1;
    uint8_t y_inv : 1;
} lv_line_ext_t;


enum {
    LV_LINE_PART_MAIN,
};
typedef uint8_t lv_line_style_t;
# 54 "./src/lv_widgets/lv_line.h"
lv_obj_t * lv_line_create(lv_obj_t * par, const lv_obj_t * copy);
# 67 "./src/lv_widgets/lv_line.h"
void lv_line_set_points(lv_obj_t * line, const lv_point_t point_a[], uint16_t point_num);







void lv_line_set_auto_size(lv_obj_t * line, bool en);
# 84 "./src/lv_widgets/lv_line.h"
void lv_line_set_y_invert(lv_obj_t * line, bool en);
# 99 "./src/lv_widgets/lv_line.h"
bool lv_line_get_auto_size(const lv_obj_t * line);






bool lv_line_get_y_invert(const lv_obj_t * line);
# 51 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_page.h" 1
# 38 "./src/lv_widgets/lv_page.h"
enum {
    LV_SCROLLBAR_MODE_OFF = 0x0,
    LV_SCROLLBAR_MODE_ON = 0x1,
    LV_SCROLLBAR_MODE_DRAG = 0x2,
    LV_SCROLLBAR_MODE_AUTO = 0x3,
    LV_SCROLLBAR_MODE_HIDE = 0x4,
    LV_SCROLLBAR_MODE_UNHIDE = 0x8,
};
typedef uint8_t lv_scrollbar_mode_t;


enum { LV_PAGE_EDGE_LEFT = 0x1, LV_PAGE_EDGE_TOP = 0x2, LV_PAGE_EDGE_RIGHT = 0x4, LV_PAGE_EDGE_BOTTOM = 0x8 };
typedef uint8_t lv_page_edge_t;


typedef struct {
    lv_cont_ext_t bg;

    lv_obj_t * scrl;
    struct {
        lv_style_list_t style;
        lv_area_t hor_area;
        lv_area_t ver_area;
        uint8_t hor_draw : 1;
        uint8_t ver_draw : 1;
        lv_scrollbar_mode_t mode : 3;
    } scrlbar;

    struct {
        lv_anim_value_t state;
        lv_style_list_t style;
        uint8_t enabled : 1;
        uint8_t top_ip : 1;

        uint8_t bottom_ip : 1;

        uint8_t right_ip : 1;

        uint8_t left_ip : 1;

    } edge_flash;

    uint16_t anim_time;

    lv_obj_t * scroll_prop_obj;
    uint8_t scroll_prop : 1;
} lv_page_ext_t;

enum {
    LV_PAGE_PART_BG = LV_CONT_PART_MAIN,
    LV_PAGE_PART_SCROLLBAR = _LV_OBJ_PART_VIRTUAL_LAST,

    LV_PAGE_PART_EDGE_FLASH,

    _LV_PAGE_PART_VIRTUAL_LAST,

    LV_PAGE_PART_SCROLLABLE = _LV_OBJ_PART_REAL_LAST,
    _LV_PAGE_PART_REAL_LAST,
};
typedef uint8_t lv_part_style_t;
# 109 "./src/lv_widgets/lv_page.h"
lv_obj_t * lv_page_create(lv_obj_t * par, const lv_obj_t * copy);





void lv_page_clean(lv_obj_t * page);






lv_obj_t * lv_page_get_scrollable(const lv_obj_t * page);






uint16_t lv_page_get_anim_time(const lv_obj_t * page);
# 140 "./src/lv_widgets/lv_page.h"
void lv_page_set_scrollbar_mode(lv_obj_t * page, lv_scrollbar_mode_t sb_mode);






void lv_page_set_anim_time(lv_obj_t * page, uint16_t anim_time);
# 157 "./src/lv_widgets/lv_page.h"
void lv_page_set_scroll_propagation(lv_obj_t * page, bool en);






void lv_page_set_edge_flash(lv_obj_t * page, bool en);
# 175 "./src/lv_widgets/lv_page.h"
static inline void lv_page_set_scrollable_fit4(lv_obj_t * page, lv_fit_t left, lv_fit_t right, lv_fit_t top,
                                               lv_fit_t bottom)
{
    lv_cont_set_fit4(lv_page_get_scrollable(page), left, right, top, bottom);
}
# 188 "./src/lv_widgets/lv_page.h"
static inline void lv_page_set_scrollable_fit2(lv_obj_t * page, lv_fit_t hor, lv_fit_t ver)
{
    lv_cont_set_fit2(lv_page_get_scrollable(page), hor, ver);
}







static inline void lv_page_set_scrollable_fit(lv_obj_t * page, lv_fit_t fit)
{
    lv_cont_set_fit(lv_page_get_scrollable(page), fit);
}






static inline void lv_page_set_scrl_width(lv_obj_t * page, lv_coord_t w)
{
    lv_obj_set_width(lv_page_get_scrollable(page), w);
}






static inline void lv_page_set_scrl_height(lv_obj_t * page, lv_coord_t h)
{
    lv_obj_set_height(lv_page_get_scrollable(page), h);
}






static inline void lv_page_set_scrl_layout(lv_obj_t * page, lv_layout_t layout)
{
    lv_cont_set_layout(lv_page_get_scrollable(page), layout);
}
# 243 "./src/lv_widgets/lv_page.h"
lv_scrollbar_mode_t lv_page_get_scrollbar_mode(const lv_obj_t * page);






bool lv_page_get_scroll_propagation(lv_obj_t * page);






bool lv_page_get_edge_flash(lv_obj_t * page);






lv_coord_t lv_page_get_width_fit(lv_obj_t * page);






lv_coord_t lv_page_get_height_fit(lv_obj_t * page);
# 284 "./src/lv_widgets/lv_page.h"
lv_coord_t lv_page_get_width_grid(lv_obj_t * page, uint8_t div, uint8_t span);
# 297 "./src/lv_widgets/lv_page.h"
lv_coord_t lv_page_get_height_grid(lv_obj_t * page, uint8_t div, uint8_t span);






static inline lv_coord_t lv_page_get_scrl_width(const lv_obj_t * page)
{
    return lv_obj_get_width(lv_page_get_scrollable(page));
}






static inline lv_coord_t lv_page_get_scrl_height(const lv_obj_t * page)
{
    return lv_obj_get_height(lv_page_get_scrollable(page));
}






static inline lv_layout_t lv_page_get_scrl_layout(const lv_obj_t * page)
{
    return lv_cont_get_layout(lv_page_get_scrollable(page));
}






static inline lv_fit_t lv_page_get_scrl_fit_left(const lv_obj_t * page)
{
    return lv_cont_get_fit_left(lv_page_get_scrollable(page));
}






static inline lv_fit_t lv_page_get_scrl_fit_right(const lv_obj_t * page)
{
    return lv_cont_get_fit_right(lv_page_get_scrollable(page));
}






static inline lv_fit_t lv_page_get_scrl_fit_top(const lv_obj_t * page)
{
    return lv_cont_get_fit_top(lv_page_get_scrollable(page));
}






static inline lv_fit_t lv_page_get_scrl_fit_bottom(const lv_obj_t * page)
{
    return lv_cont_get_fit_bottom(lv_page_get_scrollable(page));
}
# 379 "./src/lv_widgets/lv_page.h"
bool lv_page_on_edge(lv_obj_t * page, lv_page_edge_t edge);






void lv_page_glue_obj(lv_obj_t * obj, bool glue);







void lv_page_focus(lv_obj_t * page, const lv_obj_t * obj, lv_anim_enable_t anim_en);






void lv_page_scroll_hor(lv_obj_t * page, lv_coord_t dist);






void lv_page_scroll_ver(lv_obj_t * page, lv_coord_t dist);







void lv_page_start_edge_flash(lv_obj_t * page, lv_page_edge_t edge);
# 52 "lvgl.h" 2

# 1 "./src/lv_widgets/lv_list.h" 1
# 47 "./src/lv_widgets/lv_list.h"
typedef struct {
    lv_page_ext_t page;



    lv_obj_t * last_sel_btn;

    lv_obj_t * act_sel_btn;
} lv_list_ext_t;


enum {
    LV_LIST_PART_BG = LV_PAGE_PART_BG,
    LV_LIST_PART_SCROLLBAR = LV_PAGE_PART_SCROLLBAR,

    LV_LIST_PART_EDGE_FLASH = LV_PAGE_PART_EDGE_FLASH,

    _LV_LIST_PART_VIRTUAL_LAST = _LV_PAGE_PART_VIRTUAL_LAST,
    LV_LIST_PART_SCROLLABLE = LV_PAGE_PART_SCROLLABLE,
    _LV_LIST_PART_REAL_LAST = _LV_PAGE_PART_REAL_LAST,
};
typedef uint8_t lv_list_style_t;
# 80 "./src/lv_widgets/lv_list.h"
lv_obj_t * lv_list_create(lv_obj_t * par, const lv_obj_t * copy);





void lv_list_clean(lv_obj_t * list);
# 99 "./src/lv_widgets/lv_list.h"
lv_obj_t * lv_list_add_btn(lv_obj_t * list, const void * img_src, const char * txt);
# 108 "./src/lv_widgets/lv_list.h"
bool lv_list_remove(const lv_obj_t * list, uint16_t index);
# 120 "./src/lv_widgets/lv_list.h"
void lv_list_focus_btn(lv_obj_t * list, lv_obj_t * btn);






static inline void lv_list_set_scrollbar_mode(lv_obj_t * list, lv_scrollbar_mode_t mode)
{
    lv_page_set_scrollbar_mode(list, mode);
}







static inline void lv_list_set_scroll_propagation(lv_obj_t * list, bool en)
{
    lv_page_set_scroll_propagation(list, en);
}






static inline void lv_list_set_edge_flash(lv_obj_t * list, bool en)
{
    lv_page_set_edge_flash(list, en);
}






static inline void lv_list_set_anim_time(lv_obj_t * list, uint16_t anim_time)
{
    lv_page_set_anim_time(list, anim_time);
}






void lv_list_set_layout(lv_obj_t * list, lv_layout_t layout);
# 179 "./src/lv_widgets/lv_list.h"
const char * lv_list_get_btn_text(const lv_obj_t * btn);





lv_obj_t * lv_list_get_btn_label(const lv_obj_t * btn);






lv_obj_t * lv_list_get_btn_img(const lv_obj_t * btn);







lv_obj_t * lv_list_get_prev_btn(const lv_obj_t * list, lv_obj_t * prev_btn);







lv_obj_t * lv_list_get_next_btn(const lv_obj_t * list, lv_obj_t * prev_btn);







int32_t lv_list_get_btn_index(const lv_obj_t * list, const lv_obj_t * btn);






uint16_t lv_list_get_size(const lv_obj_t * list);







lv_obj_t * lv_list_get_btn_selected(const lv_obj_t * list);







lv_layout_t lv_list_get_layout(lv_obj_t * list);






static inline lv_scrollbar_mode_t lv_list_get_scrollbar_mode(const lv_obj_t * list)
{
    return lv_page_get_scrollbar_mode(list);
}






static inline bool lv_list_get_scroll_propagation(lv_obj_t * list)
{
    return lv_page_get_scroll_propagation(list);
}






static inline bool lv_list_get_edge_flash(lv_obj_t * list)
{
    return lv_page_get_edge_flash(list);
}






static inline uint16_t lv_list_get_anim_time(const lv_obj_t * list)
{
    return lv_page_get_anim_time(list);
}
# 289 "./src/lv_widgets/lv_list.h"
void lv_list_up(const lv_obj_t * list);




void lv_list_down(const lv_obj_t * list);






void lv_list_focus(const lv_obj_t * btn, lv_anim_enable_t anim);
# 54 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_chart.h" 1
# 33 "./src/lv_widgets/lv_chart.h"
struct _silence_gcc_warning;
struct _silence_gcc_warning;






enum {
    LV_CHART_TYPE_NONE = 0x00,
    LV_CHART_TYPE_LINE = 0x01,
    LV_CHART_TYPE_COLUMN = 0x02,
};
typedef uint8_t lv_chart_type_t;


enum {
    LV_CHART_UPDATE_MODE_SHIFT,
    LV_CHART_UPDATE_MODE_CIRCULAR,
};
typedef uint8_t lv_chart_update_mode_t;

enum {
    LV_CHART_AXIS_PRIMARY_Y,
    LV_CHART_AXIS_SECONDARY_Y,
    _LV_CHART_AXIS_LAST,
};
typedef uint8_t lv_chart_axis_t;

enum {
    LV_CHART_CURSOR_NONE = 0x00,
    LV_CHART_CURSOR_RIGHT = 0x01,
    LV_CHART_CURSOR_UP = 0x02,
    LV_CHART_CURSOR_LEFT = 0x04,
    LV_CHART_CURSOR_DOWN = 0x08
};
typedef uint8_t lv_cursor_direction_t;

typedef struct {
    lv_coord_t * points;
    lv_color_t color;
    uint16_t start_point;
    uint8_t ext_buf_assigned : 1;
    uint8_t hidden : 1;
    lv_chart_axis_t y_axis : 1;
} lv_chart_series_t;

typedef struct {
    lv_point_t point;
    lv_color_t color;
    lv_cursor_direction_t axes : 4;
} lv_chart_cursor_t;


enum {
    LV_CHART_AXIS_SKIP_LAST_TICK = 0x00,
    LV_CHART_AXIS_DRAW_LAST_TICK = 0x01,
    LV_CHART_AXIS_INVERSE_LABELS_ORDER = 0x02
};
typedef uint8_t lv_chart_axis_options_t;

typedef struct {
    const char * list_of_values;
    lv_chart_axis_options_t options;
    uint8_t num_tick_marks;
    uint8_t major_tick_len;
    uint8_t minor_tick_len;
} lv_chart_axis_cfg_t;


typedef struct {


    lv_ll_t series_ll;
    lv_ll_t cursors_ll;
    lv_coord_t ymin[_LV_CHART_AXIS_LAST];
    lv_coord_t ymax[_LV_CHART_AXIS_LAST];
    uint8_t hdiv_cnt;
    uint8_t vdiv_cnt;
    uint16_t point_cnt;
    lv_style_list_t style_series_bg;
    lv_style_list_t style_series;
    lv_style_list_t style_cursors;
    lv_chart_type_t type;
    lv_chart_axis_cfg_t y_axis;
    lv_chart_axis_cfg_t x_axis;
    lv_chart_axis_cfg_t secondary_y_axis;
    uint8_t update_mode : 1;
} lv_chart_ext_t;


enum {
    LV_CHART_PART_BG = LV_OBJ_PART_MAIN,
    LV_CHART_PART_SERIES_BG = _LV_OBJ_PART_VIRTUAL_LAST,
    LV_CHART_PART_SERIES,
    LV_CHART_PART_CURSOR
};
# 142 "./src/lv_widgets/lv_chart.h"
lv_obj_t * lv_chart_create(lv_obj_t * par, const lv_obj_t * copy);
# 154 "./src/lv_widgets/lv_chart.h"
lv_chart_series_t * lv_chart_add_series(lv_obj_t * chart, lv_color_t color);






void lv_chart_remove_series(lv_obj_t * chart, lv_chart_series_t * series);
# 170 "./src/lv_widgets/lv_chart.h"
lv_chart_cursor_t * lv_chart_add_cursor(lv_obj_t * chart, lv_color_t color, lv_cursor_direction_t dir);






void lv_chart_clear_series(lv_obj_t * chart, lv_chart_series_t * series);







void lv_chart_hide_series(lv_obj_t * chart, lv_chart_series_t * series, bool hide);
# 197 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_div_line_count(lv_obj_t * chart, uint8_t hdiv, uint8_t vdiv);
# 206 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_y_range(lv_obj_t * chart, lv_chart_axis_t axis, lv_coord_t ymin, lv_coord_t ymax);






void lv_chart_set_type(lv_obj_t * chart, lv_chart_type_t type);






void lv_chart_set_point_count(lv_obj_t * chart, uint16_t point_cnt);







void lv_chart_init_points(lv_obj_t * chart, lv_chart_series_t * ser, lv_coord_t y);







void lv_chart_set_points(lv_obj_t * chart, lv_chart_series_t * ser, lv_coord_t y_array[]);







void lv_chart_set_next(lv_obj_t * chart, lv_chart_series_t * ser, lv_coord_t y);






void lv_chart_set_update_mode(lv_obj_t * chart, lv_chart_update_mode_t update_mode);
# 261 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_x_tick_length(lv_obj_t * chart, uint8_t major_tick_len, uint8_t minor_tick_len);
# 271 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_y_tick_length(lv_obj_t * chart, uint8_t major_tick_len, uint8_t minor_tick_len);
# 281 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_secondary_y_tick_length(lv_obj_t * chart, uint8_t major_tick_len, uint8_t minor_tick_len);
# 291 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_x_tick_texts(lv_obj_t * chart, const char * list_of_values, uint8_t num_tick_marks,
                               lv_chart_axis_options_t options);
# 302 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_secondary_y_tick_texts(lv_obj_t * chart, const char * list_of_values, uint8_t num_tick_marks,
                                         lv_chart_axis_options_t options);
# 313 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_y_tick_texts(lv_obj_t * chart, const char * list_of_values, uint8_t num_tick_marks,
                               lv_chart_axis_options_t options);







void lv_chart_set_x_start_point(lv_obj_t * chart, lv_chart_series_t * ser, uint16_t id);
# 331 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_ext_array(lv_obj_t * chart, lv_chart_series_t * ser, lv_coord_t array[], uint16_t point_cnt);
# 340 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_point_id(lv_obj_t * chart, lv_chart_series_t * ser, lv_coord_t value, uint16_t id);







void lv_chart_set_series_axis(lv_obj_t * chart, lv_chart_series_t * ser, lv_chart_axis_t axis);
# 357 "./src/lv_widgets/lv_chart.h"
void lv_chart_set_cursor_point(lv_obj_t * chart, lv_chart_cursor_t * cursor, lv_point_t * point);
# 368 "./src/lv_widgets/lv_chart.h"
lv_chart_type_t lv_chart_get_type(const lv_obj_t * chart);






uint16_t lv_chart_get_point_count(const lv_obj_t * chart);






uint16_t lv_chart_get_x_start_point(lv_chart_series_t * ser);
# 391 "./src/lv_widgets/lv_chart.h"
lv_coord_t lv_chart_get_point_id(lv_obj_t * chart, lv_chart_series_t * ser, uint16_t id);







lv_chart_axis_t lv_chart_get_series_axis(lv_obj_t * chart, lv_chart_series_t * ser);






void lv_chart_get_series_area(lv_obj_t * chart, lv_area_t * series_area);
# 415 "./src/lv_widgets/lv_chart.h"
lv_point_t lv_chart_get_cursor_point(lv_obj_t * chart, lv_chart_cursor_t * cursor);







uint16_t lv_chart_get_nearest_index_from_coord(lv_obj_t * chart, lv_coord_t x);
# 433 "./src/lv_widgets/lv_chart.h"
lv_coord_t lv_chart_get_x_from_index(lv_obj_t * chart, lv_chart_series_t * ser, uint16_t id);
# 443 "./src/lv_widgets/lv_chart.h"
lv_coord_t lv_chart_get_y_from_index(lv_obj_t * chart, lv_chart_series_t * ser, uint16_t id);
# 453 "./src/lv_widgets/lv_chart.h"
void lv_chart_refresh(lv_obj_t * chart);
# 55 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_table.h" 1
# 55 "./src/lv_widgets/lv_table.h"
typedef union {
    struct {
        uint8_t align : 2;
        uint8_t right_merge : 1;
        uint8_t type : 4;
        uint8_t crop : 1;
    } s;
    uint8_t format_byte;
} lv_table_cell_format_t;


typedef struct {

    uint16_t col_cnt;
    uint16_t row_cnt;
    char ** cell_data;
    lv_coord_t * row_h;
    lv_style_list_t cell_style[4];
    lv_coord_t col_w[12];
uint16_t cell_types :
    4;
} lv_table_ext_t;


enum {
    LV_TABLE_PART_BG,
    LV_TABLE_PART_CELL1,
    LV_TABLE_PART_CELL2,
    LV_TABLE_PART_CELL3,
    LV_TABLE_PART_CELL4,

};
# 98 "./src/lv_widgets/lv_table.h"
lv_obj_t * lv_table_create(lv_obj_t * par, const lv_obj_t * copy);
# 112 "./src/lv_widgets/lv_table.h"
void lv_table_set_cell_value(lv_obj_t * table, uint16_t row, uint16_t col, const char * txt);
# 121 "./src/lv_widgets/lv_table.h"
void lv_table_set_cell_value_fmt(lv_obj_t * table, uint16_t row, uint16_t col, const char * fmt, ...);






void lv_table_set_row_cnt(lv_obj_t * table, uint16_t row_cnt);






void lv_table_set_col_cnt(lv_obj_t * table, uint16_t col_cnt);







void lv_table_set_col_width(lv_obj_t * table, uint16_t col_id, lv_coord_t w);
# 152 "./src/lv_widgets/lv_table.h"
void lv_table_set_cell_align(lv_obj_t * table, uint16_t row, uint16_t col, lv_label_align_t align);
# 161 "./src/lv_widgets/lv_table.h"
void lv_table_set_cell_type(lv_obj_t * table, uint16_t row, uint16_t col, uint8_t type);
# 170 "./src/lv_widgets/lv_table.h"
void lv_table_set_cell_crop(lv_obj_t * table, uint16_t row, uint16_t col, bool crop);
# 179 "./src/lv_widgets/lv_table.h"
void lv_table_set_cell_merge_right(lv_obj_t * table, uint16_t row, uint16_t col, bool en);
# 192 "./src/lv_widgets/lv_table.h"
const char * lv_table_get_cell_value(lv_obj_t * table, uint16_t row, uint16_t col);






uint16_t lv_table_get_row_cnt(lv_obj_t * table);






uint16_t lv_table_get_col_cnt(lv_obj_t * table);







lv_coord_t lv_table_get_col_width(lv_obj_t * table, uint16_t col_id);
# 224 "./src/lv_widgets/lv_table.h"
lv_label_align_t lv_table_get_cell_align(lv_obj_t * table, uint16_t row, uint16_t col);
# 233 "./src/lv_widgets/lv_table.h"
lv_label_align_t lv_table_get_cell_type(lv_obj_t * table, uint16_t row, uint16_t col);
# 242 "./src/lv_widgets/lv_table.h"
lv_label_align_t lv_table_get_cell_crop(lv_obj_t * table, uint16_t row, uint16_t col);
# 251 "./src/lv_widgets/lv_table.h"
bool lv_table_get_cell_merge_right(lv_obj_t * table, uint16_t row, uint16_t col);
# 260 "./src/lv_widgets/lv_table.h"
lv_res_t lv_table_get_pressed_cell(lv_obj_t * table, uint16_t * row, uint16_t * col);
# 56 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_checkbox.h" 1
# 42 "./src/lv_widgets/lv_checkbox.h"
typedef struct {
    lv_btn_ext_t bg_btn;

    lv_obj_t * bullet;
    lv_obj_t * label;
} lv_checkbox_ext_t;


enum {
    LV_CHECKBOX_PART_BG = LV_BTN_PART_MAIN,
    _LV_CHECKBOX_PART_VIRTUAL_LAST,
    LV_CHECKBOX_PART_BULLET = _LV_BTN_PART_REAL_LAST,
    _LV_CHECKBOX_PART_REAL_LAST
};
typedef uint8_t lv_checkbox_style_t;
# 68 "./src/lv_widgets/lv_checkbox.h"
lv_obj_t * lv_checkbox_create(lv_obj_t * par, const lv_obj_t * copy);
# 80 "./src/lv_widgets/lv_checkbox.h"
void lv_checkbox_set_text(lv_obj_t * cb, const char * txt);







void lv_checkbox_set_text_static(lv_obj_t * cb, const char * txt);






void lv_checkbox_set_checked(lv_obj_t * cb, bool checked);





void lv_checkbox_set_disabled(lv_obj_t * cb);






void lv_checkbox_set_state(lv_obj_t * cb, lv_btn_state_t state);
# 118 "./src/lv_widgets/lv_checkbox.h"
const char * lv_checkbox_get_text(const lv_obj_t * cb);






static inline bool lv_checkbox_is_checked(const lv_obj_t * cb)
{
    return lv_btn_get_state(cb) == LV_BTN_STATE_RELEASED ? 0 : 1;
}






static inline bool lv_checkbox_is_inactive(const lv_obj_t * cb)
{
    return lv_btn_get_state(cb) == LV_BTN_STATE_DISABLED ? 1 : 0;
}






static inline lv_btn_state_t lv_checkbox_get_state(const lv_obj_t * cb)
{
    return lv_btn_get_state(cb);
}
# 57 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_cpicker.h" 1
# 30 "./src/lv_widgets/lv_cpicker.h"
enum {
    LV_CPICKER_TYPE_RECT,
    LV_CPICKER_TYPE_DISC,
};
typedef uint8_t lv_cpicker_type_t;

enum {
    LV_CPICKER_COLOR_MODE_HUE,
    LV_CPICKER_COLOR_MODE_SATURATION,
    LV_CPICKER_COLOR_MODE_VALUE
};
typedef uint8_t lv_cpicker_color_mode_t;


typedef struct {
    lv_color_hsv_t hsv;
    struct {
        lv_style_list_t style_list;
        lv_point_t pos;
        uint8_t colored : 1;

    } knob;
    uint32_t last_click_time;
    uint32_t last_change_time;
    lv_point_t last_press_point;
    lv_cpicker_color_mode_t color_mode : 2;
    uint8_t color_mode_fixed : 1;
    lv_cpicker_type_t type : 1;
} lv_cpicker_ext_t;


enum {
    LV_CPICKER_PART_MAIN = LV_OBJ_PART_MAIN,
    LV_CPICKER_PART_KNOB = _LV_OBJ_PART_VIRTUAL_LAST,
    _LV_CPICKER_PART_VIRTUAL_LAST,
    _LV_CPICKER_PART_REAL_LAST = _LV_OBJ_PART_REAL_LAST,
};
# 78 "./src/lv_widgets/lv_cpicker.h"
lv_obj_t * lv_cpicker_create(lv_obj_t * par, const lv_obj_t * copy);
# 89 "./src/lv_widgets/lv_cpicker.h"
void lv_cpicker_set_type(lv_obj_t * cpicker, lv_cpicker_type_t type);







bool lv_cpicker_set_hue(lv_obj_t * cpicker, uint16_t hue);







bool lv_cpicker_set_saturation(lv_obj_t * cpicker, uint8_t saturation);







bool lv_cpicker_set_value(lv_obj_t * cpicker, uint8_t val);







bool lv_cpicker_set_hsv(lv_obj_t * cpicker, lv_color_hsv_t hsv);







bool lv_cpicker_set_color(lv_obj_t * cpicker, lv_color_t color);






void lv_cpicker_set_color_mode(lv_obj_t * cpicker, lv_cpicker_color_mode_t mode);






void lv_cpicker_set_color_mode_fixed(lv_obj_t * cpicker, bool fixed);






void lv_cpicker_set_knob_colored(lv_obj_t * cpicker, bool en);
# 161 "./src/lv_widgets/lv_cpicker.h"
lv_cpicker_color_mode_t lv_cpicker_get_color_mode(lv_obj_t * cpicker);






bool lv_cpicker_get_color_mode_fixed(lv_obj_t * cpicker);






uint16_t lv_cpicker_get_hue(lv_obj_t * cpicker);






uint8_t lv_cpicker_get_saturation(lv_obj_t * cpicker);






uint8_t lv_cpicker_get_value(lv_obj_t * cpicker);






lv_color_hsv_t lv_cpicker_get_hsv(lv_obj_t * cpicker);






lv_color_t lv_cpicker_get_color(lv_obj_t * cpicker);






bool lv_cpicker_get_knob_colored(lv_obj_t * cpicker);
# 58 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_bar.h" 1
# 46 "./src/lv_widgets/lv_bar.h"
enum {
    LV_BAR_TYPE_NORMAL,
    LV_BAR_TYPE_SYMMETRICAL,
    LV_BAR_TYPE_CUSTOM
};
typedef uint8_t lv_bar_type_t;


typedef struct {
    lv_obj_t * bar;
    lv_anim_value_t anim_start;
    lv_anim_value_t anim_end;
    lv_anim_value_t anim_state;
} lv_bar_anim_t;



typedef struct {



    int16_t cur_value;
    int16_t min_value;
    int16_t max_value;
    int16_t start_value;
    lv_area_t indic_area;

    lv_anim_value_t anim_time;
    lv_bar_anim_t cur_value_anim;
    lv_bar_anim_t start_value_anim;

    uint8_t type : 2;
    lv_style_list_t style_indic;
} lv_bar_ext_t;


enum {
    LV_BAR_PART_BG,
    LV_BAR_PART_INDIC,
    _LV_BAR_PART_VIRTUAL_LAST
};
typedef uint8_t lv_bar_part_t;
# 99 "./src/lv_widgets/lv_bar.h"
lv_obj_t * lv_bar_create(lv_obj_t * par, const lv_obj_t * copy);
# 111 "./src/lv_widgets/lv_bar.h"
void lv_bar_set_value(lv_obj_t * bar, int16_t value, lv_anim_enable_t anim);







void lv_bar_set_start_value(lv_obj_t * bar, int16_t start_value, lv_anim_enable_t anim);







void lv_bar_set_range(lv_obj_t * bar, int16_t min, int16_t max);






void lv_bar_set_type(lv_obj_t * bar, lv_bar_type_t type);






void lv_bar_set_anim_time(lv_obj_t * bar, uint16_t anim_time);
# 152 "./src/lv_widgets/lv_bar.h"
int16_t lv_bar_get_value(const lv_obj_t * bar);






int16_t lv_bar_get_start_value(const lv_obj_t * bar);






int16_t lv_bar_get_min_value(const lv_obj_t * bar);






int16_t lv_bar_get_max_value(const lv_obj_t * bar);






lv_bar_type_t lv_bar_get_type(lv_obj_t * bar);






uint16_t lv_bar_get_anim_time(const lv_obj_t * bar);
# 59 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_slider.h" 1
# 36 "./src/lv_widgets/lv_slider.h"
enum {
    LV_SLIDER_TYPE_NORMAL,
    LV_SLIDER_TYPE_SYMMETRICAL,
    LV_SLIDER_TYPE_RANGE
};
typedef uint8_t lv_slider_type_t;


typedef struct {
    lv_bar_ext_t bar;

    lv_style_list_t style_knob;
    lv_area_t left_knob_area;
    lv_area_t right_knob_area;
    int16_t * value_to_set;
    uint8_t dragging : 1;
    uint8_t left_knob_focus : 1;
} lv_slider_ext_t;


enum {
    LV_SLIDER_PART_BG,
    LV_SLIDER_PART_INDIC,
    LV_SLIDER_PART_KNOB,
};
# 72 "./src/lv_widgets/lv_slider.h"
lv_obj_t * lv_slider_create(lv_obj_t * par, const lv_obj_t * copy);
# 84 "./src/lv_widgets/lv_slider.h"
static inline void lv_slider_set_value(lv_obj_t * slider, int16_t value, lv_anim_enable_t anim)
{
    lv_bar_set_value(slider, value, anim);
}







static inline void lv_slider_set_left_value(lv_obj_t * slider, int16_t left_value, lv_anim_enable_t anim)
{
    lv_bar_set_start_value(slider, left_value, anim);
}







static inline void lv_slider_set_range(lv_obj_t * slider, int16_t min, int16_t max)
{
    lv_bar_set_range(slider, min, max);
}






static inline void lv_slider_set_anim_time(lv_obj_t * slider, uint16_t anim_time)
{
    lv_bar_set_anim_time(slider, anim_time);
}







static inline void lv_slider_set_type(lv_obj_t * slider, lv_slider_type_t type)
{
    if(type == LV_SLIDER_TYPE_NORMAL)
        lv_bar_set_type(slider, LV_BAR_TYPE_NORMAL);
    else if(type == LV_SLIDER_TYPE_SYMMETRICAL)
        lv_bar_set_type(slider, LV_BAR_TYPE_SYMMETRICAL);
    else if(type == LV_SLIDER_TYPE_RANGE)
        lv_bar_set_type(slider, LV_BAR_TYPE_CUSTOM);
}
# 146 "./src/lv_widgets/lv_slider.h"
int16_t lv_slider_get_value(const lv_obj_t * slider);






static inline int16_t lv_slider_get_left_value(const lv_obj_t * slider)
{
    return lv_bar_get_start_value(slider);
}






static inline int16_t lv_slider_get_min_value(const lv_obj_t * slider)
{
    return lv_bar_get_min_value(slider);
}






static inline int16_t lv_slider_get_max_value(const lv_obj_t * slider)
{
    return lv_bar_get_max_value(slider);
}






bool lv_slider_is_dragged(const lv_obj_t * slider);






static inline uint16_t lv_slider_get_anim_time(lv_obj_t * slider)
{
    return lv_bar_get_anim_time(slider);
}






static inline lv_slider_type_t lv_slider_get_type(lv_obj_t * slider)
{
    lv_bar_type_t type = lv_bar_get_type(slider);
    if(type == LV_BAR_TYPE_SYMMETRICAL)
        return LV_SLIDER_TYPE_SYMMETRICAL;
    else if(type == LV_BAR_TYPE_CUSTOM)
        return LV_SLIDER_TYPE_RANGE;
    else
        return LV_SLIDER_TYPE_NORMAL;
}
# 60 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_led.h" 1
# 31 "./src/lv_widgets/lv_led.h"
typedef struct {


    uint8_t bright;
} lv_led_ext_t;


enum {
    LV_LED_PART_MAIN = LV_OBJ_PART_MAIN,
};
typedef uint8_t lv_led_part_t;
# 53 "./src/lv_widgets/lv_led.h"
lv_obj_t * lv_led_create(lv_obj_t * par, const lv_obj_t * copy);






void lv_led_set_bright(lv_obj_t * led, uint8_t bright);





void lv_led_on(lv_obj_t * led);





void lv_led_off(lv_obj_t * led);





void lv_led_toggle(lv_obj_t * led);






uint8_t lv_led_get_bright(const lv_obj_t * led);
# 61 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_btnmatrix.h" 1
# 30 "./src/lv_widgets/lv_btnmatrix.h"
struct _silence_gcc_warning;







enum {
    LV_BTNMATRIX_CTRL_HIDDEN = 0x0008,
    LV_BTNMATRIX_CTRL_NO_REPEAT = 0x0010,
    LV_BTNMATRIX_CTRL_DISABLED = 0x0020,
    LV_BTNMATRIX_CTRL_CHECKABLE = 0x0040,
    LV_BTNMATRIX_CTRL_CHECK_STATE = 0x0080,
    LV_BTNMATRIX_CTRL_CLICK_TRIG = 0x0100,
};
typedef uint16_t lv_btnmatrix_ctrl_t;


typedef struct {


    const char ** map_p;
    lv_area_t * button_areas;
    lv_btnmatrix_ctrl_t * ctrl_bits;
    lv_style_list_t style_btn;
    uint16_t btn_cnt;
    uint16_t btn_id_pr;
    uint16_t btn_id_focused;
    uint16_t btn_id_act;
    uint8_t recolor : 1;
    uint8_t one_check : 1;
    uint8_t align : 2;
} lv_btnmatrix_ext_t;

enum {
    LV_BTNMATRIX_PART_BG,
    LV_BTNMATRIX_PART_BTN,
};
typedef uint8_t lv_btnmatrix_part_t;
# 82 "./src/lv_widgets/lv_btnmatrix.h"
lv_obj_t * lv_btnmatrix_create(lv_obj_t * par, const lv_obj_t * copy);
# 95 "./src/lv_widgets/lv_btnmatrix.h"
void lv_btnmatrix_set_map(lv_obj_t * btnm, const char * map[]);
# 109 "./src/lv_widgets/lv_btnmatrix.h"
void lv_btnmatrix_set_ctrl_map(lv_obj_t * btnm, const lv_btnmatrix_ctrl_t ctrl_map[]);






void lv_btnmatrix_set_focused_btn(lv_obj_t * btnm, uint16_t id);






void lv_btnmatrix_set_recolor(const lv_obj_t * btnm, bool en);






void lv_btnmatrix_set_btn_ctrl(lv_obj_t * btnm, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl);






void lv_btnmatrix_clear_btn_ctrl(const lv_obj_t * btnm, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl);






void lv_btnmatrix_set_btn_ctrl_all(lv_obj_t * btnm, lv_btnmatrix_ctrl_t ctrl);







void lv_btnmatrix_clear_btn_ctrl_all(lv_obj_t * btnm, lv_btnmatrix_ctrl_t ctrl);
# 163 "./src/lv_widgets/lv_btnmatrix.h"
void lv_btnmatrix_set_btn_width(lv_obj_t * btnm, uint16_t btn_id, uint8_t width);
# 172 "./src/lv_widgets/lv_btnmatrix.h"
void lv_btnmatrix_set_one_check(lv_obj_t * btnm, bool one_chk);






void lv_btnmatrix_set_align(lv_obj_t * btnm, lv_label_align_t align);
# 190 "./src/lv_widgets/lv_btnmatrix.h"
const char ** lv_btnmatrix_get_map_array(const lv_obj_t * btnm);






bool lv_btnmatrix_get_recolor(const lv_obj_t * btnm);







uint16_t lv_btnmatrix_get_active_btn(const lv_obj_t * btnm);







const char * lv_btnmatrix_get_active_btn_text(const lv_obj_t * btnm);






uint16_t lv_btnmatrix_get_focused_btn(const lv_obj_t * btnm);
# 229 "./src/lv_widgets/lv_btnmatrix.h"
const char * lv_btnmatrix_get_btn_text(const lv_obj_t * btnm, uint16_t btn_id);
# 239 "./src/lv_widgets/lv_btnmatrix.h"
bool lv_btnmatrix_get_btn_ctrl(lv_obj_t * btnm, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl);






bool lv_btnmatrix_get_one_check(const lv_obj_t * btnm);






lv_label_align_t lv_btnmatrix_get_align(const lv_obj_t * btnm);
# 62 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_keyboard.h" 1
# 42 "./src/lv_widgets/lv_keyboard.h"
enum {
    LV_KEYBOARD_MODE_TEXT_LOWER,
    LV_KEYBOARD_MODE_TEXT_UPPER,
    LV_KEYBOARD_MODE_SPECIAL,
    LV_KEYBOARD_MODE_NUM



};
typedef uint8_t lv_keyboard_mode_t;


typedef struct {
    lv_btnmatrix_ext_t btnm;

    lv_obj_t * ta;
    lv_keyboard_mode_t mode;
    uint8_t cursor_mng : 1;
} lv_keyboard_ext_t;

enum {
    LV_KEYBOARD_PART_BG,
    LV_KEYBOARD_PART_BTN,
};
typedef uint8_t lv_keyboard_style_t;
# 78 "./src/lv_widgets/lv_keyboard.h"
lv_obj_t * lv_keyboard_create(lv_obj_t * par, const lv_obj_t * copy);
# 89 "./src/lv_widgets/lv_keyboard.h"
void lv_keyboard_set_textarea(lv_obj_t * kb, lv_obj_t * ta);






void lv_keyboard_set_mode(lv_obj_t * kb, lv_keyboard_mode_t mode);






void lv_keyboard_set_cursor_manage(lv_obj_t * kb, bool en);
# 112 "./src/lv_widgets/lv_keyboard.h"
void lv_keyboard_set_map(lv_obj_t * kb, lv_keyboard_mode_t mode, const char * map[]);
# 123 "./src/lv_widgets/lv_keyboard.h"
void lv_keyboard_set_ctrl_map(lv_obj_t * kb, lv_keyboard_mode_t mode, const lv_btnmatrix_ctrl_t ctrl_map[]);
# 134 "./src/lv_widgets/lv_keyboard.h"
lv_obj_t * lv_keyboard_get_textarea(const lv_obj_t * kb);






lv_keyboard_mode_t lv_keyboard_get_mode(const lv_obj_t * kb);






bool lv_keyboard_get_cursor_manage(const lv_obj_t * kb);






static inline const char ** lv_keyboard_get_map_array(const lv_obj_t * kb)
{
    return lv_btnmatrix_get_map_array(kb);
}
# 171 "./src/lv_widgets/lv_keyboard.h"
void lv_keyboard_def_event_cb(lv_obj_t * kb, lv_event_t event);
# 63 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_dropdown.h" 1
# 41 "./src/lv_widgets/lv_dropdown.h"
enum {
    LV_DROPDOWN_DIR_DOWN,
    LV_DROPDOWN_DIR_UP,
    LV_DROPDOWN_DIR_LEFT,
    LV_DROPDOWN_DIR_RIGHT,
};

typedef uint8_t lv_dropdown_dir_t;


typedef struct {

    lv_obj_t * page;
    const char * text;
    const char * symbol;
    char * options;
    lv_style_list_t style_selected;
    lv_style_list_t style_page;
    lv_style_list_t style_scrlbar;
    lv_coord_t max_height;
    uint16_t option_cnt;
    uint16_t sel_opt_id;
    uint16_t sel_opt_id_orig;
    uint16_t pr_opt_id;
    lv_dropdown_dir_t dir : 2;
    uint8_t show_selected : 1;
    uint8_t static_txt : 1;
} lv_dropdown_ext_t;

enum {
    LV_DROPDOWN_PART_MAIN = LV_OBJ_PART_MAIN,
    LV_DROPDOWN_PART_LIST = _LV_OBJ_PART_REAL_LAST,
    LV_DROPDOWN_PART_SCROLLBAR,
    LV_DROPDOWN_PART_SELECTED,
};
typedef uint8_t lv_dropdown_part_t;
# 88 "./src/lv_widgets/lv_dropdown.h"
lv_obj_t * lv_dropdown_create(lv_obj_t * par, const lv_obj_t * copy);
# 99 "./src/lv_widgets/lv_dropdown.h"
void lv_dropdown_set_text(lv_obj_t * ddlist, const char * txt);





void lv_dropdown_clear_options(lv_obj_t * ddlist);







void lv_dropdown_set_options(lv_obj_t * ddlist, const char * options);






void lv_dropdown_set_options_static(lv_obj_t * ddlist, const char * options);







void lv_dropdown_add_option(lv_obj_t * ddlist, const char * option, uint32_t pos);






void lv_dropdown_set_selected(lv_obj_t * ddlist, uint16_t sel_opt);






void lv_dropdown_set_dir(lv_obj_t * ddlist, lv_dropdown_dir_t dir);






void lv_dropdown_set_max_height(lv_obj_t * ddlist, lv_coord_t h);






void lv_dropdown_set_symbol(lv_obj_t * ddlist, const char * symbol);






void lv_dropdown_set_show_selected(lv_obj_t * ddlist, bool show);
# 174 "./src/lv_widgets/lv_dropdown.h"
const char * lv_dropdown_get_text(lv_obj_t * ddlist);






const char * lv_dropdown_get_options(const lv_obj_t * ddlist);






uint16_t lv_dropdown_get_selected(const lv_obj_t * ddlist);






uint16_t lv_dropdown_get_option_cnt(const lv_obj_t * ddlist);







void lv_dropdown_get_selected_str(const lv_obj_t * ddlist, char * buf, uint32_t buf_size);






lv_coord_t lv_dropdown_get_max_height(const lv_obj_t * ddlist);






const char * lv_dropdown_get_symbol(lv_obj_t * ddlist);






lv_dropdown_dir_t lv_dropdown_get_dir(const lv_obj_t * ddlist);






bool lv_dropdown_get_show_selected(lv_obj_t * ddlist);
# 241 "./src/lv_widgets/lv_dropdown.h"
void lv_dropdown_open(lv_obj_t * ddlist);






void lv_dropdown_close(lv_obj_t * ddlist);
# 64 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_roller.h" 1
# 38 "./src/lv_widgets/lv_roller.h"
enum {
    LV_ROLLER_MODE_NORMAL,
    LV_ROLLER_MODE_INFINITE,
};

typedef uint8_t lv_roller_mode_t;


typedef struct {
    lv_page_ext_t page;


    lv_style_list_t style_sel;
    uint16_t option_cnt;
    uint16_t sel_opt_id;
    uint16_t sel_opt_id_ori;
    lv_roller_mode_t mode : 1;
    uint8_t auto_fit : 1;
} lv_roller_ext_t;

enum {
    LV_ROLLER_PART_BG = LV_PAGE_PART_BG,
    LV_ROLLER_PART_SELECTED = _LV_PAGE_PART_VIRTUAL_LAST,
    _LV_ROLLER_PART_VIRTUAL_LAST,
};
typedef uint8_t lv_roller_part_t;
# 75 "./src/lv_widgets/lv_roller.h"
lv_obj_t * lv_roller_create(lv_obj_t * par, const lv_obj_t * copy);
# 87 "./src/lv_widgets/lv_roller.h"
void lv_roller_set_options(lv_obj_t * roller, const char * options, lv_roller_mode_t mode);






void lv_roller_set_align(lv_obj_t * roller, lv_label_align_t align);







void lv_roller_set_selected(lv_obj_t * roller, uint16_t sel_opt, lv_anim_enable_t anim);






void lv_roller_set_visible_row_count(lv_obj_t * roller, uint8_t row_cnt);






void lv_roller_set_auto_fit(lv_obj_t * roller, bool auto_fit);






static inline void lv_roller_set_anim_time(lv_obj_t * roller, uint16_t anim_time)
{
    lv_page_set_anim_time(roller, anim_time);
}
# 136 "./src/lv_widgets/lv_roller.h"
uint16_t lv_roller_get_selected(const lv_obj_t * roller);






uint16_t lv_roller_get_option_cnt(const lv_obj_t * roller);







void lv_roller_get_selected_str(const lv_obj_t * roller, char * buf, uint32_t buf_size);






lv_label_align_t lv_roller_get_align(const lv_obj_t * roller);






bool lv_roller_get_auto_fit(lv_obj_t * roller);






const char * lv_roller_get_options(const lv_obj_t * roller);






static inline uint16_t lv_roller_get_anim_time(const lv_obj_t * roller)
{
    return lv_page_get_anim_time(roller);
}
# 65 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_textarea.h" 1
# 38 "./src/lv_widgets/lv_textarea.h"
struct _silence_gcc_warning;






typedef struct {
    lv_page_ext_t page;

    lv_obj_t * label;
    char * placeholder_txt;
    lv_style_list_t style_placeholder;
    char * pwd_tmp;
    const char * accepted_chars;
    uint32_t max_length;
    uint16_t pwd_show_time;
    struct {
        lv_style_list_t style;
        lv_coord_t valid_x;

        uint32_t pos;

        uint16_t blink_time;
        lv_area_t area;
        uint32_t txt_byte_pos;
        uint8_t state : 1;
        uint8_t hidden : 1;
        uint8_t click_pos : 1;
    } cursor;






    uint8_t pwd_mode : 1;
    uint8_t one_line : 1;
} lv_textarea_ext_t;


enum {
    LV_TEXTAREA_PART_BG = LV_PAGE_PART_BG,
    LV_TEXTAREA_PART_SCROLLBAR = LV_PAGE_PART_SCROLLBAR,

    LV_TEXTAREA_PART_EDGE_FLASH = LV_PAGE_PART_EDGE_FLASH,

    LV_TEXTAREA_PART_CURSOR = _LV_PAGE_PART_VIRTUAL_LAST,
    LV_TEXTAREA_PART_PLACEHOLDER,
    _LV_TEXTAREA_PART_VIRTUAL_LAST,

    _LV_TEXTAREA_PART_REAL_LAST = _LV_PAGE_PART_REAL_LAST,
};
typedef uint8_t lv_textarea_style_t;
# 103 "./src/lv_widgets/lv_textarea.h"
lv_obj_t * lv_textarea_create(lv_obj_t * par, const lv_obj_t * copy);
# 115 "./src/lv_widgets/lv_textarea.h"
void lv_textarea_add_char(lv_obj_t * ta, uint32_t c);






void lv_textarea_add_text(lv_obj_t * ta, const char * txt);





void lv_textarea_del_char(lv_obj_t * ta);





void lv_textarea_del_char_forward(lv_obj_t * ta);
# 145 "./src/lv_widgets/lv_textarea.h"
void lv_textarea_set_text(lv_obj_t * ta, const char * txt);






void lv_textarea_set_placeholder_text(lv_obj_t * ta, const char * txt);
# 161 "./src/lv_widgets/lv_textarea.h"
void lv_textarea_set_cursor_pos(lv_obj_t * ta, int32_t pos);






void lv_textarea_set_cursor_hidden(lv_obj_t * ta, bool hide);






void lv_textarea_set_cursor_click_pos(lv_obj_t * ta, bool en);






void lv_textarea_set_pwd_mode(lv_obj_t * ta, bool en);






void lv_textarea_set_one_line(lv_obj_t * ta, bool en);
# 198 "./src/lv_widgets/lv_textarea.h"
void lv_textarea_set_text_align(lv_obj_t * ta, lv_label_align_t align);






void lv_textarea_set_accepted_chars(lv_obj_t * ta, const char * list);






void lv_textarea_set_max_length(lv_obj_t * ta, uint32_t num);
# 222 "./src/lv_widgets/lv_textarea.h"
void lv_textarea_set_insert_replace(lv_obj_t * ta, const char * txt);






static inline void lv_textarea_set_scrollbar_mode(lv_obj_t * ta, lv_scrollbar_mode_t mode)
{
    lv_page_set_scrollbar_mode(ta, mode);
}







static inline void lv_textarea_set_scroll_propagation(lv_obj_t * ta, bool en)
{
    lv_page_set_scroll_propagation(ta, en);
}






static inline void lv_textarea_set_edge_flash(lv_obj_t * ta, bool en)
{
    lv_page_set_edge_flash(ta, en);
}






void lv_textarea_set_text_sel(lv_obj_t * ta, bool en);






void lv_textarea_set_pwd_show_time(lv_obj_t * ta, uint16_t time);






void lv_textarea_set_cursor_blink_time(lv_obj_t * ta, uint16_t time);
# 285 "./src/lv_widgets/lv_textarea.h"
const char * lv_textarea_get_text(const lv_obj_t * ta);






const char * lv_textarea_get_placeholder_text(lv_obj_t * ta);






lv_obj_t * lv_textarea_get_label(const lv_obj_t * ta);






uint32_t lv_textarea_get_cursor_pos(const lv_obj_t * ta);






bool lv_textarea_get_cursor_hidden(const lv_obj_t * ta);






bool lv_textarea_get_cursor_click_pos(lv_obj_t * ta);






bool lv_textarea_get_pwd_mode(const lv_obj_t * ta);






bool lv_textarea_get_one_line(const lv_obj_t * ta);






const char * lv_textarea_get_accepted_chars(lv_obj_t * ta);






uint32_t lv_textarea_get_max_length(lv_obj_t * ta);






static inline lv_scrollbar_mode_t lv_textarea_get_scrollbar_mode(const lv_obj_t * ta)
{
    return lv_page_get_scrollbar_mode(ta);
}






static inline bool lv_textarea_get_scroll_propagation(lv_obj_t * ta)
{
    return lv_page_get_scroll_propagation(ta);
}






static inline bool lv_textarea_get_edge_flash(lv_obj_t * ta)
{
    return lv_page_get_edge_flash(ta);
}






bool lv_textarea_text_is_selected(const lv_obj_t * ta);






bool lv_textarea_get_text_sel_en(lv_obj_t * ta);






uint16_t lv_textarea_get_pwd_show_time(lv_obj_t * ta);






uint16_t lv_textarea_get_cursor_blink_time(lv_obj_t * ta);
# 416 "./src/lv_widgets/lv_textarea.h"
void lv_textarea_clear_selection(lv_obj_t * ta);





void lv_textarea_cursor_right(lv_obj_t * ta);





void lv_textarea_cursor_left(lv_obj_t * ta);





void lv_textarea_cursor_down(lv_obj_t * ta);





void lv_textarea_cursor_up(lv_obj_t * ta);
# 66 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_canvas.h" 1
# 32 "./src/lv_widgets/lv_canvas.h"
typedef struct {
    lv_img_ext_t img;

    lv_img_dsc_t dsc;
} lv_canvas_ext_t;


enum {
    LV_CANVAS_PART_MAIN,
};
typedef uint8_t lv_canvas_part_t;
# 54 "./src/lv_widgets/lv_canvas.h"
lv_obj_t * lv_canvas_create(lv_obj_t * par, const lv_obj_t * copy);
# 72 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_set_buffer(lv_obj_t * canvas, void * buf, lv_coord_t w, lv_coord_t h, lv_img_cf_t cf);
# 81 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_set_px(lv_obj_t * canvas, lv_coord_t x, lv_coord_t y, lv_color_t c);
# 93 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_set_palette(lv_obj_t * canvas, uint8_t id, lv_color_t c);
# 106 "./src/lv_widgets/lv_canvas.h"
lv_color_t lv_canvas_get_px(lv_obj_t * canvas, lv_coord_t x, lv_coord_t y);






lv_img_dsc_t * lv_canvas_get_img(lv_obj_t * canvas);
# 129 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_copy_buf(lv_obj_t * canvas, const void * to_copy, lv_coord_t x, lv_coord_t y, lv_coord_t w,
                        lv_coord_t h);
# 147 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_transform(lv_obj_t * canvas, lv_img_dsc_t * img, int16_t angle, uint16_t zoom, lv_coord_t offset_x,
                         lv_coord_t offset_y,
                         int32_t pivot_x, int32_t pivot_y, bool antialias);







void lv_canvas_blur_hor(lv_obj_t * canvas, const lv_area_t * area, uint16_t r);







void lv_canvas_blur_ver(lv_obj_t * canvas, const lv_area_t * area, uint16_t r);







void lv_canvas_fill_bg(lv_obj_t * canvas, lv_color_t color, lv_opa_t opa);
# 184 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_draw_rect(lv_obj_t * canvas, lv_coord_t x, lv_coord_t y, lv_coord_t w, lv_coord_t h,
                         const lv_draw_rect_dsc_t * rect_dsc);
# 197 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_draw_text(lv_obj_t * canvas, lv_coord_t x, lv_coord_t y, lv_coord_t max_w,
                         lv_draw_label_dsc_t * label_draw_dsc,
                         const char * txt, lv_label_align_t align);
# 209 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_draw_img(lv_obj_t * canvas, lv_coord_t x, lv_coord_t y, const void * src,
                        const lv_draw_img_dsc_t * img_draw_dsc);
# 219 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_draw_line(lv_obj_t * canvas, const lv_point_t points[], uint32_t point_cnt,
                         const lv_draw_line_dsc_t * line_draw_dsc);
# 229 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_draw_polygon(lv_obj_t * canvas, const lv_point_t points[], uint32_t point_cnt,
                            const lv_draw_rect_dsc_t * poly_draw_dsc);
# 242 "./src/lv_widgets/lv_canvas.h"
void lv_canvas_draw_arc(lv_obj_t * canvas, lv_coord_t x, lv_coord_t y, lv_coord_t r, int32_t start_angle,
                        int32_t end_angle, const lv_draw_line_dsc_t * arc_draw_dsc);
# 67 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_win.h" 1
# 53 "./src/lv_widgets/lv_win.h"
typedef struct {


    lv_obj_t * page;
    lv_obj_t * header;
    char * title_txt;
    lv_coord_t btn_w;
    uint8_t title_txt_align;
} lv_win_ext_t;


enum {
    LV_WIN_PART_BG = LV_OBJ_PART_MAIN,
    _LV_WIN_PART_VIRTUAL_LAST,
    LV_WIN_PART_HEADER = _LV_OBJ_PART_REAL_LAST,
    LV_WIN_PART_CONTENT_SCROLLABLE,
    LV_WIN_PART_SCROLLBAR,
    _LV_WIN_PART_REAL_LAST
};
# 83 "./src/lv_widgets/lv_win.h"
lv_obj_t * lv_win_create(lv_obj_t * par, const lv_obj_t * copy);





void lv_win_clean(lv_obj_t * win);
# 101 "./src/lv_widgets/lv_win.h"
lv_obj_t * lv_win_add_btn_right(lv_obj_t * win, const void * img_src);







lv_obj_t * lv_win_add_btn_left(lv_obj_t * win, const void * img_src);
# 120 "./src/lv_widgets/lv_win.h"
void lv_win_close_event_cb(lv_obj_t * btn, lv_event_t event);






void lv_win_set_title(lv_obj_t * win, const char * title);






void lv_win_set_header_height(lv_obj_t * win, lv_coord_t size);






void lv_win_set_btn_width(lv_obj_t * win, lv_coord_t width);







void lv_win_set_content_size(lv_obj_t * win, lv_coord_t w, lv_coord_t h);






void lv_win_set_layout(lv_obj_t * win, lv_layout_t layout);






void lv_win_set_scrollbar_mode(lv_obj_t * win, lv_scrollbar_mode_t sb_mode);






void lv_win_set_anim_time(lv_obj_t * win, uint16_t anim_time);






void lv_win_set_drag(lv_obj_t * win, bool en);






void lv_win_title_set_alignment(lv_obj_t * win, uint8_t alignment);
# 195 "./src/lv_widgets/lv_win.h"
const char * lv_win_get_title(const lv_obj_t * win);






lv_obj_t * lv_win_get_content(const lv_obj_t * win);






lv_coord_t lv_win_get_header_height(const lv_obj_t * win);






lv_coord_t lv_win_get_btn_width(lv_obj_t * win);







lv_obj_t * lv_win_get_from_btn(const lv_obj_t * ctrl_btn);






lv_layout_t lv_win_get_layout(lv_obj_t * win);






lv_scrollbar_mode_t lv_win_get_sb_mode(lv_obj_t * win);






uint16_t lv_win_get_anim_time(const lv_obj_t * win);






lv_coord_t lv_win_get_width(lv_obj_t * win);






static inline bool lv_win_get_drag(const lv_obj_t * win)
{
    return lv_obj_get_drag(win);
}





uint8_t lv_win_title_get_alignment(lv_obj_t * win);
# 280 "./src/lv_widgets/lv_win.h"
void lv_win_focus(lv_obj_t * win, lv_obj_t * obj, lv_anim_enable_t anim_en);






static inline void lv_win_scroll_hor(lv_obj_t * win, lv_coord_t dist)
{
    lv_win_ext_t * ext = (lv_win_ext_t *)lv_obj_get_ext_attr(win);
    lv_page_scroll_hor(ext->page, dist);
}





static inline void lv_win_scroll_ver(lv_obj_t * win, lv_coord_t dist)
{
    lv_win_ext_t * ext = (lv_win_ext_t *)lv_obj_get_ext_attr(win);
    lv_page_scroll_ver(ext->page, dist);
}
# 68 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_tabview.h" 1
# 42 "./src/lv_widgets/lv_tabview.h"
enum {
    LV_TABVIEW_TAB_POS_NONE,
    LV_TABVIEW_TAB_POS_TOP,
    LV_TABVIEW_TAB_POS_BOTTOM,
    LV_TABVIEW_TAB_POS_LEFT,
    LV_TABVIEW_TAB_POS_RIGHT
};
typedef uint8_t lv_tabview_btns_pos_t;


typedef struct {


    lv_obj_t * btns;
    lv_obj_t * indic;
    lv_obj_t * content;
    const char ** tab_name_ptr;
    lv_point_t point_last;
    uint16_t tab_cur;
    uint16_t tab_cnt;

    uint16_t anim_time;

    lv_tabview_btns_pos_t btns_pos : 3;
} lv_tabview_ext_t;

enum {
    LV_TABVIEW_PART_BG = LV_OBJ_PART_MAIN,
    _LV_TABVIEW_PART_VIRTUAL_LAST = _LV_OBJ_PART_VIRTUAL_LAST,

    LV_TABVIEW_PART_BG_SCROLLABLE = _LV_OBJ_PART_REAL_LAST,
    LV_TABVIEW_PART_TAB_BG,
    LV_TABVIEW_PART_TAB_BTN,
    LV_TABVIEW_PART_INDIC,
    _LV_TABVIEW_PART_REAL_LAST,
};
typedef uint8_t lv_tabview_part_t;
# 90 "./src/lv_widgets/lv_tabview.h"
lv_obj_t * lv_tabview_create(lv_obj_t * par, const lv_obj_t * copy);
# 102 "./src/lv_widgets/lv_tabview.h"
lv_obj_t * lv_tabview_add_tab(lv_obj_t * tabview, const char * name);





void lv_tabview_clean_tab(lv_obj_t * tab);
# 120 "./src/lv_widgets/lv_tabview.h"
void lv_tabview_set_tab_act(lv_obj_t * tabview, uint16_t id, lv_anim_enable_t anim);







void lv_tabview_set_tab_name(lv_obj_t * tabview, uint16_t id, char * name);






void lv_tabview_set_anim_time(lv_obj_t * tabview, uint16_t anim_time);






void lv_tabview_set_btns_pos(lv_obj_t * tabview, lv_tabview_btns_pos_t btns_pos);
# 153 "./src/lv_widgets/lv_tabview.h"
uint16_t lv_tabview_get_tab_act(const lv_obj_t * tabview);






uint16_t lv_tabview_get_tab_count(const lv_obj_t * tabview);






lv_obj_t * lv_tabview_get_tab(const lv_obj_t * tabview, uint16_t id);






uint16_t lv_tabview_get_anim_time(const lv_obj_t * tabview);





lv_tabview_btns_pos_t lv_tabview_get_btns_pos(const lv_obj_t * tabview);
# 69 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_tileview.h" 1
# 31 "./src/lv_widgets/lv_tileview.h"
typedef struct {
    lv_page_ext_t page;

    const lv_point_t * valid_pos;
    uint16_t valid_pos_cnt;

    uint16_t anim_time;

    lv_point_t act_id;
    uint8_t drag_top_en : 1;
    uint8_t drag_bottom_en : 1;
    uint8_t drag_left_en : 1;
    uint8_t drag_right_en : 1;
} lv_tileview_ext_t;


enum {
    LV_TILEVIEW_PART_BG = LV_PAGE_PART_BG,
    LV_TILEVIEW_PART_SCROLLBAR = LV_PAGE_PART_SCROLLBAR,
    LV_TILEVIEW_PART_EDGE_FLASH = LV_PAGE_PART_EDGE_FLASH,
    _LV_TILEVIEW_PART_VIRTUAL_LAST = _LV_PAGE_PART_VIRTUAL_LAST,
    _LV_TILEVIEW_PART_REAL_LAST = _LV_PAGE_PART_REAL_LAST
};
# 65 "./src/lv_widgets/lv_tileview.h"
lv_obj_t * lv_tileview_create(lv_obj_t * par, const lv_obj_t * copy);
# 76 "./src/lv_widgets/lv_tileview.h"
void lv_tileview_add_element(lv_obj_t * tileview, lv_obj_t * element);
# 89 "./src/lv_widgets/lv_tileview.h"
void lv_tileview_set_valid_positions(lv_obj_t * tileview, const lv_point_t valid_pos[], uint16_t valid_pos_cnt);
# 98 "./src/lv_widgets/lv_tileview.h"
void lv_tileview_set_tile_act(lv_obj_t * tileview, lv_coord_t x, lv_coord_t y, lv_anim_enable_t anim);






static inline void lv_tileview_set_edge_flash(lv_obj_t * tileview, bool en)
{
    lv_page_set_edge_flash(tileview, en);
}






static inline void lv_tileview_set_anim_time(lv_obj_t * tileview, uint16_t anim_time)
{
    lv_page_set_anim_time(tileview, anim_time);
}
# 129 "./src/lv_widgets/lv_tileview.h"
void lv_tileview_get_tile_act(lv_obj_t * tileview, lv_coord_t * x, lv_coord_t * y);





static inline bool lv_tileview_get_edge_flash(lv_obj_t * tileview)
{
    return lv_page_get_edge_flash(tileview);
}






static inline uint16_t lv_tileview_get_anim_time(lv_obj_t * tileview)
{
    return lv_page_get_anim_time(tileview);
}
# 70 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_msgbox.h" 1
# 47 "./src/lv_widgets/lv_msgbox.h"
typedef struct {
    lv_cont_ext_t bg;

    lv_obj_t * text;
    lv_obj_t * btnm;

    uint16_t anim_time;

} lv_msgbox_ext_t;


enum {
    LV_MSGBOX_PART_BG = LV_CONT_PART_MAIN,

    LV_MSGBOX_PART_BTN_BG = _LV_CONT_PART_REAL_LAST,
    LV_MSGBOX_PART_BTN,
};
typedef uint8_t lv_msgbox_style_t;
# 77 "./src/lv_widgets/lv_msgbox.h"
lv_obj_t * lv_msgbox_create(lv_obj_t * par, const lv_obj_t * copy);
# 89 "./src/lv_widgets/lv_msgbox.h"
void lv_msgbox_add_btns(lv_obj_t * mbox, const char * btn_mapaction[]);
# 100 "./src/lv_widgets/lv_msgbox.h"
void lv_msgbox_set_text(lv_obj_t * mbox, const char * txt);






void lv_msgbox_set_text_fmt(lv_obj_t * mbox, const char * fmt, ...);






void lv_msgbox_set_anim_time(lv_obj_t * mbox, uint16_t anim_time);






void lv_msgbox_start_auto_close(lv_obj_t * mbox, uint16_t delay);





void lv_msgbox_stop_auto_close(lv_obj_t * mbox);






void lv_msgbox_set_recolor(lv_obj_t * mbox, bool en);
# 145 "./src/lv_widgets/lv_msgbox.h"
const char * lv_msgbox_get_text(const lv_obj_t * mbox);







uint16_t lv_msgbox_get_active_btn(lv_obj_t * mbox);







const char * lv_msgbox_get_active_btn_text(lv_obj_t * mbox);






uint16_t lv_msgbox_get_anim_time(const lv_obj_t * mbox);






bool lv_msgbox_get_recolor(const lv_obj_t * mbox);







lv_obj_t * lv_msgbox_get_btnmatrix(lv_obj_t * mbox);
# 71 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_objmask.h" 1
# 31 "./src/lv_widgets/lv_objmask.h"
typedef struct {
    void * param;
} lv_objmask_mask_t;


typedef struct {
    lv_cont_ext_t cont;

    lv_ll_t mask_ll;

} lv_objmask_ext_t;


enum {
    LV_OBJMASK_PART_MAIN,
};
typedef uint8_t lv_objmask_part_t;
# 59 "./src/lv_widgets/lv_objmask.h"
lv_obj_t * lv_objmask_create(lv_obj_t * par, const lv_obj_t * copy);
# 71 "./src/lv_widgets/lv_objmask.h"
lv_objmask_mask_t * lv_objmask_add_mask(lv_obj_t * objmask, void * param);







void lv_objmask_update_mask(lv_obj_t * objmask, lv_objmask_mask_t * mask, void * param);







void lv_objmask_remove_mask(lv_obj_t * objmask, lv_objmask_mask_t * mask);
# 72 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_gauge.h" 1
# 26 "./src/lv_widgets/lv_gauge.h"
# 1 "./src/lv_widgets/lv_linemeter.h" 1
# 30 "./src/lv_widgets/lv_linemeter.h"
typedef struct {


    uint16_t scale_angle;
    uint16_t angle_ofs;
    uint16_t line_cnt;
    int32_t cur_value;
    int32_t min_value;
    int32_t max_value;
    uint8_t mirrored : 1;
} lv_linemeter_ext_t;


enum {
    LV_LINEMETER_PART_MAIN,
    _LV_LINEMETER_PART_VIRTUAL_LAST,
    _LV_LINEMETER_PART_REAL_LAST = _LV_OBJ_PART_REAL_LAST,
};
typedef uint8_t lv_linemeter_part_t;
# 61 "./src/lv_widgets/lv_linemeter.h"
lv_obj_t * lv_linemeter_create(lv_obj_t * par, const lv_obj_t * copy);
# 72 "./src/lv_widgets/lv_linemeter.h"
void lv_linemeter_set_value(lv_obj_t * lmeter, int32_t value);







void lv_linemeter_set_range(lv_obj_t * lmeter, int32_t min, int32_t max);







void lv_linemeter_set_scale(lv_obj_t * lmeter, uint16_t angle, uint16_t line_cnt);






void lv_linemeter_set_angle_offset(lv_obj_t * lmeter, uint16_t angle);






void lv_linemeter_set_mirror(lv_obj_t * lmeter, bool mirror);
# 113 "./src/lv_widgets/lv_linemeter.h"
int32_t lv_linemeter_get_value(const lv_obj_t * lmeter);






int32_t lv_linemeter_get_min_value(const lv_obj_t * lmeter);






int32_t lv_linemeter_get_max_value(const lv_obj_t * lmeter);






uint16_t lv_linemeter_get_line_count(const lv_obj_t * lmeter);






uint16_t lv_linemeter_get_scale_angle(const lv_obj_t * lmeter);






uint16_t lv_linemeter_get_angle_offset(lv_obj_t * lmeter);

void lv_linemeter_draw_scale(lv_obj_t * lmeter, const lv_area_t * clip_area, uint8_t part);






bool lv_linemeter_get_mirror(lv_obj_t * lmeter);
# 27 "./src/lv_widgets/lv_gauge.h" 2
# 38 "./src/lv_widgets/lv_gauge.h"
typedef void (*lv_gauge_format_cb_t)(lv_obj_t * gauge, char * buf, int bufsize, int32_t value);


typedef struct {
    lv_linemeter_ext_t lmeter;

    int32_t * values;
    const lv_color_t * needle_colors;
    const void * needle_img;
    lv_point_t needle_img_pivot;
    lv_style_list_t style_needle;
    lv_style_list_t style_strong;
    uint8_t needle_count;
    uint8_t label_count;
    lv_gauge_format_cb_t format_cb;
} lv_gauge_ext_t;


enum {
    LV_GAUGE_PART_MAIN = LV_LINEMETER_PART_MAIN,
    LV_GAUGE_PART_MAJOR = _LV_LINEMETER_PART_VIRTUAL_LAST,
    LV_GAUGE_PART_NEEDLE,
    _LV_GAUGE_PART_VIRTUAL_LAST = _LV_LINEMETER_PART_VIRTUAL_LAST,
    _LV_GAUGE_PART_REAL_LAST = _LV_LINEMETER_PART_REAL_LAST,
};
typedef uint8_t lv_gauge_style_t;
# 75 "./src/lv_widgets/lv_gauge.h"
lv_obj_t * lv_gauge_create(lv_obj_t * par, const lv_obj_t * copy);
# 87 "./src/lv_widgets/lv_gauge.h"
void lv_gauge_set_needle_count(lv_obj_t * gauge, uint8_t needle_cnt, const lv_color_t colors[]);







void lv_gauge_set_value(lv_obj_t * gauge, uint8_t needle_id, int32_t value);







static inline void lv_gauge_set_range(lv_obj_t * gauge, int32_t min, int32_t max)
{
    lv_linemeter_set_range(gauge, min, max);
}






static inline void lv_gauge_set_critical_value(lv_obj_t * gauge, int32_t value)
{
    lv_linemeter_set_value(gauge, value - 1);
}
# 127 "./src/lv_widgets/lv_gauge.h"
void lv_gauge_set_scale(lv_obj_t * gauge, uint16_t angle, uint8_t line_cnt, uint8_t label_cnt);






static inline void lv_gauge_set_angle_offset(lv_obj_t * gauge, uint16_t angle)
{
    lv_linemeter_set_angle_offset(gauge, angle);
}
# 148 "./src/lv_widgets/lv_gauge.h"
void lv_gauge_set_needle_img(lv_obj_t * gauge, const void * img, lv_coord_t pivot_x, lv_coord_t pivot_y);






void lv_gauge_set_formatter_cb(lv_obj_t * gauge, lv_gauge_format_cb_t format_cb);
# 167 "./src/lv_widgets/lv_gauge.h"
int32_t lv_gauge_get_value(const lv_obj_t * gauge, uint8_t needle);






uint8_t lv_gauge_get_needle_count(const lv_obj_t * gauge);






static inline int32_t lv_gauge_get_min_value(const lv_obj_t * lmeter)
{
    return lv_linemeter_get_min_value(lmeter);
}






static inline int32_t lv_gauge_get_max_value(const lv_obj_t * lmeter)
{
    return lv_linemeter_get_max_value(lmeter);
}






static inline int32_t lv_gauge_get_critical_value(const lv_obj_t * gauge)
{
    return lv_linemeter_get_value(gauge);
}






uint8_t lv_gauge_get_label_count(const lv_obj_t * gauge);






static inline uint16_t lv_gauge_get_line_count(const lv_obj_t * gauge)
{
    return lv_linemeter_get_line_count(gauge);
}






static inline uint16_t lv_gauge_get_scale_angle(const lv_obj_t * gauge)
{
    return lv_linemeter_get_scale_angle(gauge);
}






static inline uint16_t lv_gauge_get_angle_offset(lv_obj_t * gauge)
{
    return lv_linemeter_get_angle_offset(gauge);
}







const void * lv_gauge_get_needle_img(lv_obj_t * gauge);






lv_coord_t lv_gauge_get_needle_img_pivot_x(lv_obj_t * gauge);






lv_coord_t lv_gauge_get_needle_img_pivot_y(lv_obj_t * gauge);
# 73 "lvgl.h" 2

# 1 "./src/lv_widgets/lv_switch.h" 1
# 36 "./src/lv_widgets/lv_switch.h"
typedef struct {
    lv_bar_ext_t bar;

    lv_style_list_t style_knob;
} lv_switch_ext_t;




enum {
    LV_SWITCH_PART_BG = LV_BAR_PART_BG,
    LV_SWITCH_PART_INDIC = LV_BAR_PART_INDIC,
    LV_SWITCH_PART_KNOB = _LV_BAR_PART_VIRTUAL_LAST,
    _LV_SWITCH_PART_VIRTUAL_LAST
};

typedef uint8_t lv_switch_part_t;
# 64 "./src/lv_widgets/lv_switch.h"
lv_obj_t * lv_switch_create(lv_obj_t * par, const lv_obj_t * copy);
# 75 "./src/lv_widgets/lv_switch.h"
void lv_switch_on(lv_obj_t * sw, lv_anim_enable_t anim);






void lv_switch_off(lv_obj_t * sw, lv_anim_enable_t anim);







bool lv_switch_toggle(lv_obj_t * sw, lv_anim_enable_t anim);







static inline void lv_switch_set_anim_time(lv_obj_t * sw, uint16_t anim_time)
{
    lv_bar_set_anim_time(sw, anim_time);
}
# 112 "./src/lv_widgets/lv_switch.h"
static inline bool lv_switch_get_state(const lv_obj_t * sw)
{
    return lv_bar_get_value(sw) == 1 ? 1 : 0;
}






static inline uint16_t lv_switch_get_anim_time(const lv_obj_t * sw)
{
    return lv_bar_get_anim_time(sw);
}
# 75 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_arc.h" 1
# 30 "./src/lv_widgets/lv_arc.h"
enum {
    LV_ARC_TYPE_NORMAL,
    LV_ARC_TYPE_SYMMETRIC,
    LV_ARC_TYPE_REVERSE
};
typedef uint8_t lv_arc_type_t;


typedef struct {

    uint16_t rotation_angle;
    uint16_t arc_angle_start;
    uint16_t arc_angle_end;
    uint16_t bg_angle_start;
    uint16_t bg_angle_end;
    lv_style_list_t style_arc;
    lv_style_list_t style_knob;

    int16_t cur_value;
    int16_t min_value;
    int16_t max_value;
    uint16_t dragging : 1;
    uint16_t type : 2;
    uint16_t adjustable : 1;
    uint16_t min_close : 1;
    uint16_t chg_rate;
    uint32_t last_tick;
    int16_t last_angle;
} lv_arc_ext_t;


enum {
    LV_ARC_PART_BG = LV_OBJ_PART_MAIN,
    LV_ARC_PART_INDIC,
    LV_ARC_PART_KNOB,
    _LV_ARC_PART_VIRTUAL_LAST,
    _LV_ARC_PART_REAL_LAST = _LV_OBJ_PART_REAL_LAST,
};
typedef uint8_t lv_arc_part_t;
# 80 "./src/lv_widgets/lv_arc.h"
lv_obj_t * lv_arc_create(lv_obj_t * par, const lv_obj_t * copy);
# 95 "./src/lv_widgets/lv_arc.h"
void lv_arc_set_start_angle(lv_obj_t * arc, uint16_t start);






void lv_arc_set_end_angle(lv_obj_t * arc, uint16_t end);







void lv_arc_set_angles(lv_obj_t * arc, uint16_t start, uint16_t end);






void lv_arc_set_bg_start_angle(lv_obj_t * arc, uint16_t start);






void lv_arc_set_bg_end_angle(lv_obj_t * arc, uint16_t end);







void lv_arc_set_bg_angles(lv_obj_t * arc, uint16_t start, uint16_t end);






void lv_arc_set_rotation(lv_obj_t * arc, uint16_t rotation_angle);






void lv_arc_set_type(lv_obj_t * arc, lv_arc_type_t type);






void lv_arc_set_value(lv_obj_t * arc, int16_t value);







void lv_arc_set_range(lv_obj_t * arc, int16_t min, int16_t max);







void lv_arc_set_chg_rate(lv_obj_t * arc, uint16_t threshold);






void lv_arc_set_adjustable(lv_obj_t * arc, bool adjustable);
# 187 "./src/lv_widgets/lv_arc.h"
uint16_t lv_arc_get_angle_start(lv_obj_t * arc);






uint16_t lv_arc_get_angle_end(lv_obj_t * arc);






uint16_t lv_arc_get_bg_angle_start(lv_obj_t * arc);






uint16_t lv_arc_get_bg_angle_end(lv_obj_t * arc);






lv_arc_type_t lv_arc_get_type(const lv_obj_t * arc);






int16_t lv_arc_get_value(const lv_obj_t * arc);






int16_t lv_arc_get_min_value(const lv_obj_t * arc);






int16_t lv_arc_get_max_value(const lv_obj_t * arc);






bool lv_arc_is_dragged(const lv_obj_t * arc);






bool lv_arc_get_adjustable(lv_obj_t * arc);
# 76 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_spinner.h" 1
# 44 "./src/lv_widgets/lv_spinner.h"
enum {
    LV_SPINNER_TYPE_SPINNING_ARC,
    LV_SPINNER_TYPE_FILLSPIN_ARC,
    LV_SPINNER_TYPE_CONSTANT_ARC,
};
typedef uint8_t lv_spinner_type_t;




enum {
    LV_SPINNER_DIR_FORWARD,
    LV_SPINNER_DIR_BACKWARD,
};
typedef uint8_t lv_spinner_dir_t;


typedef struct {
    lv_arc_ext_t arc;

    lv_anim_value_t arc_length;
    uint16_t time;
    lv_spinner_type_t anim_type : 2;
    lv_spinner_dir_t anim_dir : 1;
} lv_spinner_ext_t;


enum {
    LV_SPINNER_PART_BG = LV_ARC_PART_BG,
    LV_SPINNER_PART_INDIC = LV_ARC_PART_INDIC,
    _LV_SPINNER_PART_VIRTUAL_LAST,

    _LV_SPINNER_PART_REAL_LAST = _LV_ARC_PART_REAL_LAST,
};
typedef uint8_t lv_spinner_style_t;
# 91 "./src/lv_widgets/lv_spinner.h"
lv_obj_t * lv_spinner_create(lv_obj_t * par, const lv_obj_t * copy);
# 102 "./src/lv_widgets/lv_spinner.h"
void lv_spinner_set_arc_length(lv_obj_t * spinner, lv_anim_value_t deg);






void lv_spinner_set_spin_time(lv_obj_t * spinner, uint16_t time);
# 120 "./src/lv_widgets/lv_spinner.h"
void lv_spinner_set_type(lv_obj_t * spinner, lv_spinner_type_t type);






void lv_spinner_set_dir(lv_obj_t * spinner, lv_spinner_dir_t dir);
# 137 "./src/lv_widgets/lv_spinner.h"
lv_anim_value_t lv_spinner_get_arc_length(const lv_obj_t * spinner);





uint16_t lv_spinner_get_spin_time(const lv_obj_t * spinner);






lv_spinner_type_t lv_spinner_get_type(lv_obj_t * spinner);






lv_spinner_dir_t lv_spinner_get_dir(lv_obj_t * spinner);
# 168 "./src/lv_widgets/lv_spinner.h"
void lv_spinner_anim_cb(void * ptr, lv_anim_value_t val);
# 77 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_calendar.h" 1
# 33 "./src/lv_widgets/lv_calendar.h"
typedef struct {
    uint16_t year;
    int8_t month;
    int8_t day;
} lv_calendar_date_t;


typedef struct {


    lv_calendar_date_t today;
    lv_calendar_date_t showed_date;
    lv_calendar_date_t * highlighted_dates;

    int8_t btn_pressing;
    uint16_t highlighted_dates_num;
    lv_calendar_date_t pressed_date;
    const char ** day_names;
    const char ** month_names;


    lv_style_list_t style_header;
    lv_style_list_t style_day_names;
    lv_style_list_t style_date_nums;
} lv_calendar_ext_t;


enum {
    LV_CALENDAR_PART_BG,
    LV_CALENDAR_PART_HEADER,
    LV_CALENDAR_PART_DAY_NAMES,
    LV_CALENDAR_PART_DATE,
};
typedef uint8_t lv_calendar_part_t;
# 78 "./src/lv_widgets/lv_calendar.h"
lv_obj_t * lv_calendar_create(lv_obj_t * par, const lv_obj_t * copy);
# 94 "./src/lv_widgets/lv_calendar.h"
void lv_calendar_set_today_date(lv_obj_t * calendar, lv_calendar_date_t * today);







void lv_calendar_set_showed_date(lv_obj_t * calendar, lv_calendar_date_t * showed);
# 111 "./src/lv_widgets/lv_calendar.h"
void lv_calendar_set_highlighted_dates(lv_obj_t * calendar, lv_calendar_date_t highlighted[], uint16_t date_num);
# 120 "./src/lv_widgets/lv_calendar.h"
void lv_calendar_set_day_names(lv_obj_t * calendar, const char ** day_names);
# 129 "./src/lv_widgets/lv_calendar.h"
void lv_calendar_set_month_names(lv_obj_t * calendar, const char ** month_names);
# 140 "./src/lv_widgets/lv_calendar.h"
lv_calendar_date_t * lv_calendar_get_today_date(const lv_obj_t * calendar);






lv_calendar_date_t * lv_calendar_get_showed_date(const lv_obj_t * calendar);







lv_calendar_date_t * lv_calendar_get_pressed_date(const lv_obj_t * calendar);






lv_calendar_date_t * lv_calendar_get_highlighted_dates(const lv_obj_t * calendar);






uint16_t lv_calendar_get_highlighted_dates_num(const lv_obj_t * calendar);






const char ** lv_calendar_get_day_names(const lv_obj_t * calendar);






const char ** lv_calendar_get_month_names(const lv_obj_t * calendar);
# 192 "./src/lv_widgets/lv_calendar.h"
uint8_t lv_calendar_get_day_of_week(uint32_t year, uint32_t month, uint32_t day);
# 78 "lvgl.h" 2
# 1 "./src/lv_widgets/lv_spinbox.h" 1
# 38 "./src/lv_widgets/lv_spinbox.h"
typedef struct {
    lv_textarea_ext_t ta;

    int32_t value;
    int32_t range_max;
    int32_t range_min;
    int32_t step;
    uint8_t rollover : 1;
    uint16_t digit_count : 4;
    uint16_t dec_point_pos : 4;
    uint16_t digit_padding_left : 4;
} lv_spinbox_ext_t;


enum {
    LV_SPINBOX_PART_BG = LV_TEXTAREA_PART_BG,
    LV_SPINBOX_PART_CURSOR = LV_TEXTAREA_PART_CURSOR,
    _LV_SPINBOX_PART_VIRTUAL_LAST = _LV_TEXTAREA_PART_VIRTUAL_LAST,
    _LV_SPINBOX_PART_REAL_LAST = _LV_TEXTAREA_PART_REAL_LAST,
};
typedef uint8_t lv_spinbox_part_t;
# 70 "./src/lv_widgets/lv_spinbox.h"
lv_obj_t * lv_spinbox_create(lv_obj_t * par, const lv_obj_t * copy);
# 81 "./src/lv_widgets/lv_spinbox.h"
void lv_spinbox_set_rollover(lv_obj_t * spinbox, bool b);






void lv_spinbox_set_value(lv_obj_t * spinbox, int32_t i);
# 97 "./src/lv_widgets/lv_spinbox.h"
void lv_spinbox_set_digit_format(lv_obj_t * spinbox, uint8_t digit_count, uint8_t separator_position);






void lv_spinbox_set_step(lv_obj_t * spinbox, uint32_t step);







void lv_spinbox_set_range(lv_obj_t * spinbox, int32_t range_min, int32_t range_max);






void lv_spinbox_set_padding_left(lv_obj_t * spinbox, uint8_t padding);
# 129 "./src/lv_widgets/lv_spinbox.h"
bool lv_spinbox_get_rollover(lv_obj_t * spinbox);






int32_t lv_spinbox_get_value(lv_obj_t * spinbox);






static inline int32_t lv_spinbox_get_step(lv_obj_t * spinbox)
{
    lv_spinbox_ext_t * ext = (lv_spinbox_ext_t *)lv_obj_get_ext_attr(spinbox);

    return ext->step;
}
# 158 "./src/lv_widgets/lv_spinbox.h"
void lv_spinbox_step_next(lv_obj_t * spinbox);





void lv_spinbox_step_prev(lv_obj_t * spinbox);





void lv_spinbox_increment(lv_obj_t * spinbox);





void lv_spinbox_decrement(lv_obj_t * spinbox);
# 79 "lvgl.h" 2

# 1 "./src/lv_draw/lv_img_cache.h" 1
# 31 "./src/lv_draw/lv_img_cache.h"
typedef struct {
    lv_img_decoder_dsc_t dec_dsc;




    int32_t life;
} lv_img_cache_entry_t;
# 52 "./src/lv_draw/lv_img_cache.h"
lv_img_cache_entry_t * _lv_img_cache_open(const void * src, lv_color_t color);







void lv_img_cache_set_size(uint16_t new_slot_num);






void lv_img_cache_invalidate_src(const void * src);
# 81 "lvgl.h" 2

# 1 "./src/lv_api_map.h" 1
# 16 "./src/lv_api_map.h"
# 1 "./src/lv_misc/../../lvgl.h" 1
# 17 "./src/lv_api_map.h" 2
# 35 "./src/lv_api_map.h"
static inline void lv_task_once(lv_task_t * task)
{
    lv_task_set_repeat_count(task, 1);
}
# 54 "./src/lv_api_map.h"
static inline void lv_dropdown_set_draw_arrow(lv_obj_t * ddlist, bool en)
{
    if(en) lv_dropdown_set_symbol(ddlist, "\xef\x81\xb8");
    else lv_dropdown_set_symbol(ddlist, 0);
}

static inline bool lv_dropdown_get_draw_arrow(lv_obj_t * ddlist)
{
    if(lv_dropdown_get_symbol(ddlist)) return 1;
    else return 0;
}
# 79 "./src/lv_api_map.h"
static inline void lv_bar_set_sym(lv_obj_t * bar, bool en)
{
    if(en)
        lv_bar_set_type(bar, LV_BAR_TYPE_SYMMETRICAL);
    else
        lv_bar_set_type(bar, LV_BAR_TYPE_NORMAL);
}







static inline bool lv_bar_get_sym(lv_obj_t * bar)
{
    return lv_bar_get_type(bar) == LV_BAR_TYPE_SYMMETRICAL;
}
# 115 "./src/lv_api_map.h"
static inline void lv_slider_set_sym(lv_obj_t * slider, bool en)
{
    lv_bar_set_sym(slider, en);
}







static inline bool lv_slider_get_sym(lv_obj_t * slider)
{
    return lv_bar_get_sym(slider);
}
# 141 "./src/lv_api_map.h"
static inline void lv_roller_set_fix_width(lv_obj_t * roller, lv_coord_t w)
{
    lv_roller_set_auto_fit(roller, 0);
    lv_obj_set_width(roller, w);
}
# 159 "./src/lv_api_map.h"
static inline void lv_page_set_scrlbar_mode(lv_obj_t * page, lv_scrollbar_mode_t sb_mode)
{
    lv_page_set_scrollbar_mode(page, sb_mode);
}
static inline lv_scrollbar_mode_t lv_page_get_scrlbar_mode(lv_obj_t * page)
{
    return lv_page_get_scrollbar_mode(page);
}

static inline lv_obj_t * lv_page_get_scrl(lv_obj_t * page)
{
    return lv_page_get_scrollable(page);
}
# 187 "./src/lv_api_map.h"
static inline lv_obj_t * lv_win_add_btn(lv_obj_t * win, const void * img_src)
{
    return lv_win_add_btn_right(win, img_src);
}




static inline void lv_chart_set_range(lv_obj_t * chart, lv_coord_t ymin, lv_coord_t ymax)
{
    lv_chart_set_y_range(chart, LV_CHART_AXIS_PRIMARY_Y, ymin, ymax);
}

static inline void lv_chart_clear_serie(lv_obj_t * chart, lv_chart_series_t * series)
{
    lv_chart_clear_series(chart, series);
}



static inline void lv_obj_align_origo(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t x_ofs,
                                      lv_coord_t y_ofs)
{
    lv_obj_align_mid(obj, base, align, x_ofs, y_ofs);
}

static inline void lv_obj_align_origo_x(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t x_ofs)
{
    lv_obj_align_mid_y(obj, base, align, x_ofs);
}

static inline void lv_obj_align_origo_y(lv_obj_t * obj, const lv_obj_t * base, lv_align_t align, lv_coord_t y_ofs)
{
    lv_obj_align_mid_y(obj, base, align, y_ofs);
}
# 83 "./src/lv_misc/../../lvgl.h" 2
# 127 "./src/lv_misc/../../lvgl.h"
static inline int lv_version_major(void)
{
    return 7;
}

static inline int lv_version_minor(void)
{
    return 11;
}

static inline int lv_version_patch(void)
{
    return 0;
}

static inline const char *lv_version_info(void)
{
    return "";
}
