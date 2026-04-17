/*
@module  fft
@summary 快速傅里叶变换（FFT/IFFT），支持 float32 与 q15 定点内核
@version 0.3
@date    2025.08
@demo    fft
@tag     LUAT_USE_FFT
@usage
-- 模块通常作为内置库，无需 require，直接调用
-- 示例见各 API 注释以及仓库 demo/test 脚本

-- 支持的点数范围：
-- 输入点数N，要求为2的幂次方，且N < 65536
-- 格式支持：Lua数组 或 zbuff输入
-- 推荐范围：N ≤ 16384（已验证稳定运行）

-- 性能测试结果（实测数据）：
-- Air780EHV平台：
--   2048点：F32=23ms, Q15=10ms（Q15快2.3倍）
--   16384点：F32=240ms, Q15=110ms（Q15快2.2倍）
-- Air8101平台(有硬件浮点加速)：
--   2048点：F32=6ms, Q15=5ms（性能相近）
--   16384点：F32=78ms, Q15=86ms（F32略快）

-- 平台建议：
-- Air780EHV/Air780EPM：推荐使用Q15路径，性能提升显著
-- Air8101：小规模FFT两种都可，大规模FFT建议F32路径
-- 内存受限场景：优先选择Q15路径（内存需求减半）
-- 高精度场景：优先选择F32路径
*/
#include "luat_base.h"
#include "luat_mem.h"

#include <math.h>
#include <string.h>

#include "fft_core.h"

#define LUAT_LOG_TAG "fft"
#include "luat_log.h"

#include "luat_conf_bsp.h"
#include "luat_zbuff.h"
#include "rotable2.h"
// Q15 内核头文件
#include "fft_core_q15.h"

// Q15 输入格式枚举（避免在循环内 strcmp）
enum {
    INPUT_FMT_F32 = 0,
    INPUT_FMT_U12,
    INPUT_FMT_U16,
    INPUT_FMT_S16
};

// 将输入格式字符串转为枚举
static int parse_input_format(const char* s)
{
    if (!s || strcmp(s, "f32") == 0) return INPUT_FMT_F32;
    if (strcmp(s, "u12") == 0) return INPUT_FMT_U12;
    if (strcmp(s, "u16") == 0) return INPUT_FMT_U16;
    if (strcmp(s, "s16") == 0) return INPUT_FMT_S16;
    return INPUT_FMT_F32;
}

