#include "fft_core_q15.h"
#include "luat_base.h"
// 去除浮点依赖

#ifndef __LUAT_C_CODE_IN_RAM__
#define __LUAT_C_CODE_IN_RAM__
#endif

static inline int16_t q15_saturate(int32_t x)
{
    if (x > 32767)
        return 32767;
    if (x < -32768)
        return -32768;
    return (int16_t)x;
}

static inline int16_t q15_mul(int16_t a, int16_t b)
{
    int32_t t = (int32_t)a * (int32_t)b; // Q15*Q15 -> Q30
    t += 1 << 14; // round
    t >>= 15; // back to Q15
    return (int16_t)t; // 饱和延后到写回
}

// 通过度数获取 sin 的 Q15 值（支持任意整数度）
// 利用对称性：sin(180-d)=sin(d), sin(180+d)=-sin(d)
static int16_t sin_q15_deg(const int16_t* table91, int deg)
{
    int d = deg % 360;
    if (d < 0) d += 360;
    if (d <= 90) return table91[d];
    if (d <= 180) return table91[180 - d];
    if (d <= 270) return (int16_t)-table91[d - 180];
    return (int16_t)-table91[360 - d];
}

// 纯整数生成 Q15 旋转因子（无浮点依赖）
// 使用 Q15 精度查找表 + 线性插值，支持大 N 场景
__LUAT_C_CODE_IN_RAM__ void luat_fft_generate_twiddles_q15(int16_t* Wc, int16_t* Ws, int N)
{
    if (!Wc || !Ws || N <= 1)
        return;

    // sin 查找表（0~90 度，1 度步长，放大 32768 倍即 Q15）
    // sin_q15[d] = round(sin(d * pi / 180) * 32768)，钳到 32767
    static const int16_t SIN_Q15[91] = {
            0,   572,  1144,  1715,  2286,  2856,  3425,  3993,  4560,  5126,
         5690,  6252,  6813,  7371,  7927,  8481,  9032,  9580, 10126, 10668,
        11207, 11743, 12275, 12803, 13328, 13848, 14365, 14876, 15384, 15886,
        16384, 16877, 17364, 17847, 18324, 18795, 19261, 19720, 20174, 20622,
        21063, 21498, 21926, 22348, 22762, 23170, 23571, 23965, 24351, 24730,
        25102, 25466, 25822, 26170, 26510, 26842, 27166, 27482, 27789, 28088,
        28378, 28660, 28932, 29197, 29452, 29698, 29935, 30163, 30382, 30592,
        30792, 30983, 31164, 31336, 31499, 31651, 31795, 31928, 32052, 32166,
        32270, 32365, 32449, 32524, 32588, 32643, 32688, 32723, 32748, 32763,
        32767
    };

    int half = N / 2;
    for (int k = 0; k < half; k++) {
        // angle_deg = 360.0 * k / N，用整数高精度计算
        // deg_x256 = k * 360 * 256 / N（8 位小数精度，用于线性插值）
        int64_t deg_x256 = (int64_t)k * 360 * 256 / N;
        int deg_int = (int)(deg_x256 / 256);
        int frac = (int)(deg_x256 % 256); // 0~255 的小数部分

        // cos(angle) = sin(angle + 90)
        // -sin(angle) 用于前向 FFT 的 Ws

        // 线性插值: sin(deg + frac/256) ≈ sin(deg) + frac/256 * (sin(deg+1) - sin(deg))
        int16_t s0 = sin_q15_deg(SIN_Q15, deg_int + 90);
        int16_t s1 = sin_q15_deg(SIN_Q15, deg_int + 91);
        int32_t wc = (int32_t)s0 + ((int32_t)(s1 - s0) * frac + 128) / 256;
        if (wc > 32767) wc = 32767;
        if (wc < -32768) wc = -32768;
        Wc[k] = (int16_t)wc;

        int16_t t0 = sin_q15_deg(SIN_Q15, deg_int);
        int16_t t1 = sin_q15_deg(SIN_Q15, deg_int + 1);
        int32_t ws = (int32_t)t0 + ((int32_t)(t1 - t0) * frac + 128) / 256;
        // Ws 存 -sin（前向 FFT）
        ws = -ws;
        if (ws > 32767) ws = 32767;
        if (ws < -32768) ws = -32768;
        Ws[k] = (int16_t)ws;
    }
}

