#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Generate twiddle factors cos/sin for size N (N must be power of 2)
// Wc and Ws must have length at least N/2 (float32)
void luat_fft_generate_twiddles(int N, float* Wc, float* Ws);

// In-place iterative radix-2 FFT
// If Wc/Ws are NULL, twiddles are computed on the fly
void luat_fft_run_inplace(float* real, float* imag, int N,
    const float* Wc, const float* Ws);

// In-place IFFT with 1/N normalization
void luat_ifft_run_inplace(float* real, float* imag, int N,
    const float* Wc, const float* Ws);

// Frequency-domain integral: X(ω) -> X(ω)/(jω)
// n is FFT size, df is frequency resolution fs/n
void luat_fft_integral_inplace(float* xr, float* xi, int n, float df);

#ifdef __cplusplus
}
#endif