// helper: read float array from lua table (1-based)
static int read_lua_array_float(lua_State* L, int idx, float* out, int n)
{
    for (int i = 0; i < n; i++) {
        lua_rawgeti(L, idx, i + 1);
        if (!lua_isnumber(L, -1)) {
            lua_pop(L, 1);
            return -1;
        }
        out[i] = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
    return 0;
}

// helper: write float array into lua table (1-based)
static void write_lua_array_float(lua_State* L, float* a, int n)
{
    lua_createtable(L, n, 0);
    for (int i = 0; i < n; i++) {
        lua_pushnumber(L, a[i]);
        lua_rawseti(L, -2, i + 1);
    }
}

// FFT/IFFT 公共参数结构体
typedef struct {
    float *r, *im, *Wc, *Ws;
    int r_free, im_free, wc_free, ws_free;
    int N;
    int use_q15;
    int input_fmt; // INPUT_FMT_xxx 枚举
} fft_args_t;

// 释放 fft_args_t 中动态分配的内存
static void fft_args_cleanup(fft_args_t* a)
{
    if (a->r_free && a->r)   luat_heap_free(a->r);
    if (a->im_free && a->im) luat_heap_free(a->im);
    if (a->wc_free && a->Wc) luat_heap_free(a->Wc);
    if (a->ws_free && a->Ws) luat_heap_free(a->Ws);
    a->r = a->im = a->Wc = a->Ws = NULL;
}

// 解析 fft.run / fft.ifft 的公共参数
// 参数布局: (real, imag, N, Wc, Ws [, opts])
// 返回 0 成功, <0 失败（已设置 lua error）
static int fft_parse_args(lua_State* L, fft_args_t* a)
{
    memset(a, 0, sizeof(*a));
    
    // 参数数量检查
    int top = lua_gettop(L);
    if (top < 5) {
        LLOGE("fft_parse_args: insufficient arguments, expected at least 5, got %d", top);
        return luaL_error(L, "fft requires at least 5 arguments: real, imag, N, Wc, Ws");
    }
    
    // 参数3: N - 必须是整数
    if (!lua_isinteger(L, 3)) {
        LLOGE("fft_parse_args: parameter N must be integer, got %s", lua_typename(L, lua_type(L, 3)));
        return luaL_error(L, "N must be integer");
    }
    
    a->N = luaL_checkinteger(L, 3);
    
    // N的范围检查
    if (a->N <= 1) {
        LLOGE("fft_parse_args: N must be greater than 1, got %d", a->N);
        return luaL_error(L, "N must be greater than 1");
    }
    
    // N必须是2的幂次
    if (a->N & (a->N - 1)) {
        LLOGE("fft_parse_args: N must be power of 2, got %d", a->N);
        return luaL_error(L, "N must be power of 2");
    }
    
    // N上限检查（防止内存溢出）
    if (a->N > 65536) {
        LLOGE("fft_parse_args: N exceeds maximum allowed value 65536, got %d", a->N);
        return luaL_error(L, "N must not exceed 65536");
    }

    int N = a->N;
    luat_zbuff_t* zb;

    // 参数1: real - 必须是zbuff或table，不能为nil
    int real_type = lua_type(L, 1);
    if (real_type == LUA_TNIL) {
        LLOGE("fft_parse_args: real parameter cannot be nil");
        return luaL_error(L, "real must be zbuff or table, not nil");
    }
    if (real_type != LUA_TTABLE) {
        zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
        if (!zb) {
            LLOGE("fft_parse_args: real parameter must be zbuff or table, got %s", 
                  lua_typename(L, real_type));
            return luaL_error(L, "real must be zbuff or table");
        }
        a->r = (float*)zb->addr;
    } else {
        // table类型
        a->r = luat_heap_malloc(sizeof(float) * N);
        a->r_free = 1;
        if (!a->r) { 
            LLOGE("fft_parse_args: failed to allocate memory for real (size=%zu)", 
                  sizeof(float) * N);
            fft_args_cleanup(a); 
            return luaL_error(L, "no memory"); 
        }
        if (read_lua_array_float(L, 1, a->r, N)) {
            LLOGE("fft_parse_args: failed to read real array, table must contain %d numbers", N);
            fft_args_cleanup(a); 
            return luaL_error(L, "real table must contain %d numbers", N);
        }
    }
    // 参数2: imag - 必须是zbuff、table或nil
    int imag_type = lua_type(L, 2);
    if (imag_type != LUA_TNIL && imag_type != LUA_TTABLE) {
        zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
        if (!zb) {
            LLOGE("fft_parse_args: imag parameter must be zbuff, table or nil, got %s", 
                  lua_typename(L, imag_type));
            fft_args_cleanup(a);
            return luaL_error(L, "imag must be zbuff, table or nil");
        }
        a->im = (float*)zb->addr;
    } else if (imag_type == LUA_TNIL) {
        // 当 imag 为 nil 时，分配内存并初始化为 0
        a->im = luat_heap_malloc(sizeof(float) * N);
        a->im_free = 1;
        if (!a->im) { 
            LLOGE("fft_parse_args: failed to allocate memory for imag (size=%zu)", 
                  sizeof(float) * N);
            fft_args_cleanup(a); 
            return luaL_error(L, "no memory"); 
        }
        memset(a->im, 0, sizeof(float) * N);
    } else {
        // table类型
        a->im = luat_heap_malloc(sizeof(float) * N);
        a->im_free = 1;
        if (!a->im) { 
            LLOGE("fft_parse_args: failed to allocate memory for imag (size=%zu)", 
                  sizeof(float) * N);
            fft_args_cleanup(a); 
            return luaL_error(L, "no memory"); 
        }
        if (read_lua_array_float(L, 2, a->im, N)) {
            LLOGE("fft_parse_args: failed to read imag array, table must contain %d numbers", N);
            fft_args_cleanup(a); 
            return luaL_error(L, "imag table must contain %d numbers", N);
        }
    }
    
    // 参数4: Wc - 必须是zbuff或table
    int wc_type = lua_type(L, 4);
    if (wc_type != LUA_TTABLE) {
        zb = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
        if (!zb) {
            LLOGE("fft_parse_args: Wc parameter must be zbuff or table, got %s", 
                  lua_typename(L, wc_type));
            fft_args_cleanup(a);
            return luaL_error(L, "Wc must be zbuff or table");
        }
        a->Wc = (float*)zb->addr;
    } else {
        a->Wc = luat_heap_malloc(sizeof(float) * (N / 2));
        a->wc_free = 1;
        if (!a->Wc) { 
            LLOGE("fft_parse_args: failed to allocate memory for Wc (size=%zu)", 
                  sizeof(float) * (N / 2));
            fft_args_cleanup(a); 
            return luaL_error(L, "no memory"); 
        }
        if (read_lua_array_float(L, 4, a->Wc, N / 2)) {
            LLOGE("fft_parse_args: failed to read Wc array, table must contain %d numbers", N / 2);
            fft_args_cleanup(a); 
            return luaL_error(L, "Wc table must contain %d numbers", N / 2);
        }
    }
    
    // 参数5: Ws - 必须是zbuff或table
    int ws_type = lua_type(L, 5);
    if (ws_type != LUA_TTABLE) {
        zb = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
        if (!zb) {
            LLOGE("fft_parse_args: Ws parameter must be zbuff or table, got %s", 
                  lua_typename(L, ws_type));
            fft_args_cleanup(a);
            return luaL_error(L, "Ws must be zbuff or table");
        }
        a->Ws = (float*)zb->addr;
    } else {
        a->Ws = luat_heap_malloc(sizeof(float) * (N / 2));
        a->ws_free = 1;
        if (!a->Ws) { 
            LLOGE("fft_parse_args: failed to allocate memory for Ws (size=%zu)", 
                  sizeof(float) * (N / 2));
            fft_args_cleanup(a); 
            return luaL_error(L, "no memory"); 
        }
        if (read_lua_array_float(L, 5, a->Ws, N / 2)) {
            LLOGE("fft_parse_args: failed to read Ws array, table must contain %d numbers", N / 2);
            fft_args_cleanup(a); 
            return luaL_error(L, "Ws table must contain %d numbers", N / 2);
        }
    }

    // 读取 opts 参数
    const char* core = "f32";
    const char* input_format = "f32";
    if (top >= 6) {
        if (!lua_istable(L, 6)) {
            LLOGE("fft_parse_args: opts parameter must be table, got %s", 
                  lua_typename(L, lua_type(L, 6)));
            fft_args_cleanup(a);
            return luaL_error(L, "opts must be table");
        }
        lua_getfield(L, 6, "core");
        if (!lua_isnil(L, -1)) {
            if (!lua_isstring(L, -1)) {
                LLOGE("fft_parse_args: opts.core must be string, got %s", 
                      lua_typename(L, lua_type(L, -1)));
                lua_pop(L, 1);
                fft_args_cleanup(a);
                return luaL_error(L, "opts.core must be string");
            }
            core = luaL_checkstring(L, -1);
        }
        lua_pop(L, 1);
        
        lua_getfield(L, 6, "input_format");
        if (!lua_isnil(L, -1)) {
            if (!lua_isstring(L, -1)) {
                LLOGE("fft_parse_args: opts.input_format must be string, got %s", 
                      lua_typename(L, lua_type(L, -1)));
                lua_pop(L, 1);
                fft_args_cleanup(a);
                return luaL_error(L, "opts.input_format must be string");
            }
            input_format = luaL_checkstring(L, -1);
        }
        lua_pop(L, 1);
    }
    
    // 验证core参数值
    if (core && strcmp(core, "f32") != 0 && strcmp(core, "q15") != 0) {
        LLOGE("fft_parse_args: invalid core value '%s', must be 'f32' or 'q15'", core);
        fft_args_cleanup(a);
        return luaL_error(L, "opts.core must be 'f32' or 'q15'");
    }
    
    a->use_q15 = (core && strcmp(core, "q15") == 0);
    a->input_fmt = parse_input_format(input_format);
    
    LLOGD("fft_parse_args: success - N=%d, use_q15=%d, input_fmt=%d", 
          a->N, a->use_q15, a->input_fmt);
    return 0;
}

// 将整数 zbuff 数据原地转换为 Q15 有符号格式
static void convert_integer_to_q15(int16_t* data, int N, int input_fmt)
{
    uint16_t* u16 = (uint16_t*)data;
    for (int i = 0; i < N; i++) {
        int32_t v;
        uint16_t u = u16[i];
        switch (input_fmt) {
        case INPUT_FMT_U12:
            v = (int32_t)(u & 0x0FFF) - 2048;
            v <<= 4;
            break;
        case INPUT_FMT_U16:
            v = (int32_t)u - 32768;
            break;
        default: // INPUT_FMT_S16
            v = (int16_t)u;
            break;
        }
        if (v > 32767) v = 32767;
        if (v < -32768) v = -32768;
        data[i] = (int16_t)v;
    }
}

// 将 f32 路径结果回写到 Lua table（若输入为 table）
static void writeback_lua_tables(lua_State* L, float* r, float* im, int N)
{
    // 检查 real 是否为 nil 或 zbuff
    if (!lua_isnil(L, 1) && !luaL_testudata(L, 1, LUAT_ZBUFF_TYPE)) {
        lua_settop(L, 2);
        for (int i = 0; i < N; i++) {
            lua_pushnumber(L, r[i]);
            lua_rawseti(L, 1, i + 1);
        }
    }
    // 检查 imag 是否为 nil 或 zbuff
    if (!lua_isnil(L, 2) && !luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)) {
        for (int i = 0; i < N; i++) {
            lua_pushnumber(L, im[i]);
            lua_rawseti(L, 2, i + 1);
        }
    }
}

