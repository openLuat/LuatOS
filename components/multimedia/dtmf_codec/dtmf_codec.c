#include "dtmf_codec.h"
#include "luat_mem.h"
#include <string.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static const float DTMF_ROW_FREQS[4] = {697.0f, 770.0f, 852.0f, 941.0f};
static const float DTMF_COL_FREQS[4] = {1209.0f, 1336.0f, 1477.0f, 1633.0f};
static const char DTMF_MAP[4][4] = {
    { '1', '2', '3', 'A' },
    { '4', '5', '6', 'B' },
    { '7', '8', '9', 'C' },
    { '*', '0', '#', 'D' },
};

void dtmf_decode_opts_default(dtmf_decode_opts_t* opts) {
    if (!opts) {
        return;
    }
    opts->frame_ms = 40.0f;
    opts->step_ms = 40.0f;
    opts->detect_ratio = 5.0f;
    opts->power_ratio = 2.5f;
    opts->twist_db = 6.0f;
    opts->min_consecutive = 2;
}

void dtmf_encode_opts_default(dtmf_encode_opts_t* opts) {
    if (!opts) {
        return;
    }
    opts->tone_ms = 100.0f;
    opts->pause_ms = 50.0f;
    opts->amplitude = 0.7f;
}

// Goertzel算法计算指定频点能量
static float goertzel_power(const int16_t* samples, uint32_t start, uint32_t end, uint32_t sample_rate, float freq) {
    if (!samples || end < start) {
        return 0.0f;
    }
    uint32_t n = end - start + 1;
    if (n == 0 || sample_rate == 0) {
        return 0.0f;
    }
    float k = 0.5f + ((float)n * freq) / (float)sample_rate;
    float w = (2.0f * (float)M_PI * k) / (float)n;
    float coeff = 2.0f * cosf(w);
    float q0 = 0.0f, q1 = 0.0f, q2 = 0.0f;
    for (uint32_t i = start; i <= end; ++i) {
        float s = (float)samples[i];
        q0 = coeff * q1 - q2 + s;
        q2 = q1;
        q1 = q0;
    }
    return q1 * q1 + q2 * q2 - coeff * q1 * q2;
}

// 选出最大和次大能量
static void pick_top_two(const float* powers, uint32_t count, float* max1, float* max2, int* idx1) {
    float m1 = -1.0f;
    float m2 = -1.0f;
    int index = -1;
    for (uint32_t i = 0; i < count; ++i) {
        float v = powers[i];
        if (v > m1) {
            m2 = m1;
            m1 = v;
            index = (int)i;
        } else if (v > m2) {
            m2 = v;
        }
    }
    if (m2 < 0.0f) {
        m2 = 0.0f;
    }
    if (max1) {
        *max1 = m1;
    }
    if (max2) {
        *max2 = m2;
    }
    if (idx1) {
        *idx1 = index;
    }
}

// 主峰/次峰比校验
static int power_ratio_ok(float max1, float max2, float ratio) {
    if (max1 <= 0.0f) {
        return 0;
    }
    if (max2 <= 0.0f) {
        return 1;
    }
    return (max1 / max2) >= ratio;
}

// 行列功率扭曲容差校验
static int twist_ok(float row_power, float col_power, float twist_db) {
    if (row_power <= 0.0f || col_power <= 0.0f) {
        return 0;
    }
    float twist = powf(10.0f, twist_db / 10.0f);
    float r = row_power / col_power;
    return (r >= (1.0f / twist)) && (r <= twist);
}

