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

// 占位：不再提供浮点生成（使用绑定层的整型 LUT 生成）
__LUAT_C_CODE_IN_RAM__ void luat_fft_generate_twiddles_q15(int16_t* Wc, int16_t* Ws, int N)
{
    (void)Wc;
    (void)Ws;
    (void)N;
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

    // 确定逆变换的符号：逆变换需要对旋转因子虚部取共轭
    // 预共轭：调用方需根据 inverse 提供已处理好的 Ws

    // FFT主循环：Cooley-Tukey算法的迭代实现
    // len从2开始，每次翻倍，直到N
    for (int len = 2; len <= N; len <<= 1) {
        int half = len >> 1; // 当前阶段的半长度
        int step = N / len; // 旋转因子的步长

        int need_scale_this_stage = 0; // 本级是否需要缩放的标志
        int32_t stage_max_abs = 0; // 本级的最大绝对值

        // 处理每个长度为len的子序列
        for (int base = 0; base < N; base += len) {
            int idx = 0; // 旋转因子索引
            // 对当前子序列进行蝶形运算
            for (int j = 0; j < half; j++) {
                // 获取旋转因子W = wr + i*wi
                int16_t wr = Wc[idx];
                int16_t wi = Ws[idx]; // 已按方向传入
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
                int16_t tr = (int16_t)((int32_t)q15_mul(wr, vr) - (int32_t)q15_mul(wi, vi));
                int16_t ti = (int16_t)((int32_t)q15_mul(wr, vi) + (int32_t)q15_mul(wi, vr));

                // 蝶形运算：计算输出
                int32_t xr = (int32_t)ur + (int32_t)tr; // X[p] = X[p] + W*X[q]
                int32_t xi = (int32_t)ui + (int32_t)ti;
                int32_t yr = (int32_t)ur - (int32_t)tr; // X[q] = X[p] - W*X[q]
                int32_t yi = (int32_t)ui - (int32_t)ti;

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
                need_scale_this_stage = 1;
            }
            if (need_scale_this_stage) {
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