/*
生成 float32 旋转因子
@api fft.generate_twiddles(N)
@int N 点数，必须为 2 的幂
@return table Wc, table Ws 两个 Lua 数组（长度 N/2），分别为 cos 与 -sin
@usage
local N = 2048
local Wc, Ws = fft.generate_twiddles(N)
*/
static int l_fft_generate_twiddles(lua_State* L)
{
    int N = luaL_checkinteger(L, 1);
    if (N <= 1 || (N & (N - 1)))
        return luaL_error(L, "N must be power of 2");
    int half = N / 2;
    float* Wc = luat_heap_malloc(sizeof(float) * half);
    float* Ws = luat_heap_malloc(sizeof(float) * half);
    if (!Wc || !Ws) {
        if (Wc) luat_heap_free(Wc);
        if (Ws) luat_heap_free(Ws);
        return luaL_error(L, "no memory");
    }
    luat_fft_generate_twiddles(N, Wc, Ws);
    write_lua_array_float(L, Wc, half);
    write_lua_array_float(L, Ws, half);
    luat_heap_free(Wc);
    luat_heap_free(Ws);
    return 2;
}

// 生成 Q15 旋转因子到 zbuff（长度要求：N/2 * 2 字节）
// 调用方式：fft.generate_twiddles_q15_to_zbuff(N, Wc_zbuff, Ws_zbuff)
/*
生成 q15 旋转因子到 zbuff（零浮点）
@api fft.generate_twiddles_q15_to_zbuff(N, Wc_zb, Ws_zb)
@int N 点数，必须为 2 的幂
@zbuff Wc_zb 输出缓冲，长度至少为 (N/2)*2 字节，存放 int16 Q15 的 cos
@zbuff Ws_zb 输出缓冲，长度至少为 (N/2)*2 字节，存放 int16 Q15 的 -sin（前向）
@return nil 无返回值，结果写入传入的 zbuff
@usage
local N = 2048
local Wc_q15 = zbuff.create((N//2)*2)
local Ws_q15 = zbuff.create((N//2)*2)
fft.generate_twiddles_q15_to_zbuff(N, Wc_q15, Ws_q15)
*/
static int l_fft_generate_twiddles_q15_to_zbuff(lua_State* L)
{
    int N = luaL_checkinteger(L, 1);
    if (N <= 1 || (N & (N - 1)))
        return luaL_error(L, "N must be power of 2");
    luat_zbuff_t* zbWc = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    luat_zbuff_t* zbWs = (luat_zbuff_t*)luaL_testudata(L, 3, LUAT_ZBUFF_TYPE);
    if (!zbWc || !zbWs)
        return luaL_error(L, "Wc/Ws must be zbuff");
    int need = (N / 2) * 2;
    if ((int)zbWc->len < need || (int)zbWs->len < need)
        return luaL_error(L, "zbuff too small");
    int16_t* Wc = (int16_t*)zbWc->addr;
    int16_t* Ws = (int16_t*)zbWs->addr;
    luat_fft_generate_twiddles_q15(Wc, Ws, N);
    return 0;
}

