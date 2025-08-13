#ifndef LUAT_FFT_CORE_Q15_H
#define LUAT_FFT_CORE_Q15_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 生成 Q15 旋转因子表（长度 N/2）：
// Wc[k] = cos(2πk/N) 的 Q15 表示；
// Ws[k] = -sin(2πk/N) 的 Q15 表示（前向FFT用负号）
void luat_fft_generate_twiddles_q15(int16_t* Wc, int16_t* Ws, int N);

// Q15 原地FFT/IFFT
// 参数：
// - real/imag: 长度 N 的 int16_t 数组（Q15）
// - inverse: 0=FFT, 1=IFFT（内部对 Ws 取反或外置 sign）
// - Wc/Ws: 长度 N/2 的 Q15 twiddle 表
// - block_scaling_mode: 0=每级固定右移1位；1=条件缩放（按级最大值）
// - out_scale_exp: 输出累计右移的位数（用于幅值/单位还原）
// 返回：0 成功，<0 表示参数错误
int luat_fft_inplace_q15(int16_t* real, int16_t* imag, int N, int inverse,
    const int16_t* Wc, const int16_t* Ws,
    int block_scaling_mode, int* out_scale_exp);

#ifdef __cplusplus
}
#endif

#endif // LUAT_FFT_CORE_Q15_H
