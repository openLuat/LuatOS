#include "dtmf_codec.h"
#include <string.h>

#define DTMF_Q10_ONE 1024
#define DTMF_Q15_ONE 32768
#define DTMF_Q30_ONE 1073741824

#define DTMF_PI_Q30 3373259426LL
#define DTMF_TWO_PI_Q30 6746518852LL

static const uint16_t DTMF_ROW_FREQS[4] = {697, 770, 852, 941};
static const uint16_t DTMF_COL_FREQS[4] = {1209, 1336, 1477, 1633};
static const char DTMF_MAP[4][4] = {
    { '1', '2', '3', 'A' },
    { '4', '5', '6', 'B' },
    { '7', '8', '9', 'C' },
    { '*', '0', '#', 'D' },
};

static const int32_t CORDIC_ATAN_Q30[16] = {
    843314857, 497837829, 263043836, 133525159,
    67021687, 33511064, 16754554, 8372258,
    4187890, 2093945, 1046973, 523486,
    261743, 130872, 65436, 32718
};

static const int32_t CORDIC_K_Q30 = 652032874;

static const uint16_t TWIST_DB_RATIO_Q10[13] = {
    1024, 1289, 1624, 2043, 2573, 3236, 4077,
    5132, 6463, 8139, 10240, 12880, 16220
};

static void cordic_sin_cos_q30(int64_t angle_q30, int32_t* cos_q30, int32_t* sin_q30) {
    int64_t ang = angle_q30 % DTMF_TWO_PI_Q30;
    if (ang > DTMF_PI_Q30) {
        ang -= DTMF_TWO_PI_Q30;
    } else if (ang < -DTMF_PI_Q30) {
        ang += DTMF_TWO_PI_Q30;
    }

    int32_t x = CORDIC_K_Q30;
    int32_t y = 0;
    int64_t z = ang;

    for (int i = 0; i < 16; ++i) {
        int32_t x_new;
        int32_t y_new;
        if (z >= 0) {
            x_new = x - (y >> i);
            y_new = y + (x >> i);
            z -= CORDIC_ATAN_Q30[i];
        } else {
            x_new = x + (y >> i);
            y_new = y - (x >> i);
            z += CORDIC_ATAN_Q30[i];
        }
        x = x_new;
        y = y_new;
    }

    if (cos_q30) {
        *cos_q30 = x;
    }
    if (sin_q30) {
        *sin_q30 = y;
    }
}

void dtmf_decode_opts_default(dtmf_decode_opts_t* opts) {
    if (!opts) {
        return;
    }
    opts->frame_ms = 40;
    opts->step_ms = 40;
    opts->detect_ratio_q10 = 5 * DTMF_Q10_ONE;
    opts->power_ratio_q10 = (uint32_t)(2 * DTMF_Q10_ONE + DTMF_Q10_ONE / 2);
    opts->twist_db = 6;
    opts->min_consecutive = 2;
}

void dtmf_encode_opts_default(dtmf_encode_opts_t* opts) {
    if (!opts) {
        return;
    }
    opts->tone_ms = 100;
    opts->pause_ms = 50;
    opts->amplitude_q15 = 22938;
}

static int64_t goertzel_power(const int16_t* samples, uint32_t start, uint32_t end,
                              uint32_t sample_rate, uint16_t freq) {
    if (!samples || end < start || sample_rate == 0) {
        return 0;
    }
    uint32_t n = end - start + 1;
    if (n == 0) {
        return 0;
    }

    uint32_t k = (uint32_t)(((uint64_t)n * freq + (sample_rate / 2)) / sample_rate);
    if (k == 0) {
        return 0;
    }

    int64_t angle_q30 = (DTMF_TWO_PI_Q30 * (int64_t)k + (int64_t)n / 2) / (int64_t)n;
    int32_t cos_q30 = 0;
    cordic_sin_cos_q30(angle_q30, &cos_q30, NULL);

    int32_t cos_q14 = (int32_t)(cos_q30 >> 16);
    int32_t coeff_q14 = cos_q14 << 1;

    int64_t q0 = 0, q1 = 0, q2 = 0;
    for (uint32_t i = start; i <= end; ++i) {
        q0 = ((int64_t)coeff_q14 * q1 >> 14) - q2 + samples[i];
        q2 = q1;
        q1 = q0;
    }

    int64_t term = ((int64_t)coeff_q14 * q1 >> 14);
    int64_t power = q1 * q1 + q2 * q2 - term * q2;
    if (power < 0) {
        power = 0;
    }
    return power;
}