/*
原地 FFT 计算
@api fft.run(real, imag, N, Wc, Ws[, opts])
@param real 实部容器：
 - float32 路径：Lua 数组或 zbuff(float32)
 - q15 路径：zbuff(int16)。当 opts.core="q15" 且 opts.input_format 为 "u12"/"u16"/"s16" 时生效
@param imag 虚部容器：同 real。可为 nil（视为全 0）
@int N 点数，2 的幂
@param Wc 旋转因子 cos：
 - float32 路径：Lua 数组或 zbuff(float32)
 - q15 路径：zbuff(int16)，推荐配合 fft.generate_twiddles_q15_to_zbuff 生成
@param Ws 旋转因子 -sin：同 Wc；IFFT 建议传入共轭版本以避免内层符号乘
@table [opts]
 - core: "f32" | "q15"（默认 "f32"）
   * "f32": 浮点内核，精度高（32位），计算稳定，适合精密分析
   * "q15": 定点内核，速度快（16位整数），内存省，适合实时处理但精度略低
 - input_format: "f32" | "u12" | "u16" | "s16"（q15 时必填其一）
   * "f32": 标准浮点输入，适用于已处理的信号数据
   * "u12": 12位无符号整数（0~4095），常见于ADC采样，自动去直流分量
   * "u16": 16位无符号整数（0~65535），适用于高精度ADC或预处理数据
   * "s16": 16位有符号整数（-32768~32767），适用于已去直流的差分信号
@return nil 就地修改 real/imag
@usage
-- f32 路径示例（zbuff float32）
local N=2048
local real=zbuff.create(N*4); local imag=zbuff.create(N*4)
local Wc,Ws=fft.generate_twiddles(N)
fft.run(real, imag, N, Wc, Ws)

-- q15 路径示例（U12 整数输入）
local N=2048
local real_i16=zbuff.create(N*2); local imag_i16=zbuff.create(N*2)
local Wc_q15=zbuff.create((N//2)*2); local Ws_q15=zbuff.create((N//2)*2)
fft.generate_twiddles_q15_to_zbuff(N, Wc_q15, Ws_q15)
-- 写入 U12 数据到 real_i16 后：
fft.run(real_i16, imag_i16, N, Wc_q15, Ws_q15, {core="q15", input_format="u12"})
*/
static int l_fft_run(lua_State* L)
{
    fft_args_t a;
    int parse_ret = fft_parse_args(L, &a);
    if (parse_ret != 0) {
        LLOGE("fft.run: parameter parsing failed, error code: %d", parse_ret);
        return luaL_error(L, "fft.run: invalid parameters");
    }

    int N = a.N;
    int integer_input = (a.input_fmt != INPUT_FMT_F32);

    if (a.use_q15 && integer_input) {
        // Q15 整数快速路径
        luat_zbuff_t* zb_real = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
        luat_zbuff_t* zb_imag = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
        if (!zb_real) {
            fft_args_cleanup(&a);
            return luaL_error(L, "q15 mode requires real to be zbuff");
        }
        if ((int)zb_real->len < N * 2) {
            fft_args_cleanup(&a);
            return luaL_error(L, "real zbuff too small");
        }

        // 原地转换为 Q15
        convert_integer_to_q15((int16_t*)zb_real->addr, N, a.input_fmt);

        if (zb_imag && (int)zb_imag->len >= N * 2) {
            convert_integer_to_q15((int16_t*)zb_imag->addr, N, a.input_fmt);
        } else if (zb_imag) {
            memset(zb_imag->addr, 0, zb_imag->len);
        }

        // 获取 Q15 twiddle
        luat_zbuff_t* zbWc = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
        luat_zbuff_t* zbWs = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
        const int need_tw = (N / 2) * 2;
        if (!(zbWc && zbWs) || (int)zbWc->len < need_tw || (int)zbWs->len < need_tw) {
            fft_args_cleanup(&a);
            return luaL_error(L, "q15 requires Wc/Ws zbuff, length N/2*2 bytes");
        }

        int scale_exp = 0;
        int rc = luat_fft_inplace_q15((int16_t*)zb_real->addr,
                                       zb_imag ? (int16_t*)zb_imag->addr : NULL,
                                       N, 0, (const int16_t*)zbWc->addr,
                                       (const int16_t*)zbWs->addr, 0, &scale_exp);
        fft_args_cleanup(&a);
        if (rc != 0)
            return luaL_error(L, "q15 core failed");
        return 0;
    }

    // 默认：float32 路径
    luat_fft_run_inplace(a.r, a.im, N, a.Wc, a.Ws);
    writeback_lua_tables(L, a.r, a.im, N);
    fft_args_cleanup(&a);
    return 0;
}