// 单帧检测DTMF符号
static char detect_frame(const int16_t* samples, uint32_t sample_rate, uint32_t start, uint32_t end,
                         const dtmf_decode_opts_t* opts) {
    float row_powers[4];
    float col_powers[4];
    double total_energy = 0.0;

    for (uint32_t i = start; i <= end; ++i) {
        double s = (double)samples[i];
        total_energy += s * s;
    }
    uint32_t n = end - start + 1;
    double avg_power = (n > 0) ? (total_energy / (double)n) : 0.0;

    for (uint32_t i = 0; i < 4; ++i) {
        row_powers[i] = goertzel_power(samples, start, end, sample_rate, DTMF_ROW_FREQS[i]);
        col_powers[i] = goertzel_power(samples, start, end, sample_rate, DTMF_COL_FREQS[i]);
    }

    float row_max, row_2nd, col_max, col_2nd;
    int row_idx, col_idx;
    pick_top_two(row_powers, 4, &row_max, &row_2nd, &row_idx);
    pick_top_two(col_powers, 4, &col_max, &col_2nd, &col_idx);

    float detect_ratio = opts ? opts->detect_ratio : 5.0f;
    float power_ratio = opts ? opts->power_ratio : 2.5f;
    float twist_db = opts ? opts->twist_db : 6.0f;

    if (row_max < (float)avg_power * detect_ratio) {
        return 0;
    }
    if (col_max < (float)avg_power * detect_ratio) {
        return 0;
    }
    if (!power_ratio_ok(row_max, row_2nd, power_ratio)) {
        return 0;
    }
    if (!power_ratio_ok(col_max, col_2nd, power_ratio)) {
        return 0;
    }
    if (!twist_ok(row_max, col_max, twist_db)) {
        return 0;
    }

    if (row_idx < 0 || col_idx < 0) {
        return 0;
    }

    return DTMF_MAP[row_idx][col_idx];
}

// PCM16LE解码入口
int dtmf_decode_pcm16(const int16_t* samples, uint32_t sample_count, uint32_t sample_rate,
                      const dtmf_decode_opts_t* opts,
                      char* seq, uint32_t seq_size,
                      dtmf_event_t* events, uint32_t* event_count, uint32_t max_events) {
    if (!samples || sample_count == 0 || sample_rate == 0) {
        if (seq && seq_size > 0) {
            seq[0] = 0;
        }
        if (event_count) {
            *event_count = 0;
        }
        return 0;
    }

    float frame_ms = opts ? opts->frame_ms : 40.0f;
    float step_ms = opts ? opts->step_ms : frame_ms;
    uint32_t min_cons = opts ? opts->min_consecutive : 2;

    uint32_t frame_len = (uint32_t)((float)sample_rate * frame_ms / 1000.0f);
    uint32_t step_len = (uint32_t)((float)sample_rate * step_ms / 1000.0f);
    if (frame_len < 1) frame_len = 1;
    if (step_len < 1) step_len = 1;

    char current = 0;
    uint32_t current_count = 0;
    uint32_t current_start = 0;

    uint32_t seq_idx = 0;
    uint32_t ev_idx = 0;

    for (uint32_t i = 0; i + frame_len <= sample_count; i += step_len) {
        char symbol = detect_frame(samples, sample_rate, i, i + frame_len - 1, opts);
        if (symbol && symbol == current) {
            current_count++;
        } else {
            if (current && current_count >= min_cons) {
                if (seq && seq_idx + 1 < seq_size) {
                    seq[seq_idx++] = current;
                }
                if (events && ev_idx < max_events) {
                    events[ev_idx].symbol = current;
                    events[ev_idx].start_sample = current_start + 1;
                    events[ev_idx].end_sample = i;
                    events[ev_idx].frames = current_count;
                    ev_idx++;
                }
            }
            if (symbol) {
                current = symbol;
                current_count = 1;
                current_start = i;
            } else {
                current = 0;
                current_count = 0;
                current_start = 0;
            }
        }
    }

    if (current && current_count >= min_cons) {
        if (seq && seq_idx + 1 < seq_size) {
            seq[seq_idx++] = current;
        }
        if (events && ev_idx < max_events) {
            events[ev_idx].symbol = current;
            events[ev_idx].start_sample = current_start + 1;
            events[ev_idx].end_sample = sample_count;
            events[ev_idx].frames = current_count;
            ev_idx++;
        }
    }

    if (seq && seq_size > 0) {
        seq[seq_idx] = 0;
    }
    if (event_count) {
        *event_count = ev_idx;
    }
    return (int)seq_idx;
}

