/*
@module  fft
@summary 快速傅里叶变换（FFT/IFFT），支持 float32 与 q15 定点内核
@version 0.2
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
// Q15 内核头文件（当前版本已实现）
#include "fft_core_q15.h"

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
        if (Wc)
            luat_heap_free(Wc);
        if (Ws)
            luat_heap_free(Ws);
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
    // 使用整型查表（度数，1度分辨率，缩放256）生成近似Q15旋转因子
    static const int16_t SIN_TABLE256[91] = {
        0, 4, 9, 13, 18, 22, 27, 31, 36, 40, 44, 49, 53, 58, 62, 66, 71, 75, 79, 83,
        88, 92, 96, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 139, 143, 147, 150, 154, 158, 161,
        165, 168, 171, 175, 178, 181, 184, 187, 190, 193, 196, 199, 202, 204, 207, 210, 212, 215, 217, 219,
        222, 224, 226, 228, 230, 232, 234, 236, 237, 239, 241, 242, 243, 245, 246, 247, 248, 249, 250, 251,
        252, 253, 254, 254, 255, 255, 255, 256, 256, 256, 256
    };
    int N = luaL_checkinteger(L, 1);
    if (N <= 1 || (N & (N - 1)))
        return luaL_error(L, "N 必须为 2 的幂");
    luat_zbuff_t* zbWc = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    luat_zbuff_t* zbWs = (luat_zbuff_t*)luaL_testudata(L, 3, LUAT_ZBUFF_TYPE);
    if (!zbWc || !zbWs)
        return luaL_error(L, "Wc/Ws 需为 zbuff");
    int need = (N / 2) * 2;
    if ((int)zbWc->len < need || (int)zbWs->len < need)
        return luaL_error(L, "zbuff 太小");
    int16_t* Wc = (int16_t*)zbWc->addr;
    int16_t* Ws = (int16_t*)zbWs->addr;
    for (int k = 0; k < N / 2; k++) {
        // angle = 360 * k / N (度)，四舍五入
        int deg = (int)((int64_t)k * 360 + (N / 2)) / N;
        // cos 与 -sin，放大到 Q15（256<<7=32768，钳到 32767）
        int s256;
        int d = deg;
        int neg = 0;
        if (d < 0) {
            d = -d + 180;
        }
        d %= 360;
        if (d >= 180) {
            d -= 180;
            neg = 1;
        }
        if (d <= 90)
            s256 = SIN_TABLE256[d];
        else
            s256 = SIN_TABLE256[180 - d];
        int c256 = 0; // cos = sin(deg+90)
        int d2 = deg + 90;
        neg = 0;
        d = d2;
        if (d < 0) {
            d = -d + 180;
        }
        d %= 360;
        if (d >= 180) {
            d -= 180;
            neg = 1;
        }
        if (d <= 90)
            c256 = SIN_TABLE256[d];
        else
            c256 = SIN_TABLE256[180 - d];
        if (neg)
            c256 = -c256;
        int32_t wc = (int32_t)c256 << 7;
        if (wc > 32767)
            wc = 32767;
        if (wc < -32768)
            wc = -32768;
        // -sin：复用 s256 并加符号
        int sgn = 0;
        d = deg;
        if (d < 0) {
            d = -d + 180;
        }
        d %= 360;
        if (d >= 180) {
            d -= 180;
            sgn = 1;
        }
        int32_t ws = (int32_t)(sgn ? -s256 : s256) << 7;
        if (ws > 32767)
            ws = 32767;
        if (ws < -32768)
            ws = -32768;
        Wc[k] = (int16_t)wc;
        Ws[k] = (int16_t)ws;
    }
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
    int N = luaL_checkinteger(L, 3);
    if (N <= 1 || (N & (N - 1)))
        return luaL_error(L, "N 必须为 2 的幂");

    float *r = NULL, *im = NULL, *Wc = NULL, *Ws = NULL;
    int r_free = 0, im_free = 0, wc_free = 0, ws_free = 0;

    // 可选参数解析（opts）：当前版本仅支持 core/input_format（其余项作为未来优化）
    const char* core = "f32"; // "f32" | "q15"
    const char* input_format = "f32"; // "f32"|"u12"|"u16"|"s16"

    // real
    luat_zbuff_t* zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
    if (zb) {
        r = (float*)zb->addr;
    } else {
        r = luat_heap_malloc(sizeof(float) * N);
        r_free = 1;
        if (!r)
            return luaL_error(L, "no memory");
        if (read_lua_array_float(L, 1, r, N)) {
            if (r_free)
                luat_heap_free(r);
            return luaL_error(L, "real must be number array or zbuff");
        }
    }
    // imag
    zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    if (zb) {
        im = (float*)zb->addr;
    } else {
        im = luat_heap_malloc(sizeof(float) * N);
        im_free = 1;
        if (!im) {
            if (r_free)
                luat_heap_free(r);
            return luaL_error(L, "no memory");
        }
        if (read_lua_array_float(L, 2, im, N)) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            return luaL_error(L, "imag must be number array or zbuff");
        }
    }
    // W_real
    zb = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
    if (zb) {
        Wc = (float*)zb->addr;
    } else {
        Wc = luat_heap_malloc(sizeof(float) * (N / 2));
        wc_free = 1;
        if (!Wc) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            return luaL_error(L, "no memory");
        }
        if (read_lua_array_float(L, 4, Wc, N / 2)) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            return luaL_error(L, "W_real must be number array or zbuff");
        }
    }
    // W_imag
    zb = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
    if (zb) {
        Ws = (float*)zb->addr;
    } else {
        Ws = luat_heap_malloc(sizeof(float) * (N / 2));
        ws_free = 1;
        if (!Ws) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            return luaL_error(L, "内存不足");
        }
        if (read_lua_array_float(L, 5, Ws, N / 2)) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "W_imag 需为数字数组或 zbuff");
        }
    }
    // 读取第6个参数的 opts（若有）
    if (lua_gettop(L) >= 6 && lua_istable(L, 6)) {
        lua_getfield(L, 6, "core");
        if (!lua_isnil(L, -1))
            core = luaL_checkstring(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 6, "input_format");
        if (!lua_isnil(L, -1))
            input_format = luaL_checkstring(L, -1);
        lua_pop(L, 1);
    }

    // 如果选择 q15 内核，且输入为整数 zbuff，则走 q15 路径
    int use_q15 = (core && strcmp(core, "q15") == 0);
    int integer_input = (strcmp(input_format, "u12") == 0 || strcmp(input_format, "u16") == 0 || strcmp(input_format, "s16") == 0);
    if (use_q15 && integer_input) {
        // 校验 real/imag 是否为 zbuff（当前整型快速路径仅支持 zbuff）
        luat_zbuff_t* zb_real = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
        luat_zbuff_t* zb_imag = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
        if (!zb_real) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "q15 模式要求 real 为整数 zbuff");
        }
        if ((int)zb_real->len < N * 2) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "real zbuff 太小");
        }
        // 原地：将整数输入就地转换为带符号 Q15（覆盖 zbuff）
        uint16_t* r16 = (uint16_t*)zb_real->addr;
        for (int i = 0; i < N; i++) {
            int32_t v;
            uint16_t u = r16[i];
            if (strcmp(input_format, "u12") == 0) {
                v = (int32_t)(u & 0x0FFF) - 2048;
                v <<= 4;
            } else if (strcmp(input_format, "u16") == 0) {
                v = (int32_t)u - 32768;
            } else {
                v = (int16_t)u;
            }
            if (v > 32767)
                v = 32767;
            if (v < -32768)
                v = -32768;
            ((int16_t*)zb_real->addr)[i] = (int16_t)v;
        }
        if (zb_imag && (int)zb_imag->len >= N * 2) {
            uint16_t* i16 = (uint16_t*)zb_imag->addr;
            for (int i = 0; i < N; i++) {
                int32_t v;
                uint16_t u = i16[i];
                if (strcmp(input_format, "u12") == 0) {
                    v = (int32_t)(u & 0x0FFF) - 2048;
                    v <<= 4;
                } else if (strcmp(input_format, "u16") == 0) {
                    v = (int32_t)u - 32768;
                } else {
                    v = (int16_t)u;
                }
                if (v > 32767)
                    v = 32767;
                if (v < -32768)
                    v = -32768;
                ((int16_t*)zb_imag->addr)[i] = (int16_t)v;
            }
        } else if (zb_imag) {
            // 长度不足则清零
            memset(zb_imag->addr, 0, zb_imag->len);
        }

        // 强制要求外部传入 Q15 twiddle
        luat_zbuff_t* zbWc = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
        luat_zbuff_t* zbWs = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
        const int need_tw = (N / 2) * 2;
        if (!(zbWc && zbWs) || (int)zbWc->len < need_tw || (int)zbWs->len < need_tw) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "q15 需传入 Wc/Ws zbuff，长度 N/2*2 字节");
        }

        int scale_exp = 0;
        int rc = luat_fft_inplace_q15((int16_t*)zb_real->addr, zb_imag ? (int16_t*)zb_imag->addr : NULL,
                                       N, 0, (const int16_t*)zbWc->addr, (const int16_t*)zbWs->addr,
                                       0, &scale_exp);
        if (r_free)
            luat_heap_free(r);
        if (im_free)
            luat_heap_free(im);
        if (wc_free)
            luat_heap_free(Wc);
        if (ws_free)
            luat_heap_free(Ws);
        if (rc != 0)
            return luaL_error(L, "q15 内核执行失败");
        return 0;
    }

    // 默认：沿用 float32 路径
    luat_fft_run_inplace(r, im, N, Wc, Ws);

    // if input was table, write back
    if (!luaL_testudata(L, 1, LUAT_ZBUFF_TYPE)) {
        lua_settop(L, 2);
        for (int i = 0; i < N; i++) {
            lua_pushnumber(L, r[i]);
            lua_rawseti(L, 1, i + 1);
        }
    }
    if (!luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)) {
        for (int i = 0; i < N; i++) {
            lua_pushnumber(L, im[i]);
            lua_rawseti(L, 2, i + 1);
        }
    }

    if (r_free)
        luat_heap_free(r);
    if (im_free)
        luat_heap_free(im);
    if (wc_free)
        luat_heap_free(Wc);
    if (ws_free)
        luat_heap_free(Ws);
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
    int N = luaL_checkinteger(L, 3);
    if (N <= 1 || (N & (N - 1)))
        return luaL_error(L, "N 必须为 2 的幂");

    float *r = NULL, *im = NULL, *Wc = NULL, *Ws = NULL;
    int r_free = 0, im_free = 0, wc_free = 0, ws_free = 0;
    // 可选 opts（同 run）：当前仅 core/input_format
    const char* core = "f32";
    const char* input_format = "f32";
    luat_zbuff_t* zb = NULL;
    zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
    if (zb) {
        r = (float*)zb->addr;
    } else {
        r = luat_heap_malloc(sizeof(float) * N);
        r_free = 1;
        if (!r)
            return luaL_error(L, "no memory");
        if (read_lua_array_float(L, 1, r, N)) {
            if (r_free)
                luat_heap_free(r);
            return luaL_error(L, "real must be number array or zbuff");
        }
    }
    zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    if (zb) {
        im = (float*)zb->addr;
    } else {
        im = luat_heap_malloc(sizeof(float) * N);
        im_free = 1;
        if (!im) {
            if (r_free)
                luat_heap_free(r);
            return luaL_error(L, "no memory");
        }
        if (read_lua_array_float(L, 2, im, N)) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            return luaL_error(L, "imag must be number array or zbuff");
        }
    }
    zb = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
    if (zb) {
        Wc = (float*)zb->addr;
    } else {
        Wc = luat_heap_malloc(sizeof(float) * (N / 2));
        wc_free = 1;
        if (!Wc) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            return luaL_error(L, "no memory");
        }
        if (read_lua_array_float(L, 4, Wc, N / 2)) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            return luaL_error(L, "W_real must be number array or zbuff");
        }
    }
    zb = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
    if (zb) {
        Ws = (float*)zb->addr;
    } else {
        Ws = luat_heap_malloc(sizeof(float) * (N / 2));
        ws_free = 1;
        if (!Ws) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            return luaL_error(L, "内存不足");
        }
        if (read_lua_array_float(L, 5, Ws, N / 2)) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "W_imag 需为数字数组或 zbuff");
        }
    }

    if (lua_gettop(L) >= 6 && lua_istable(L, 6)) {
        lua_getfield(L, 6, "core");
        if (!lua_isnil(L, -1))
            core = luaL_checkstring(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 6, "input_format");
        if (!lua_isnil(L, -1))
            input_format = luaL_checkstring(L, -1);
        lua_pop(L, 1);
    }

    int use_q15 = (core && strcmp(core, "q15") == 0);
    int integer_input = (strcmp(input_format, "u12") == 0 || strcmp(input_format, "u16") == 0 || strcmp(input_format, "s16") == 0);
    if (use_q15 && integer_input) {
        luat_zbuff_t* zb_real = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
        luat_zbuff_t* zb_imag = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
        if (!zb_real) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "q15 模式要求 real 为整数 zbuff");
        }
        if ((int)zb_real->len < N * 2) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "real zbuff 太小");
        }

        int16_t* rq = (int16_t*)luat_heap_malloc(sizeof(int16_t) * N);
        int16_t* iq = (int16_t*)luat_heap_malloc(sizeof(int16_t) * N);
        if (!rq || !iq) {
            if (rq)
                luat_heap_free(rq);
            if (iq)
                luat_heap_free(iq);
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "内存不足");
        }

        const uint16_t* r16 = (const uint16_t*)zb_real->addr;
        for (int i = 0; i < N; i++) {
            int32_t v;
            uint16_t u = r16[i];
            if (strcmp(input_format, "u12") == 0) {
                v = ((int32_t)(u & 0x0FFF)) - 2048;
                v <<= 4;
            } else if (strcmp(input_format, "u16") == 0) {
                v = (int32_t)u - 32768;
            } else {
                v = (int16_t)u;
            }
            if (v > 32767)
                v = 32767;
            if (v < -32768)
                v = -32768;
            rq[i] = (int16_t)v;
        }
        if (zb_imag && (int)zb_imag->len >= N * 2) {
            const uint16_t* i16 = (const uint16_t*)zb_imag->addr;
            for (int i = 0; i < N; i++) {
                int32_t v;
                uint16_t u = i16[i];
                if (strcmp(input_format, "u12") == 0) {
                    v = ((int32_t)(u & 0x0FFF)) - 2048;
                    v <<= 4;
                } else if (strcmp(input_format, "u16") == 0) {
                    v = (int32_t)u - 32768;
                } else {
                    v = (int16_t)u;
                }
                if (v > 32767)
                    v = 32767;
                if (v < -32768)
                    v = -32768;
                iq[i] = (int16_t)v;
            }
        } else {
            memset(iq, 0, sizeof(int16_t) * N);
        }

        // 使用传入的 Q15 旋转因子（zbuff）或按需生成
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
                if (Wcq_alloc)
                    luat_heap_free(Wcq_alloc);
                if (Wsq_alloc)
                    luat_heap_free(Wsq_alloc);
                luat_heap_free(rq);
                luat_heap_free(iq);
                if (r_free)
                    luat_heap_free(r);
                if (im_free)
                    luat_heap_free(im);
                if (wc_free)
                    luat_heap_free(Wc);
                if (ws_free)
                    luat_heap_free(Ws);
                return luaL_error(L, "内存不足");
            }
            luat_fft_generate_twiddles_q15(Wcq_alloc, Wsq_alloc, N);
            Wcq = Wcq_alloc;
            Wsq = Wsq_alloc;
        }

        int scale_exp = 0;
        int rc = luat_fft_inplace_q15(rq, iq, N, 1, Wcq, Wsq, 0, &scale_exp); // inverse=1
        if (Wcq_alloc)
            luat_heap_free(Wcq_alloc);
        if (Wsq_alloc)
            luat_heap_free(Wsq_alloc);
        if (rc != 0) {
            luat_heap_free(rq);
            luat_heap_free(iq);
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            if (wc_free)
                luat_heap_free(Wc);
            if (ws_free)
                luat_heap_free(Ws);
            return luaL_error(L, "q15 内核执行失败");
        }

        for (int i = 0; i < N; i++)
            ((int16_t*)zb_real->addr)[i] = rq[i];
        if (zb_imag && (int)zb_imag->len >= N * 2) {
            for (int i = 0; i < N; i++)
                ((int16_t*)zb_imag->addr)[i] = iq[i];
        }
        luat_heap_free(rq);
        luat_heap_free(iq);
        if (r_free)
            luat_heap_free(r);
        if (im_free)
            luat_heap_free(im);
        if (wc_free)
            luat_heap_free(Wc);
        if (ws_free)
            luat_heap_free(Ws);
        return 0;
    }

    luat_ifft_run_inplace(r, im, N, Wc, Ws);

    if (!luaL_testudata(L, 1, LUAT_ZBUFF_TYPE)) {
        lua_settop(L, 2);
        for (int i = 0; i < N; i++) {
            lua_pushnumber(L, r[i]);
            lua_rawseti(L, 1, i + 1);
        }
    }
    if (!luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)) {
        for (int i = 0; i < N; i++) {
            lua_pushnumber(L, im[i]);
            lua_rawseti(L, 2, i + 1);
        }
    }

    if (r_free)
        luat_heap_free(r);
    if (im_free)
        luat_heap_free(im);
    if (wc_free)
        luat_heap_free(Wc);
    if (ws_free)
        luat_heap_free(Ws);
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
    luat_zbuff_t* zb = NULL;
    zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
    if (zb) {
        r = (float*)zb->addr;
    } else {
        r = luat_heap_malloc(sizeof(float) * n);
        r_free = 1;
        if (!r)
            return luaL_error(L, "no memory");
        if (read_lua_array_float(L, 1, r, n)) {
            if (r_free)
                luat_heap_free(r);
            return luaL_error(L, "real must be number array or zbuff");
        }
    }
    zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    if (zb) {
        im = (float*)zb->addr;
    } else {
        im = luat_heap_malloc(sizeof(float) * n);
        im_free = 1;
        if (!im) {
            if (r_free)
                luat_heap_free(r);
            return luaL_error(L, "no memory");
        }
        if (read_lua_array_float(L, 2, im, n)) {
            if (r_free)
                luat_heap_free(r);
            if (im_free)
                luat_heap_free(im);
            return luaL_error(L, "imag must be number array or zbuff");
        }
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
    if (r_free)
        luat_heap_free(r);
    if (im_free)
        luat_heap_free(im);
    return 0;
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