static void pick_top_two(const int64_t* powers, uint32_t count, int64_t* max1, int64_t* max2, int* idx1) {
    int64_t m1 = -1;
    int64_t m2 = -1;
    int index = -1;
    for (uint32_t i = 0; i < count; ++i) {
        int64_t v = powers[i];
        if (v > m1) {
            m2 = m1;
            m1 = v;
            index = (int)i;
        } else if (v > m2) {
            m2 = v;
        }
    }
    if (m2 < 0) {
        m2 = 0;
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

static int power_ratio_ok(int64_t max1, int64_t max2, uint32_t ratio_q10) {
    if (max1 <= 0) {
        return 0;
    }
    if (max2 <= 0) {
        return 1;
    }
    return (max1 * DTMF_Q10_ONE) >= (max2 * (int64_t)ratio_q10);
}

static int twist_ok(int64_t row_power, int64_t col_power, uint32_t twist_db) {
    if (row_power <= 0 || col_power <= 0) {
        return 0;
    }
    if (twist_db > 12) {
        twist_db = 12;
    }
    uint32_t ratio_q10 = TWIST_DB_RATIO_Q10[twist_db];
    return (row_power * (int64_t)ratio_q10 >= col_power * DTMF_Q10_ONE) &&
           (row_power * DTMF_Q10_ONE <= col_power * (int64_t)ratio_q10);
}

static char detect_frame(const int16_t* samples, uint32_t sample_rate, uint32_t start, uint32_t end,
                         const dtmf_decode_opts_t* opts) {
    int64_t row_powers[4];
    int64_t col_powers[4];
    int64_t total_energy = 0;

    for (uint32_t i = start; i <= end; ++i) {
        int32_t s = samples[i];
        total_energy += (int64_t)s * s;
    }
    uint32_t n = end - start + 1;
    int64_t avg_power = (n > 0) ? (total_energy / (int64_t)n) : 0;

    for (uint32_t i = 0; i < 4; ++i) {
        row_powers[i] = goertzel_power(samples, start, end, sample_rate, DTMF_ROW_FREQS[i]);
        col_powers[i] = goertzel_power(samples, start, end, sample_rate, DTMF_COL_FREQS[i]);
    }

    int64_t row_max, row_2nd, col_max, col_2nd;
    int row_idx, col_idx;
    pick_top_two(row_powers, 4, &row_max, &row_2nd, &row_idx);
    pick_top_two(col_powers, 4, &col_max, &col_2nd, &col_idx);

    uint32_t detect_ratio_q10 = opts ? opts->detect_ratio_q10 : (5 * DTMF_Q10_ONE);
    uint32_t power_ratio_q10 = opts ? opts->power_ratio_q10 : (2 * DTMF_Q10_ONE + DTMF_Q10_ONE / 2);
    uint32_t twist_db = opts ? opts->twist_db : 6;

    if (row_max * DTMF_Q10_ONE < avg_power * (int64_t)detect_ratio_q10) {
        return 0;
    }
    if (col_max * DTMF_Q10_ONE < avg_power * (int64_t)detect_ratio_q10) {
        return 0;
    }
    if (!power_ratio_ok(row_max, row_2nd, power_ratio_q10)) {
        return 0;
    }
    if (!power_ratio_ok(col_max, col_2nd, power_ratio_q10)) {
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

    uint32_t frame_ms = opts ? opts->frame_ms : 40;
    uint32_t step_ms = opts ? opts->step_ms : frame_ms;
    uint32_t min_cons = opts ? opts->min_consecutive : 2;

    uint32_t frame_len = (sample_rate * frame_ms + 500) / 1000;
    uint32_t step_len = (sample_rate * step_ms + 500) / 1000;
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

static int dtmf_symbol_to_freqs(char symbol, uint16_t* f1, uint16_t* f2) {
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

uint32_t dtmf_encode_calc_samples(const char* digits, uint32_t sample_rate, const dtmf_encode_opts_t* opts) {
    if (!digits || sample_rate == 0) {
        return 0;
    }
    uint32_t tone_ms = opts ? opts->tone_ms : 100;
    uint32_t pause_ms = opts ? opts->pause_ms : 50;
    uint32_t tone_len = (sample_rate * tone_ms + 500) / 1000;
    uint32_t pause_len = (sample_rate * pause_ms + 500) / 1000;

    uint32_t count = 0;
    for (const char* p = digits; *p; ++p) {
        uint16_t f1, f2;
        if (dtmf_symbol_to_freqs(*p, &f1, &f2)) {
            count += tone_len;
            if (pause_len > 0) {
                count += pause_len;
            }
        }
    }
    return count;
}

int dtmf_encode_pcm16(const char* digits, uint32_t sample_rate, const dtmf_encode_opts_t* opts,
                      int16_t* out_samples, uint32_t max_samples, uint32_t* out_count) {
    if (!digits || !out_samples || sample_rate == 0) {
        if (out_count) {
            *out_count = 0;
        }
        return 0;
    }

    uint32_t tone_ms = opts ? opts->tone_ms : 100;
    uint32_t pause_ms = opts ? opts->pause_ms : 50;
    uint16_t amplitude_q15 = opts ? opts->amplitude_q15 : 22938;

    uint32_t tone_len = (sample_rate * tone_ms + 500) / 1000;
    uint32_t pause_len = (sample_rate * pause_ms + 500) / 1000;
    if (tone_len < 1) tone_len = 1;

    uint32_t out_idx = 0;
    for (const char* p = digits; *p; ++p) {
        uint16_t f1, f2;
        if (!dtmf_symbol_to_freqs(*p, &f1, &f2)) {
            continue;
        }

        int64_t angle1_q30 = (DTMF_TWO_PI_Q30 * (int64_t)f1 + (int64_t)sample_rate / 2) / (int64_t)sample_rate;
        int64_t angle2_q30 = (DTMF_TWO_PI_Q30 * (int64_t)f2 + (int64_t)sample_rate / 2) / (int64_t)sample_rate;
        int32_t cos1_q30 = 0, sin1_q30 = 0;
        int32_t cos2_q30 = 0, sin2_q30 = 0;
        cordic_sin_cos_q30(angle1_q30, &cos1_q30, &sin1_q30);
        cordic_sin_cos_q30(angle2_q30, &cos2_q30, &sin2_q30);

        int32_t s1_q30 = 0;
        int32_t c1_q30 = DTMF_Q30_ONE;
        int32_t s2_q30 = 0;
        int32_t c2_q30 = DTMF_Q30_ONE;

        for (uint32_t i = 0; i < tone_len && out_idx < max_samples; ++i) {
            int32_t s1_next = (int32_t)(((int64_t)s1_q30 * cos1_q30 + (int64_t)c1_q30 * sin1_q30) >> 30);
            int32_t c1_next = (int32_t)(((int64_t)c1_q30 * cos1_q30 - (int64_t)s1_q30 * sin1_q30) >> 30);
            int32_t s2_next = (int32_t)(((int64_t)s2_q30 * cos2_q30 + (int64_t)c2_q30 * sin2_q30) >> 30);
            int32_t c2_next = (int32_t)(((int64_t)c2_q30 * cos2_q30 - (int64_t)s2_q30 * sin2_q30) >> 30);
            s1_q30 = s1_next;
            c1_q30 = c1_next;
            s2_q30 = s2_next;
            c2_q30 = c2_next;

            int32_t s_q15 = (int32_t)((s1_q30 + s2_q30) >> 16);
            int32_t v = (int32_t)(((int64_t)amplitude_q15 * s_q15) >> 15);
            if (v > 32767) v = 32767;
            if (v < -32768) v = -32768;
            out_samples[out_idx++] = (int16_t)v;
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