// 将符号映射为行列频率
static int dtmf_symbol_to_freqs(char symbol, float* f1, float* f2) {
    for (int r = 0; r < 4; ++r) {
        for (int c = 0; c < 4; ++c) {
            if (DTMF_MAP[r][c] == symbol) {
                if (f1) *f1 = DTMF_ROW_FREQS[r];
                if (f2) *f2 = DTMF_COL_FREQS[c];
                return 1;
            }
        }
    }
    return 0;
}

// 计算编码输出样本数
uint32_t dtmf_encode_calc_samples(const char* digits, uint32_t sample_rate, const dtmf_encode_opts_t* opts) {
    if (!digits || sample_rate == 0) {
        return 0;
    }
    float tone_ms = opts ? opts->tone_ms : 100.0f;
    float pause_ms = opts ? opts->pause_ms : 50.0f;
    uint32_t tone_len = (uint32_t)((float)sample_rate * tone_ms / 1000.0f);
    uint32_t pause_len = (uint32_t)((float)sample_rate * pause_ms / 1000.0f);

    uint32_t count = 0;
    for (const char* p = digits; *p; ++p) {
        float f1, f2;
        if (dtmf_symbol_to_freqs(*p, &f1, &f2)) {
            count += tone_len;
            if (pause_len > 0) {
                count += pause_len;
            }
        }
    }
    return count;
}

// PCM16LE编码入口
int dtmf_encode_pcm16(const char* digits, uint32_t sample_rate, const dtmf_encode_opts_t* opts,
                      int16_t* out_samples, uint32_t max_samples, uint32_t* out_count) {
    if (!digits || !out_samples || sample_rate == 0) {
        if (out_count) {
            *out_count = 0;
        }
        return 0;
    }
    float tone_ms = opts ? opts->tone_ms : 100.0f;
    float pause_ms = opts ? opts->pause_ms : 50.0f;
    float amplitude = opts ? opts->amplitude : 0.7f;

    if (amplitude <= 1.0f) {
        amplitude = amplitude * 32767.0f;
    }
    if (amplitude > 32767.0f) {
        amplitude = 32767.0f;
    }
    if (amplitude < 0.0f) {
        amplitude = 0.0f;
    }

    uint32_t tone_len = (uint32_t)((float)sample_rate * tone_ms / 1000.0f);
    uint32_t pause_len = (uint32_t)((float)sample_rate * pause_ms / 1000.0f);
    if (tone_len < 1) tone_len = 1;

    uint32_t out_idx = 0;
    for (const char* p = digits; *p; ++p) {
        float f1, f2;
        if (!dtmf_symbol_to_freqs(*p, &f1, &f2)) {
            continue;
        }
        float w1 = 2.0f * (float)M_PI * f1 / (float)sample_rate;
        float w2 = 2.0f * (float)M_PI * f2 / (float)sample_rate;
        float phase1 = 0.0f;
        float phase2 = 0.0f;
        for (uint32_t i = 0; i < tone_len && out_idx < max_samples; ++i) {
            float s = sinf(phase1) + sinf(phase2);
            float v = s * (amplitude * 0.5f);
            if (v > 32767.0f) v = 32767.0f;
            if (v < -32768.0f) v = -32768.0f;
            out_samples[out_idx++] = (int16_t)v;
            phase1 += w1;
            phase2 += w2;
            if (phase1 > 2.0f * (float)M_PI) phase1 -= 2.0f * (float)M_PI;
            if (phase2 > 2.0f * (float)M_PI) phase2 -= 2.0f * (float)M_PI;
        }
        for (uint32_t i = 0; i < pause_len && out_idx < max_samples; ++i) {
            out_samples[out_idx++] = 0;
        }
    }

    if (out_count) {
        *out_count = out_idx;
    }
    return 1;
}