__LUAT_C_CODE_IN_RAM__ int luat_fft_inplace_q15(int16_t* real, int16_t* imag, int N, int inverse,
    const int16_t* Wc, const int16_t* Ws,
    int block_scaling_mode, int* out_scale_exp)
{
    // 参数检查：验证输入指针和FFT大小的有效性
    if (!real || !imag || !Wc || !Ws)
        return -1;
    if (N <= 1 || (N & (N - 1)))
        return -2; // N必须是2的幂
    int scale_exp = 0; // 记录总缩放指数

    // 确定逆变换的符号系数：逆变换需要对旋转因子虚部取共轭
    int inv_sign = inverse ? -1 : 1;

    // 位逆序重排（原地、迭代版本）
    // 对所有元素进行位逆序重排，为FFT算法做准备
    for (int i = 1, j = 0; i < N; i++) {
        int bit = N >> 1; // 从最高位开始
        // 计算i的位逆序索引j
        for (; j & bit; bit >>= 1)
            j &= ~bit;
        j |= bit;
        // 只交换一次，避免重复交换
        if (i < j) {
            int16_t tr = real[i];
            real[i] = real[j];
            real[j] = tr;
            int16_t ti = imag[i];
            imag[i] = imag[j];
            imag[j] = ti;
        }
    }

    // FFT主循环：Cooley-Tukey算法的迭代实现
    // len从2开始，每次翻倍，直到N
    for (int len = 2; len <= N; len <<= 1) {
        int half = len >> 1; // 当前阶段的半长度
        int step = N / len; // 旋转因子的步长

        int32_t stage_max_abs = 0; // 本级的最大绝对值（条件缩放模式使用）

        // 处理每个长度为len的子序列
        for (int base = 0; base < N; base += len) {
            int idx = 0; // 旋转因子索引
            // 对当前子序列进行蝶形运算
            for (int j = 0; j < half; j++) {
                // 获取旋转因子W = wr + i*wi
                int16_t wr = Wc[idx];
                int16_t wi = (int16_t)(Ws[idx] * inv_sign); // 逆变换时取共轭
                idx += step;

                // 蝶形运算的两个数据点索引
                int p = base + j; // 上半部分索引
                int q = p + half; // 下半部分索引

                // 读取输入数据
                int16_t ur = real[p]; // X[p]的实部
                int16_t ui = imag[p]; // X[p]的虚部
                int16_t vr = real[q]; // X[q]的实部
                int16_t vi = imag[q]; // X[q]的虚部

                // 计算旋转后的值：W * X[q] = (wr + i*wi) * (vr + i*vi)
                // 使用 int32_t 中间结果避免 int16_t 减法溢出
                int32_t tr = (int32_t)q15_mul(wr, vr) - (int32_t)q15_mul(wi, vi);
                int32_t ti = (int32_t)q15_mul(wr, vi) + (int32_t)q15_mul(wi, vr);
                int16_t tr16 = q15_saturate(tr);
                int16_t ti16 = q15_saturate(ti);

                // 蝶形运算：计算输出
                int32_t xr = (int32_t)ur + (int32_t)tr16; // X[p] = X[p] + W*X[q]
                int32_t xi = (int32_t)ui + (int32_t)ti16;
                int32_t yr = (int32_t)ur - (int32_t)tr16; // X[q] = X[p] - W*X[q]
                int32_t yi = (int32_t)ui - (int32_t)ti16;

                if (block_scaling_mode == 1) {
                    // 条件缩放模式：跟踪本级的最大绝对值
                    int32_t a0 = xr < 0 ? -xr : xr;
                    int32_t a1 = xi < 0 ? -xi : xi;
                    int32_t a2 = yr < 0 ? -yr : yr;
                    int32_t a3 = yi < 0 ? -yi : yi;
                    if (a0 > stage_max_abs)
                        stage_max_abs = a0;
                    if (a1 > stage_max_abs)
                        stage_max_abs = a1;
                    if (a2 > stage_max_abs)
                        stage_max_abs = a2;
                    if (a3 > stage_max_abs)
                        stage_max_abs = a3;
                    // 暂存到输出（先不缩放，避免重复计算）
                    real[p] = q15_saturate(xr);
                    imag[p] = q15_saturate(xi);
                    real[q] = q15_saturate(yr);
                    imag[q] = q15_saturate(yi);
                } else {
                    // 固定缩放模式：每级固定右移1位防止溢出
                    xr >>= 1;
                    xi >>= 1;
                    yr >>= 1;
                    yi >>= 1;
                    real[p] = q15_saturate(xr);
                    imag[p] = q15_saturate(xi);
                    real[q] = q15_saturate(yr);
                    imag[q] = q15_saturate(yi);
                }
            }
        }

        if (block_scaling_mode == 1) {
            // 条件缩放：检查是否需要在本级进行缩放
            // 如果最大值接近Q15范围上限，则统一右移1位
            if (stage_max_abs > 16384) { // 16384 = 2^14，接近32767的一半
                // 对所有数据统一右移1位
                for (int i = 0; i < N; i++) {
                    int32_t r = real[i];
                    int32_t im = imag[i];
                    r >>= 1;
                    im >>= 1;
                    real[i] = q15_saturate(r);
                    imag[i] = q15_saturate(im);
                }
                scale_exp += 1; // 记录缩放次数
            }
        } else {
            scale_exp += 1; // 固定缩放模式：每级缩放指数+1
        }
    }

    // 输出总缩放指数（用于后续的幅度校正）
    if (out_scale_exp)
        *out_scale_exp = scale_exp;
    return 0; // 成功返回
}
