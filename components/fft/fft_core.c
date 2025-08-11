#include "fft_core.h"
#include <math.h>
#include <string.h>
#include <stdint.h>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static inline int reverse_bits(int x, int bits) {
    int y = 0;
    for (int i = 0; i < bits; i++) {
        y = (y << 1) | (x & 1);
        x >>= 1;
    }
    return y;
}

void fft_generate_twiddles(int N, float* Wc, float* Ws) {
    for (int k = 0; k < N/2; k++) {
        float angle = (float)(-2.0 * M_PI * (double)k / (double)N);
        Wc[k] = (float)cos(angle);
        Ws[k] = (float)sin(angle);
    }
}

static void fft_inplace_core(float* real, float* imag, int N, int inverse,
                             const float* Wc, const float* Ws) {
    // bit-reverse permutation
    int bits = 0; while ((1 << bits) < N) bits++;
    for (int i = 0; i < N; i++) {
        int j = reverse_bits(i, bits);
        if (j > i) {
            float tr = real[i]; real[i] = real[j]; real[j] = tr;
            float ti = imag[i]; imag[i] = imag[j]; imag[j] = ti;
        }
    }

    // iterative stages
    for (int len = 2; len <= N; len <<= 1) {
        int half = len >> 1;
        int step = N / len; // twiddle step
        for (int i = 0; i < N; i += len) {
            for (int j = 0; j < half; j++) {
                int idx = j * step;
                float wr, wi;
                if (Wc && Ws) {
                    wr = Wc[idx];
                    wi = Ws[idx];
                } else {
                    float angle = (float)(-2.0 * M_PI * (double)idx / (double)N);
                    wr = (float)cos(angle);
                    wi = (float)sin(angle);
                }
                if (inverse) wi = -wi;
                int p = i + j;
                int q = p + half;
                float tr = wr * real[q] - wi * imag[q];
                float ti = wr * imag[q] + wi * real[q];
                float ur = real[p];
                float ui = imag[p];
                real[p] = ur + tr;
                imag[p] = ui + ti;
                real[q] = ur - tr;
                imag[q] = ui - ti;
            }
        }
    }
}

void fft_run_inplace(float* real, float* imag, int N,
                     const float* Wc, const float* Ws) {
    fft_inplace_core(real, imag, N, 0, Wc, Ws);
}

void ifft_run_inplace(float* real, float* imag, int N,
                      const float* Wc, const float* Ws) {
    fft_inplace_core(real, imag, N, 1, Wc, Ws);
    // 1/N normalization
    float invN = (float)(1.0 / (double)N);
    for (int i = 0; i < N; i++) {
        real[i] *= invN;
        imag[i] *= invN;
    }
}

void fft_integral_inplace(float* xr, float* xi, int n, float df) {
    const float two_pi_df = (float)(2.0 * M_PI) * df;
    // positive freqs (exclude DC)
    for (int i = 1; i < n/2; i++) {
        float omega = two_pi_df * (float)i;
        if (omega != 0.0) {
            float xr0 = xr[i];
            float xi0 = xi[i];
            xr[i] =  xi0 / omega;
            xi[i] = -xr0 / omega;
        } else {
            xr[i] = 0.0; xi[i] = 0.0;
        }
    }
    // negative freqs
    for (int i = n/2 + 1; i < n; i++) {
        int k = i - n; // negative bin index
        float omega = two_pi_df * (float)k;
        if (omega != 0.0) {
            float xr0 = xr[i];
            float xi0 = xi[i];
            xr[i] =  xi0 / omega;
            xi[i] = -xr0 / omega;
        } else {
            xr[i] = 0.0; xi[i] = 0.0;
        }
    }
    // DC
    xr[0] = 0.0; xi[0] = 0.0;
}