/*
原地 IFFT 计算
@api fft.ifft(real, imag, N, Wc, Ws[, opts])
@param real 实部容器，类型与 fft.run 一致
@param imag 虚部容器，类型与 fft.run 一致
@int N 点数，2 的幂
@param Wc 旋转因子 cos：类型同 fft.run
@param Ws 旋转因子 -sin：类型同 fft.run。建议为 IFFT 预共轭传入 +sin 表
@table [opts]
 - core: "f32" | "q15"（默认 "f32"）
 - input_format: "f32" | "u12" | "u16" | "s16"（q15 时必填其一）
@return nil 就地修改 real/imag，并在 f32 路径下包含 1/N 归一化
*/
static int l_fft_ifft(lua_State* L)
{
    fft_args_t a;
    int parse_ret = fft_parse_args(L, &a);
    if (parse_ret != 0) {
        LLOGE("fft.ifft: parameter parsing failed, error code: %d", parse_ret);
        return luaL_error(L, "fft.ifft: invalid parameters");
    }
    
    int N = a.N;
    int integer_input = (a.input_fmt != INPUT_FMT_F32);

    if (a.use_q15 && integer_input) {
        // Q15 IFFT 路径：原地操作（避免额外分配）
        luat_zbuff_t* zb_real = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
        luat_zbuff_t* zb_imag = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
        if (!zb_real) {
            fft_args_cleanup(&a);
            return luaL_error(L, "q15 mode requires real to be zbuff");
        }
        if ((int)zb_real->len < N * 2) {
            fft_args_cleanup(&a);
            return luaL_error(L, "real zbuff too small");
        }

        // 原地转换
        convert_integer_to_q15((int16_t*)zb_real->addr, N, a.input_fmt);

        if (zb_imag && (int)zb_imag->len >= N * 2) {
            convert_integer_to_q15((int16_t*)zb_imag->addr, N, a.input_fmt);
        } else if (zb_imag) {
            memset(zb_imag->addr, 0, zb_imag->len);
        }

        // 获取 Q15 twiddle
        luat_zbuff_t* zbWc = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
        luat_zbuff_t* zbWs = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
        const int need_tw = (N / 2) * 2;
        const int16_t* Wcq = NULL;
        const int16_t* Wsq = NULL;
        int16_t* Wcq_alloc = NULL;
        int16_t* Wsq_alloc = NULL;
        if (zbWc && zbWs && (int)zbWc->len >= need_tw && (int)zbWs->len >= need_tw) {
            Wcq = (const int16_t*)zbWc->addr;
            Wsq = (const int16_t*)zbWs->addr;
        } else {
            Wcq_alloc = (int16_t*)luat_heap_malloc(sizeof(int16_t) * (N / 2));
            Wsq_alloc = (int16_t*)luat_heap_malloc(sizeof(int16_t) * (N / 2));
            if (!Wcq_alloc || !Wsq_alloc) {
                if (Wcq_alloc) luat_heap_free(Wcq_alloc);
                if (Wsq_alloc) luat_heap_free(Wsq_alloc);
                fft_args_cleanup(&a);
                return luaL_error(L, "no memory");
            }
            luat_fft_generate_twiddles_q15(Wcq_alloc, Wsq_alloc, N);
            Wcq = Wcq_alloc;
            Wsq = Wsq_alloc;
        }

        int scale_exp = 0;
        int16_t* imag_ptr = (zb_imag && (int)zb_imag->len >= N * 2)
                            ? (int16_t*)zb_imag->addr : NULL;
        int rc = luat_fft_inplace_q15((int16_t*)zb_real->addr, imag_ptr,
                                       N, 1, Wcq, Wsq, 0, &scale_exp);
        if (Wcq_alloc) luat_heap_free(Wcq_alloc);
        if (Wsq_alloc) luat_heap_free(Wsq_alloc);
        fft_args_cleanup(&a);
        if (rc != 0)
            return luaL_error(L, "q15 core failed");
        return 0;
    }

    // 默认：float32 路径
    luat_ifft_run_inplace(a.r, a.im, N, a.Wc, a.Ws);
    writeback_lua_tables(L, a.r, a.im, N);
    fft_args_cleanup(&a);
    return 0;
}

