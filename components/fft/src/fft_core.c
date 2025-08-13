#include "fft_core.h"
#include "luat_base.h"
#include <math.h>
#include <stdint.h>
#include <string.h>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifndef __LUAT_C_CODE_IN_RAM__
#define __LUAT_C_CODE_IN_RAM__
#endif

__LUAT_C_CODE_IN_RAM__ static inline int reverse_bits(int x, int bits)
{
    int y = 0;
    for (int i = 0; i < bits; i++) {
        y = (y << 1) | (x & 1);
        x >>= 1;
    }
    return y;
}

__LUAT_C_CODE_IN_RAM__ void luat_fft_generate_twiddles(int N, float* Wc, float* Ws)
{
    for (int k = 0; k < N / 2; k++) {
        float angle = (float)(-2.0 * M_PI * (double)k / (double)N);
        Wc[k] = (float)cos(angle);
        Ws[k] = (float)sin(angle);
    }
}

__LUAT_C_CODE_IN_RAM__ static void fft_inplace_core(float* real, float* imag, int N, int inverse,
    const float* Wc, const float* Ws)
{
    // bit-reverse permutation 位逆序置换
    // 计算需要的位数来表示所有索引
    int bits = 0;
    while ((1 << bits) < N)
        bits++;

    // 对所有元素进行位逆序重排
    for (int i = 0; i < N; i++) {
        int j = reverse_bits(i, bits); // 获取位逆序后的索引
        if (j > i) { // 只交换一次，避免重复交换
            // 交换实部
            float tr = real[i];
            real[i] = real[j];
            real[j] = tr;
            // 交换虚部
            float ti = imag[i];
            imag[i] = imag[j];
            imag[j] = ti;
        }
    }

    // iterative stages 迭代阶段 - Cooley-Tukey算法的主要循环
    // len从2开始，每次翻倍，直到N
    for (int len = 2; len <= N; len <<= 1) {
        int half = len >> 1; // 当前阶段的半长度
        int step = N / len; // twiddle step 旋转因子步长

        // 处理每个长度为len的子序列
        for (int i = 0; i < N; i += len) {
            // 对当前子序列进行蝶形运算
            for (int j = 0; j < half; j++) {
                int idx = j * step; // 旋转因子索引
                float wr, wi; // 旋转因子的实部和虚部

                // 获取旋转因子
                if (Wc && Ws) {
                    // 使用预计算的旋转因子表
                    wr = Wc[idx];
                    wi = Ws[idx];
                } else {
                    // 实时计算旋转因子
                    float angle = (float)(-2.0 * M_PI * (double)idx / (double)N);
                    wr = (float)cos(angle);
                    wi = (float)sin(angle);
                }

                // 如果是逆变换，需要共轭旋转因子
                if (inverse)
                    wi = -wi;

                // 蝶形运算的两个数据点索引
                int p = i + j; // 上半部分索引
                int q = p + half; // 下半部分索引

                // 计算旋转后的值：W * X[q]
                float tr = wr * real[q] - wi * imag[q]; // 复数乘法实部
                float ti = wr * imag[q] + wi * real[q]; // 复数乘法虚部

                // 保存原始值
                float ur = real[p];
                float ui = imag[p];

                // 蝶形运算：更新两个数据点
                real[p] = ur + tr; // X[p] = X[p] + W*X[q]
                imag[p] = ui + ti;
                real[q] = ur - tr; // X[q] = X[p] - W*X[q]
                imag[q] = ui - ti;
            }
        }
    }
}

__LUAT_C_CODE_IN_RAM__ void luat_fft_run_inplace(float* real, float* imag, int N,
    const float* Wc, const float* Ws)
{
    fft_inplace_core(real, imag, N, 0, Wc, Ws);
}

__LUAT_C_CODE_IN_RAM__ void luat_ifft_run_inplace(float* real, float* imag, int N,
    const float* Wc, const float* Ws)
{
    fft_inplace_core(real, imag, N, 1, Wc, Ws);
    // 1/N normalization
    float invN = (float)(1.0 / (double)N);
    for (int i = 0; i < N; i++) {
        real[i] *= invN;
        imag[i] *= invN;
    }
}

__LUAT_C_CODE_IN_RAM__ void luat_fft_integral_inplace(float* xr, float* xi, int n, float df)
{
    // 计算角频率步长 Calculate angular frequency step
    const float two_pi_df = (float)(2.0 * M_PI) * df;

    // positive freqs (exclude DC) 正频率部分（排除直流分量）
    // 处理正频率分量，通过除以jω实现时域积分
    for (int i = 1; i < n / 2; i++) {
        float omega = two_pi_df * (float)i; // 当前频率的角频率
        if (omega != 0.0) {
            // 保存原始值
            float xr0 = xr[i];
            float xi0 = xi[i];
            // 执行 X(ω) / (jω) = (xr + j*xi) / (j*ω) = xi/ω - j*xr/ω
            xr[i] = xi0 / omega; // 实部：xi/ω
            xi[i] = -xr0 / omega; // 虚部：-xr/ω
        } else {
            // 频率为0时设为0（避免除零）
            xr[i] = 0.0;
            xi[i] = 0.0;
        }
    }

    // negative freqs 负频率部分
    // 处理负频率分量
    for (int i = n / 2 + 1; i < n; i++) {
        int k = i - n; // negative bin index 负频率索引
        float omega = two_pi_df * (float)k; // 负频率的角频率
        if (omega != 0.0) {
            // 保存原始值
            float xr0 = xr[i];
            float xi0 = xi[i];
            // 执行 X(ω) / (jω) 变换
            xr[i] = xi0 / omega; // 实部：xi/ω
            xi[i] = -xr0 / omega; // 虚部：-xr/ω
        } else {
            // 频率为0时设为0（避免除零）
            xr[i] = 0.0;
            xi[i] = 0.0;
        }
    }

    // DC 直流分量
    // 直流分量（ω=0）在积分后应为0
    xr[0] = 0.0;
    xi[0] = 0.0;
}