/*
频域积分（1/(jω)）
@api fft.fft_integral(real, imag, n, df)
@param real 实部（float32，Lua 数组或 zbuff）
@param imag 虚部（float32，Lua 数组或 zbuff）
@int n 点数，2 的幂
@number df 频率分辨率（fs/n）
@return nil 原地修改 real/imag（DC 置 0）
@usage
-- 先完成 FFT 得到谱 (real, imag)，再调用积分：
fft.fft_integral(real, imag, N, fs/N)
*/
static int l_fft_integral(lua_State* L)
{
    int n = luaL_checkinteger(L, 3);
    float df = (float)luaL_checknumber(L, 4);
    if (n <= 1 || (n & (n - 1)))
        return luaL_error(L, "n must be power of 2");

    float *r = NULL, *im = NULL;
    int r_free = 0, im_free = 0;
    luat_zbuff_t* zb;

    zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
    if (zb) {
        r = (float*)zb->addr;
    } else {
        r = luat_heap_malloc(sizeof(float) * n);
        r_free = 1;
        if (!r) goto integral_oom;
        if (read_lua_array_float(L, 1, r, n)) goto integral_err_real;
    }
    zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    if (zb) {
        im = (float*)zb->addr;
    } else {
        im = luat_heap_malloc(sizeof(float) * n);
        im_free = 1;
        if (!im) goto integral_oom;
        if (read_lua_array_float(L, 2, im, n)) goto integral_err_imag;
    }

    luat_fft_integral_inplace(r, im, n, df);

    if (!luaL_testudata(L, 1, LUAT_ZBUFF_TYPE)) {
        lua_settop(L, 2);
        for (int i = 0; i < n; i++) {
            lua_pushnumber(L, r[i]);
            lua_rawseti(L, 1, i + 1);
        }
    }
    if (!luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)) {
        for (int i = 0; i < n; i++) {
            lua_pushnumber(L, im[i]);
            lua_rawseti(L, 2, i + 1);
        }
    }

    if (r_free) luat_heap_free(r);
    if (im_free) luat_heap_free(im);
    return 0;

integral_oom:
    if (r_free && r) luat_heap_free(r);
    if (im_free && im) luat_heap_free(im);
    return luaL_error(L, "no memory");
integral_err_real:
    if (r_free) luat_heap_free(r);
    return luaL_error(L, "real must be number array or zbuff");
integral_err_imag:
    if (r_free && r) luat_heap_free(r);
    if (im_free) luat_heap_free(im);
    return luaL_error(L, "imag must be number array or zbuff");
}

static const rotable_Reg_t reg_fft[] = {
    { "generate_twiddles", ROREG_FUNC(l_fft_generate_twiddles) },
    { "generate_twiddles_q15_to_zbuff", ROREG_FUNC(l_fft_generate_twiddles_q15_to_zbuff) },
    { "run", ROREG_FUNC(l_fft_run) },
    { "ifft", ROREG_FUNC(l_fft_ifft) },
    { "fft_integral", ROREG_FUNC(l_fft_integral) },
    { NULL, ROREG_INT(0) }
};

LUAMOD_API int luaopen_fft(lua_State* L)
{
    luat_newlib2(L, reg_fft);
    return 1;
}
