#include <stdlib.h>
#include <fenv.h>
#include <math.h>
#include <string.h>

#include "luat_mem.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_ndk.h"
#include "luat_ndk_host.h"
#include "luat_ndk_abi.h"

#define LUAT_LOG_TAG "ndk"
#include "luat_log.h"

static void ndk_postexec(luat_ndk_t *ctx, uint32_t pc, uint32_t ir, uint32_t trap);

enum {
    NDK_FBINOP_ADD = 0,
    NDK_FBINOP_SUB = 1,
    NDK_FBINOP_MUL = 2,
    NDK_FBINOP_DIV = 3,
    NDK_FMINMAX_MIN = 4,
    NDK_FMINMAX_MAX = 5,
    NDK_FCMP_FEQ = 0,
    NDK_FCMP_FLT = 1,
    NDK_FCMP_FLE = 2,
    NDK_FSGNJ_COPY = 0,
    NDK_FSGNJ_NEGATE = 1,
    NDK_FSGNJ_XOR = 2
};

#if defined(__GNUC__) || defined(__clang__)
#pragma STDC FENV_ACCESS ON
#endif
#if defined(_MSC_VER)
#pragma float_control(precise, on, push)
#pragma fenv_access(on)
#endif
static uint32_t ndk_host_fexcepts_to_riscv_fflags(int host_excepts) {
    uint32_t fflags = 0;

    if (host_excepts & FE_INEXACT) {
        fflags |= 0x01u;
    }
    if (host_excepts & FE_UNDERFLOW) {
        fflags |= 0x02u;
    }
    if (host_excepts & FE_OVERFLOW) {
        fflags |= 0x04u;
    }
    if (host_excepts & FE_DIVBYZERO) {
        fflags |= 0x08u;
    }
    if (host_excepts & FE_INVALID) {
        fflags |= 0x10u;
    }
    return fflags;
}

static int ndk_riscv_rm_to_host_round(uint32_t rm, int *host_round) {
    if (!host_round) return 0;
    switch (rm) {
    case 0:
        *host_round = FE_TONEAREST;
        return 1;
    case 1:
        *host_round = FE_TOWARDZERO;
        return 1;
    case 2:
        *host_round = FE_DOWNWARD;
        return 1;
    case 3:
        *host_round = FE_UPWARD;
        return 1;
    default:
        return 0;
    }
}

static int ndk_resolve_host_round(luat_ndk_t *ctx, uint32_t rm, int *host_round) {
    uint32_t effective_rm = 0;

    if (!ctx || !host_round || ctx->flen != 32) return 0;
    effective_rm = (rm == 7) ? ((ctx->fcsr >> 5) & 0x7u) : rm;
    return ndk_riscv_rm_to_host_round(effective_rm, host_round);
}

static void ndk_merge_fflags(luat_ndk_t *ctx, uint32_t fflags) {
    if (!ctx || ctx->flen != 32 || (fflags & 0x1Fu) == 0) return;
    ctx->fcsr = (ctx->fcsr & ~0x1Fu) | ((ctx->fcsr & 0x1Fu) | (fflags & 0x1Fu));
}

static bool ndk_f32_is_nan(uint32_t bits) {
    return (bits & 0x7F800000u) == 0x7F800000u && (bits & 0x007FFFFFu) != 0;
}

static bool ndk_f32_is_snan(uint32_t bits) {
    return ndk_f32_is_nan(bits) && (bits & 0x00400000u) == 0;
}

static bool ndk_f32_is_inf(uint32_t bits) {
    return (bits & 0x7FFFFFFFu) == 0x7F800000u;
}

static uint32_t ndk_f32_canonicalize_nan(uint32_t bits) {
    return ndk_f32_is_nan(bits) ? 0x7FC00000u : bits;
}

static uint32_t ndk_fclass_s_bits(uint32_t bits) {
    uint32_t sign = bits >> 31;
    uint32_t exp = (bits >> 23) & 0xFFu;
    uint32_t frac = bits & 0x007FFFFFu;

    if (exp == 0xFFu) {
        if (frac == 0) {
            return sign ? 0x001u : 0x080u;
        }
        return (bits & 0x00400000u) ? 0x200u : 0x100u;
    }
    if (exp == 0) {
        if (frac == 0) {
            return sign ? 0x008u : 0x010u;
        }
        return sign ? 0x004u : 0x020u;
    }
    return sign ? 0x002u : 0x040u;
}

static int ndk_host_fcvt_s_w(uint32_t value, bool is_unsigned, int host_round, float *out, uint32_t *fflags_out) {
    fenv_t saved_env;
    int saved_mode = 0;
    int host_excepts = 0;
    volatile int32_t signed_value = (int32_t)value;
    volatile uint32_t unsigned_value = value;
    volatile float result_v = 0.0f;

    if (!out || !fflags_out) return 0;
    if (fegetenv(&saved_env) != 0) return 0;
    saved_mode = fegetround();
    if (saved_mode < 0) return 0;
    if (saved_mode != host_round && fesetround(host_round) != 0) {
        return 0;
    }
    if (feclearexcept(FE_ALL_EXCEPT) != 0) {
        (void)fesetenv(&saved_env);
        return 0;
    }

    result_v = is_unsigned ? (float)unsigned_value : (float)signed_value;
    host_excepts = fetestexcept(FE_ALL_EXCEPT);
    *out = result_v;
    *fflags_out = ndk_host_fexcepts_to_riscv_fflags(host_excepts);

    if (fesetenv(&saved_env) != 0) {
        if (saved_mode != FE_TONEAREST) {
            (void)fesetround(saved_mode);
        }
        LLOGW("restore host fenv failed after FCVT.S.W");
    }
    return 1;
}

static int ndk_host_fcvt_w_s(uint32_t bits, bool is_unsigned, int host_round, uint32_t *out, uint32_t *fflags_out) {
    fenv_t saved_env;
    int saved_mode = 0;
    int host_excepts = 0;
    float input = 0.0f;
    volatile float input_v = 0.0f;
    volatile float rounded_v = 0.0f;
    double rounded_d = 0.0;

    if (!out || !fflags_out) return 0;
    if (fegetenv(&saved_env) != 0) return 0;
    saved_mode = fegetround();
    if (saved_mode < 0) return 0;
    if (saved_mode != host_round && fesetround(host_round) != 0) {
        return 0;
    }
    if (feclearexcept(FE_ALL_EXCEPT) != 0) {
        (void)fesetenv(&saved_env);
        return 0;
    }

    if (ndk_f32_is_nan(bits)) {
        *out = is_unsigned ? 0xFFFFFFFFu : 0x7FFFFFFFu;
        *fflags_out = 0x10u;
    } else if (ndk_f32_is_inf(bits)) {
        if (bits & 0x80000000u) {
            *out = is_unsigned ? 0x00000000u : 0x80000000u;
        } else {
            *out = is_unsigned ? 0xFFFFFFFFu : 0x7FFFFFFFu;
        }
        *fflags_out = 0x10u;
    } else {
        memcpy(&input, &bits, sizeof(input));
        input_v = input;
        rounded_v = rintf(input_v);
        host_excepts = fetestexcept(FE_ALL_EXCEPT);
        rounded_d = (double)rounded_v;
        if (is_unsigned) {
            if (rounded_d < 0.0) {
                *out = 0x00000000u;
                *fflags_out = 0x10u;
            } else if (rounded_d > 4294967295.0) {
                *out = 0xFFFFFFFFu;
                *fflags_out = 0x10u;
            } else {
                *out = (uint32_t)rounded_v;
                *fflags_out = ndk_host_fexcepts_to_riscv_fflags(host_excepts) & 0x0Fu;
            }
        } else {
            if (rounded_d < -2147483648.0) {
                *out = 0x80000000u;
                *fflags_out = 0x10u;
            } else if (rounded_d > 2147483647.0) {
                *out = 0x7FFFFFFFu;
                *fflags_out = 0x10u;
            } else {
                *out = (uint32_t)(int32_t)rounded_v;
                *fflags_out = ndk_host_fexcepts_to_riscv_fflags(host_excepts) & 0x0Fu;
            }
        }
    }

    if (fesetenv(&saved_env) != 0) {
        if (saved_mode != FE_TONEAREST) {
            (void)fesetround(saved_mode);
        }
        LLOGW("restore host fenv failed after FCVT.W.S");
    }
    return 1;
}

static int ndk_host_fbinop(float lhs, float rhs, uint32_t op, int host_round, float *out, uint32_t *fflags_out) {
    fenv_t saved_env;
    int saved_mode = 0;
    int host_excepts = 0;
    volatile float lhs_v = lhs;
    volatile float rhs_v = rhs;
    volatile float result_v = 0.0f;

    if (!out || !fflags_out) return 0;
    if (fegetenv(&saved_env) != 0) return 0;
    saved_mode = fegetround();
    if (saved_mode < 0) return 0;
    if (saved_mode != host_round && fesetround(host_round) != 0) {
        return 0;
    }
    if (feclearexcept(FE_ALL_EXCEPT) != 0) {
        (void)fesetenv(&saved_env);
        return 0;
    }

    switch (op) {
    case NDK_FBINOP_ADD:
        result_v = lhs_v + rhs_v;
        break;
    case NDK_FBINOP_SUB:
        result_v = lhs_v - rhs_v;
        break;
    case NDK_FBINOP_MUL:
        result_v = lhs_v * rhs_v;
        break;
    case NDK_FBINOP_DIV:
        result_v = lhs_v / rhs_v;
        break;
    default:
        (void)fesetenv(&saved_env);
        return 0;
    }
    host_excepts = fetestexcept(FE_ALL_EXCEPT);
    *out = result_v;
    *fflags_out = ndk_host_fexcepts_to_riscv_fflags(host_excepts);

    if (fesetenv(&saved_env) != 0) {
        if (saved_mode != FE_TONEAREST) {
            (void)fesetround(saved_mode);
        }
        LLOGW("restore host fenv failed after FP binop");
    }
    return 1;
}

static int ndk_host_fmadd(float rs1, float rs2, float rs3, int host_round, float *out, uint32_t *fflags_out) {
    fenv_t saved_env;
    int saved_mode = 0;
    int host_excepts = 0;
    volatile float rs1_v = rs1;
    volatile float rs2_v = rs2;
    volatile float rs3_v = rs3;
    volatile float result_v = 0.0f;

    if (!out || !fflags_out) return 0;
    if (fegetenv(&saved_env) != 0) return 0;
    saved_mode = fegetround();
    if (saved_mode < 0) return 0;
    if (saved_mode != host_round && fesetround(host_round) != 0) {
        return 0;
    }
    if (feclearexcept(FE_ALL_EXCEPT) != 0) {
        (void)fesetenv(&saved_env);
        return 0;
    }

    result_v = fmaf(rs1_v, rs2_v, rs3_v);
    host_excepts = fetestexcept(FE_ALL_EXCEPT);
    *out = result_v;
    *fflags_out = ndk_host_fexcepts_to_riscv_fflags(host_excepts);

    if (fesetenv(&saved_env) != 0) {
        if (saved_mode != FE_TONEAREST) {
            (void)fesetround(saved_mode);
        }
        LLOGW("restore host fenv failed after FMADD.S");
    }
    return 1;
}

static int ndk_host_fsqrt(float input, int host_round, float *out, uint32_t *fflags_out) {
    fenv_t saved_env;
    int saved_mode = 0;
    int host_excepts = 0;
    volatile float input_v = input;
    volatile float result_v = 0.0f;

    if (!out || !fflags_out) return 0;
    if (fegetenv(&saved_env) != 0) return 0;
    saved_mode = fegetround();
    if (saved_mode < 0) return 0;
    if (saved_mode != host_round && fesetround(host_round) != 0) {
        return 0;
    }
    if (feclearexcept(FE_ALL_EXCEPT) != 0) {
        (void)fesetenv(&saved_env);
        return 0;
    }

    result_v = sqrtf(input_v);
    host_excepts = fetestexcept(FE_ALL_EXCEPT);
    *out = result_v;
    *fflags_out = ndk_host_fexcepts_to_riscv_fflags(host_excepts);

    if (fesetenv(&saved_env) != 0) {
        if (saved_mode != FE_TONEAREST) {
            (void)fesetround(saved_mode);
        }
        LLOGW("restore host fenv failed after FSQRT.S");
    }
    return 1;
}
#if defined(_MSC_VER)
#pragma float_control(pop)
#endif

static int ndk_fbinop_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rm, uint32_t op, uint32_t *out_bits) {
    uint32_t fflags = 0;
    uint32_t result_bits = 0;
    int host_round = FE_TONEAREST;
    float lhs = 0.0f;
    float rhs = 0.0f;
    float result = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;

    memcpy(&lhs, &rs1_bits, sizeof(lhs));
    memcpy(&rhs, &rs2_bits, sizeof(rhs));
    if (!ndk_host_fbinop(lhs, rhs, op, host_round, &result, &fflags)) return 0;
    memcpy(&result_bits, &result, sizeof(result));
    *out_bits = ndk_f32_canonicalize_nan(result_bits);
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fadd_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rm, uint32_t *out_bits) {
    return ndk_fbinop_s(ctx, rs1_bits, rs2_bits, rm, NDK_FBINOP_ADD, out_bits);
}

static int ndk_fsub_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rm, uint32_t *out_bits) {
    return ndk_fbinop_s(ctx, rs1_bits, rs2_bits, rm, NDK_FBINOP_SUB, out_bits);
}

static int ndk_fmul_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rm, uint32_t *out_bits) {
    return ndk_fbinop_s(ctx, rs1_bits, rs2_bits, rm, NDK_FBINOP_MUL, out_bits);
}

static int ndk_fdiv_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rm, uint32_t *out_bits) {
    return ndk_fbinop_s(ctx, rs1_bits, rs2_bits, rm, NDK_FBINOP_DIV, out_bits);
}

static int ndk_fminmax_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t op, uint32_t *out_bits) {
    bool rs1_nan = false;
    bool rs2_nan = false;
    bool rs1_snan = false;
    bool rs2_snan = false;
    bool rs1_is_zero = false;
    bool rs2_is_zero = false;
    uint32_t result_bits = 0;
    uint32_t fflags = 0;
    float lhs = 0.0f;
    float rhs = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    rs1_nan = ndk_f32_is_nan(rs1_bits);
    rs2_nan = ndk_f32_is_nan(rs2_bits);
    rs1_snan = ndk_f32_is_snan(rs1_bits);
    rs2_snan = ndk_f32_is_snan(rs2_bits);
    if (rs1_snan || rs2_snan) {
        fflags |= 0x10u;
    }

    if (rs1_nan && rs2_nan) {
        result_bits = 0x7FC00000u;
    } else if (rs1_nan) {
        result_bits = rs2_bits;
    } else if (rs2_nan) {
        result_bits = rs1_bits;
    } else {
        memcpy(&lhs, &rs1_bits, sizeof(lhs));
        memcpy(&rhs, &rs2_bits, sizeof(rhs));
        if (lhs < rhs) {
            result_bits = (op == NDK_FMINMAX_MIN) ? rs1_bits : rs2_bits;
        } else if (lhs > rhs) {
            result_bits = (op == NDK_FMINMAX_MIN) ? rs2_bits : rs1_bits;
        } else {
            rs1_is_zero = (rs1_bits & 0x7FFFFFFFu) == 0;
            rs2_is_zero = (rs2_bits & 0x7FFFFFFFu) == 0;
            if (rs1_is_zero && rs2_is_zero) {
                result_bits = (op == NDK_FMINMAX_MIN) ? (rs1_bits | rs2_bits) : (rs1_bits & rs2_bits);
            } else {
                result_bits = rs1_bits;
            }
        }
    }

    *out_bits = result_bits;
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fmin_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t *out_bits) {
    return ndk_fminmax_s(ctx, rs1_bits, rs2_bits, NDK_FMINMAX_MIN, out_bits);
}

static int ndk_fmax_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t *out_bits) {
    return ndk_fminmax_s(ctx, rs1_bits, rs2_bits, NDK_FMINMAX_MAX, out_bits);
}

static int ndk_fmadd_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rs3_bits, uint32_t rm, uint32_t *out_bits) {
    uint32_t fflags = 0;
    uint32_t result_bits = 0;
    int host_round = FE_TONEAREST;
    float rs1 = 0.0f;
    float rs2 = 0.0f;
    float rs3 = 0.0f;
    float result = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;

    memcpy(&rs1, &rs1_bits, sizeof(rs1));
    memcpy(&rs2, &rs2_bits, sizeof(rs2));
    memcpy(&rs3, &rs3_bits, sizeof(rs3));
    if (!ndk_host_fmadd(rs1, rs2, rs3, host_round, &result, &fflags)) return 0;
    memcpy(&result_bits, &result, sizeof(result));
    *out_bits = ndk_f32_canonicalize_nan(result_bits);
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fmsub_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rs3_bits, uint32_t rm, uint32_t *out_bits) {
    uint32_t fflags = 0;
    uint32_t result_bits = 0;
    uint32_t neg_rs3_bits = 0;
    int host_round = FE_TONEAREST;
    float rs1 = 0.0f;
    float rs2 = 0.0f;
    float neg_rs3 = 0.0f;
    float result = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;

    memcpy(&rs1, &rs1_bits, sizeof(rs1));
    memcpy(&rs2, &rs2_bits, sizeof(rs2));
    neg_rs3_bits = rs3_bits ^ 0x80000000u;
    memcpy(&neg_rs3, &neg_rs3_bits, sizeof(neg_rs3));
    if (!ndk_host_fmadd(rs1, rs2, neg_rs3, host_round, &result, &fflags)) return 0;
    memcpy(&result_bits, &result, sizeof(result));
    *out_bits = ndk_f32_canonicalize_nan(result_bits);
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fnmsub_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rs3_bits, uint32_t rm, uint32_t *out_bits) {
    uint32_t fflags = 0;
    uint32_t result_bits = 0;
    uint32_t neg_rs1_bits = 0;
    int host_round = FE_TONEAREST;
    float neg_rs1 = 0.0f;
    float rs2 = 0.0f;
    float rs3 = 0.0f;
    float result = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;

    neg_rs1_bits = rs1_bits ^ 0x80000000u;
    memcpy(&neg_rs1, &neg_rs1_bits, sizeof(neg_rs1));
    memcpy(&rs2, &rs2_bits, sizeof(rs2));
    memcpy(&rs3, &rs3_bits, sizeof(rs3));
    if (!ndk_host_fmadd(neg_rs1, rs2, rs3, host_round, &result, &fflags)) return 0;
    memcpy(&result_bits, &result, sizeof(result));
    *out_bits = ndk_f32_canonicalize_nan(result_bits);
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fnmadd_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t rs3_bits, uint32_t rm, uint32_t *out_bits) {
    uint32_t fflags = 0;
    uint32_t result_bits = 0;
    uint32_t neg_rs1_bits = 0;
    uint32_t neg_rs3_bits = 0;
    int host_round = FE_TONEAREST;
    float neg_rs1 = 0.0f;
    float rs2 = 0.0f;
    float neg_rs3 = 0.0f;
    float result = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;

    neg_rs1_bits = rs1_bits ^ 0x80000000u;
    neg_rs3_bits = rs3_bits ^ 0x80000000u;
    memcpy(&neg_rs1, &neg_rs1_bits, sizeof(neg_rs1));
    memcpy(&rs2, &rs2_bits, sizeof(rs2));
    memcpy(&neg_rs3, &neg_rs3_bits, sizeof(neg_rs3));
    if (!ndk_host_fmadd(neg_rs1, rs2, neg_rs3, host_round, &result, &fflags)) return 0;
    memcpy(&result_bits, &result, sizeof(result));
    *out_bits = ndk_f32_canonicalize_nan(result_bits);
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fsqrt_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rm, uint32_t *out_bits) {
    uint32_t fflags = 0;
    uint32_t result_bits = 0;
    int host_round = FE_TONEAREST;
    float input = 0.0f;
    float result = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;

    memcpy(&input, &rs1_bits, sizeof(input));
    if (!ndk_host_fsqrt(input, host_round, &result, &fflags)) return 0;
    memcpy(&result_bits, &result, sizeof(result));
    *out_bits = ndk_f32_canonicalize_nan(result_bits);
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fsgnj_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t op, uint32_t *out_bits) {
    uint32_t sign = 0;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    switch (op) {
    case NDK_FSGNJ_COPY:
        sign = rs2_bits & 0x80000000u;
        break;
    case NDK_FSGNJ_NEGATE:
        sign = (~rs2_bits) & 0x80000000u;
        break;
    case NDK_FSGNJ_XOR:
        sign = (rs1_bits ^ rs2_bits) & 0x80000000u;
        break;
    default:
        return 0;
    }
    *out_bits = (rs1_bits & 0x7FFFFFFFu) | sign;
    return 1;
}

static int ndk_fcmp_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rs2_bits, uint32_t op, uint32_t *out_bits) {
    bool rs1_nan = false;
    bool rs2_nan = false;
    bool rs1_snan = false;
    bool rs2_snan = false;
    uint32_t fflags = 0;
    float lhs = 0.0f;
    float rhs = 0.0f;
    bool result = false;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    rs1_nan = ndk_f32_is_nan(rs1_bits);
    rs2_nan = ndk_f32_is_nan(rs2_bits);
    rs1_snan = ndk_f32_is_snan(rs1_bits);
    rs2_snan = ndk_f32_is_snan(rs2_bits);
    if (rs1_nan || rs2_nan) {
        if (op == NDK_FCMP_FEQ) {
            if (rs1_snan || rs2_snan) {
                fflags = 0x10u;
            }
        } else {
            fflags = 0x10u;
        }
        *out_bits = 0;
        ndk_merge_fflags(ctx, fflags);
        return 1;
    }

    memcpy(&lhs, &rs1_bits, sizeof(lhs));
    memcpy(&rhs, &rs2_bits, sizeof(rhs));
    switch (op) {
    case NDK_FCMP_FEQ:
        result = lhs == rhs;
        break;
    case NDK_FCMP_FLT:
        result = lhs < rhs;
        break;
    case NDK_FCMP_FLE:
        result = lhs <= rhs;
        break;
    default:
        return 0;
    }
    *out_bits = result ? 1u : 0u;
    return 1;
}

static int ndk_fclass_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t *out_bits) {
    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    *out_bits = ndk_fclass_s_bits(rs1_bits);
    return 1;
}

static int ndk_fcvt_s_w(luat_ndk_t *ctx, uint32_t rs1_value, uint32_t rm, bool is_unsigned, uint32_t *out_bits) {
    uint32_t fflags = 0;
    int host_round = FE_TONEAREST;
    float result = 0.0f;

    if (!ctx || !out_bits || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;
    if (!ndk_host_fcvt_s_w(rs1_value, is_unsigned, host_round, &result, &fflags)) return 0;
    memcpy(out_bits, &result, sizeof(result));
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_fcvt_w_s(luat_ndk_t *ctx, uint32_t rs1_bits, uint32_t rm, bool is_unsigned, uint32_t *out_value) {
    uint32_t fflags = 0;
    int host_round = FE_TONEAREST;

    if (!ctx || !out_value || ctx->flen != 32) return 0;
    if (!ndk_resolve_host_round(ctx, rm, &host_round)) return 0;
    if (!ndk_host_fcvt_w_s(rs1_bits, is_unsigned, host_round, out_value, &fflags)) return 0;
    ndk_merge_fflags(ctx, fflags);
    return 1;
}

static int ndk_set_isa(luat_ndk_t *ndk, const char *isa) {
    const char *selected = isa;
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (selected == NULL || selected[0] == '\0') {
        selected = LUAT_NDK_ISA_RV32IMA;
    }
    if (strcmp(selected, LUAT_NDK_ISA_RV32IMA) != 0 && strcmp(selected, LUAT_NDK_ISA_RV32IMF) != 0) {
        return LUAT_NDK_ERR_PARAM;
    }
    memcpy(ndk->isa, selected, strlen(selected) + 1);
    ndk->flen = (strcmp(selected, LUAT_NDK_ISA_RV32IMF) == 0) ? 32 : 0;
    ndk->fcsr = 0;
    return LUAT_NDK_OK;
}

// mini-rv32ima configuration
#define MINI_RV32_RAM_SIZE (ctx->ram_size)
#define MINIRV32_POSTEXEC(pc, ir, trap) ndk_postexec(ctx, pc, ir, trap)
#define MINIRV32_LUATOS_RV32C_PATCH 1
#define MINIRV32_HAS_F_EXTENSION() (ctx->flen == 32)
#define MINIRV32_GET_MISA() (0x40401105u | (MINIRV32_HAS_F_EXTENSION() ? 0x20u : 0u))
#define MINIRV32_OTHERCSR_WRITE(csrno, value) luat_ndk_host_othercsr_write(ctx, csrno, value)
#define MINIRV32_OTHERCSR_READ(csrno, value) luat_ndk_host_othercsr_read(ctx, csrno, &value)
#define MINIRV32_FADD_S(rs1_bits, rs2_bits, rm, out_bits) ndk_fadd_s(ctx, rs1_bits, rs2_bits, rm, &(out_bits))
#define MINIRV32_FSUB_S(rs1_bits, rs2_bits, rm, out_bits) ndk_fsub_s(ctx, rs1_bits, rs2_bits, rm, &(out_bits))
#define MINIRV32_FMUL_S(rs1_bits, rs2_bits, rm, out_bits) ndk_fmul_s(ctx, rs1_bits, rs2_bits, rm, &(out_bits))
#define MINIRV32_FDIV_S(rs1_bits, rs2_bits, rm, out_bits) ndk_fdiv_s(ctx, rs1_bits, rs2_bits, rm, &(out_bits))
#define MINIRV32_FMADD_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) ndk_fmadd_s(ctx, rs1_bits, rs2_bits, rs3_bits, rm, &(out_bits))
#define MINIRV32_FMSUB_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) ndk_fmsub_s(ctx, rs1_bits, rs2_bits, rs3_bits, rm, &(out_bits))
#define MINIRV32_FNMSUB_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) ndk_fnmsub_s(ctx, rs1_bits, rs2_bits, rs3_bits, rm, &(out_bits))
#define MINIRV32_FNMADD_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) ndk_fnmadd_s(ctx, rs1_bits, rs2_bits, rs3_bits, rm, &(out_bits))
#define MINIRV32_FSQRT_S(rs1_bits, rm, out_bits) ndk_fsqrt_s(ctx, rs1_bits, rm, &(out_bits))
#define MINIRV32_FEQ_S(rs1_bits, rs2_bits, out_bits) ndk_fcmp_s(ctx, rs1_bits, rs2_bits, NDK_FCMP_FEQ, &(out_bits))
#define MINIRV32_FLT_S(rs1_bits, rs2_bits, out_bits) ndk_fcmp_s(ctx, rs1_bits, rs2_bits, NDK_FCMP_FLT, &(out_bits))
#define MINIRV32_FLE_S(rs1_bits, rs2_bits, out_bits) ndk_fcmp_s(ctx, rs1_bits, rs2_bits, NDK_FCMP_FLE, &(out_bits))
#define MINIRV32_FCLASS_S(rs1_bits, out_bits) ndk_fclass_s(ctx, rs1_bits, &(out_bits))
#define MINIRV32_FCVT_S_W(rs1_value, rm, out_bits) ndk_fcvt_s_w(ctx, rs1_value, rm, false, &(out_bits))
#define MINIRV32_FCVT_S_WU(rs1_value, rm, out_bits) ndk_fcvt_s_w(ctx, rs1_value, rm, true, &(out_bits))
#define MINIRV32_FCVT_W_S(rs1_bits, rm, out_bits) ndk_fcvt_w_s(ctx, rs1_bits, rm, false, &(out_bits))
#define MINIRV32_FCVT_WU_S(rs1_bits, rm, out_bits) ndk_fcvt_w_s(ctx, rs1_bits, rm, true, &(out_bits))
#define MINIRV32_FSGNJ_S(rs1_bits, rs2_bits, out_bits) ndk_fsgnj_s(ctx, rs1_bits, rs2_bits, NDK_FSGNJ_COPY, &(out_bits))
#define MINIRV32_FSGNJN_S(rs1_bits, rs2_bits, out_bits) ndk_fsgnj_s(ctx, rs1_bits, rs2_bits, NDK_FSGNJ_NEGATE, &(out_bits))
#define MINIRV32_FSGNJX_S(rs1_bits, rs2_bits, out_bits) ndk_fsgnj_s(ctx, rs1_bits, rs2_bits, NDK_FSGNJ_XOR, &(out_bits))
#define MINIRV32_FMIN_S(rs1_bits, rs2_bits, out_bits) ndk_fmin_s(ctx, rs1_bits, rs2_bits, &(out_bits))
#define MINIRV32_FMAX_S(rs1_bits, rs2_bits, out_bits) ndk_fmax_s(ctx, rs1_bits, rs2_bits, &(out_bits))
#define MINIRV32_HANDLE_MEM_STORE_CONTROL( addy, val ) if( luat_ndk_host_control_store(ctx, addy, val ) ) return val;
#define MINIRV32_STEPPROTO static int32_t MiniRV32IMAStep(luat_ndk_t *ctx, struct MiniRV32IMAState *state, uint8_t *image, uint32_t vProcAddress, uint32_t elapsedUs, int count)
#define MINIRV32_IMPLEMENTATION
#include "mini-rv32ima.h"

#define NDK_DEFAULT_STEP_BUDGET 32768
#define NDK_STEP_CHUNK 256
#define NDK_DEFAULT_ELAPSED_US 100
#define NDK_STOP_POLL_MS 10
#define NDK_DEINIT_WAIT_MS 1000

static inline bool ndk_state_active(luat_ndk_state_t state) {
    return state == LUAT_NDK_STATE_RUNNING || state == LUAT_NDK_STATE_STOPPING || state == LUAT_NDK_STATE_RESETTING;
}

static inline int ndk_lock(luat_ndk_t *ndk) {
    if (!ndk) return -1;
    luat_rtos_mutex_t lock = NULL;
    uint32_t critical = luat_rtos_entry_critical();
    if (!ndk->lock || ndk->lock_closing) {
        luat_rtos_exit_critical(critical);
        return -1;
    }
    ndk->lock_refs++;
    lock = ndk->lock;
    luat_rtos_exit_critical(critical);
    if (luat_rtos_mutex_lock(lock, LUAT_WAIT_FOREVER) != 0) {
        critical = luat_rtos_entry_critical();
        if (ndk->lock_refs) ndk->lock_refs--;
        luat_rtos_exit_critical(critical);
        return -1;
    }
    return 0;
}

static inline void ndk_unlock(luat_ndk_t *ndk) {
    if (!ndk) return;
    if (ndk->lock) {
        luat_rtos_mutex_unlock(ndk->lock);
    }
    uint32_t critical = luat_rtos_entry_critical();
    if (ndk->lock_refs) {
        ndk->lock_refs--;
    }
    luat_rtos_exit_critical(critical);
}

static void ndk_init_fail_cleanup(luat_ndk_t *ndk) {
    if (!ndk) return;
    if (ndk->ram) {
        luat_heap_free(ndk->ram);
        ndk->ram = NULL;
    }
    if (ndk->core) {
        luat_heap_free(ndk->core);
        ndk->core = NULL;
    }
    if (ndk->image_path) {
        luat_heap_free(ndk->image_path);
        ndk->image_path = NULL;
    }
    ndk->worker = NULL;
    ndk->thread_id = 0;
    ndk->image_size = 0;
    ndk->trap_pending = 0;
    ndk->stop_request = 0;
    ndk->fcsr = 0;
    ndk->flen = 0;
    ndk->isa[0] = '\0';
    ndk->lock_closing = 0;
    ndk->lock_refs = 0;
    ndk->state = LUAT_NDK_STATE_DEINIT;
    if (ndk->lock) {
        luat_rtos_mutex_delete(ndk->lock);
        ndk->lock = NULL;
    }
}

static bool ndk_should_stop(luat_ndk_t *ndk) {
    bool stop = true;
    if (!ndk) return true;
    if (ndk_lock(ndk) != 0) return true;
    stop = ndk->stop_request || ndk->state == LUAT_NDK_STATE_STOPPING || ndk->state == LUAT_NDK_STATE_DEINIT;
    ndk_unlock(ndk);
    return stop;
}

static void ndk_postexec(luat_ndk_t *ctx, uint32_t pc, uint32_t ir, uint32_t trap) {
    (void)pc;
    (void)ir;
    if (!ctx || trap == 0) return;
    ctx->trap_pending = 1;
    ctx->last_trap = trap;
}

static void ndk_reset_abi_state(luat_ndk_t *ndk) {
    size_t event_bytes = 0;
    size_t slot_count = 0;

    ndk->abi_features = LUAT_NDK_FEATURE_META | LUAT_NDK_FEATURE_TIME | LUAT_NDK_FEATURE_EVENT |
        LUAT_NDK_FEATURE_GPIO | LUAT_NDK_FEATURE_UART | LUAT_NDK_FEATURE_CRYPTO;
    ndk->last_error = LUAT_NDK_HOST_ERR_NONE;

    event_bytes = (ndk->exchange_size > (LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE))
        ? (ndk->exchange_size - (LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE))
        : 0;
    slot_count = event_bytes / sizeof(luat_ndk_event_t);
    if (slot_count > 8) {
        slot_count = 8;
    }
    ndk->event_slots = (uint16_t)slot_count;
    ndk->event_head = 0;
    ndk->event_tail = 0;
    ndk->event_enabled = 0;
    luat_ndk_gpio_reset(ndk);
    luat_ndk_uart_reset(ndk);

    if (ndk->ram && ndk->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE <= ndk->ram_size) {
        luat_ndk_event_header_t *hdr = (luat_ndk_event_header_t*)(ndk->ram + ndk->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET);
        hdr->host_write = 0;
        hdr->guest_read = 0;
        hdr->slot_count = ndk->event_slots;
        hdr->overflow = 0;
    }
}

static void ndk_reset_core(luat_ndk_t *ndk) {
    memset(ndk->core, 0, sizeof(MiniRV32IMAState));
    ndk->core->pc = MINIRV32_RAM_IMAGE_OFFSET;
    ndk->core->mtvec = MINIRV32_RAM_IMAGE_OFFSET;
    ndk->core->mstatus = 0x00001800; // machine mode, MPIE cleared
    ndk->core->extraflags = 3;       // machine mode
    ndk->trap_pending = 0;
    ndk->last_mcause = 0;
    ndk->last_mtval = 0;
    ndk->last_trap = 0;
    ndk->fcsr = 0;
    ndk_reset_abi_state(ndk);
}

static int ndk_reload_image(luat_ndk_t *ndk) {
    if (!ndk || !ndk->image_path) return LUAT_NDK_ERR_PARAM;
    
    FILE *fd = luat_fs_fopen(ndk->image_path, "rb");
    if (fd == NULL) {
        LLOGE("open %s fail", ndk->image_path);
        return LUAT_NDK_ERR_IO;
    }
    
    memset(ndk->ram, 0, ndk->ram_size);
    size_t readed = luat_fs_fread(ndk->ram, 1, ndk->image_size, fd);
    luat_fs_fclose(fd);
    
    if (readed != ndk->image_size) {
        LLOGE("read image %u/%u", (unsigned int)readed, (unsigned int)ndk->image_size);
        return LUAT_NDK_ERR_IO;
    }
    
    if (ndk->exchange_offset < ndk->ram_size) {
        memset(ndk->ram + ndk->exchange_offset, 0, ndk->exchange_size);
    }
    ndk_reset_core(ndk);
    luat_ndk_event_reset(ndk);
    return LUAT_NDK_OK;
}

static int ndk_load_image(luat_ndk_t *ndk, const char *path) {
    if (!ndk || !path) return LUAT_NDK_ERR_PARAM;
    
    size_t sz = luat_fs_fsize(path);
    if (sz == 0 || sz > ndk->exchange_offset) {
        LLOGE("image too large %u", (unsigned int)sz);
        return LUAT_NDK_ERR_IMAGE_TOO_LARGE;
    }
    ndk->image_size = sz;
    
    return ndk_reload_image(ndk);
}

static int ndk_exec_inner(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us, int32_t *retval) {
    if (!ndk || !ndk->core || !ndk->ram) return LUAT_NDK_ERR_PARAM;
    if (step_budget == 0) step_budget = NDK_DEFAULT_STEP_BUDGET;
    if (elapsed_us == 0) elapsed_us = NDK_DEFAULT_ELAPSED_US;

    int32_t ret = 0;

    ndk->trap_pending = 0;
    ndk->last_mcause = 0;
    ndk->last_mtval = 0;
    ndk->last_trap = 0;
    ndk->core->mcause = 0;
    ndk->core->mtval = 0;

    uint32_t left = step_budget;
    int rc = LUAT_NDK_OK;

    while (left > 0 && !ndk->trap_pending && !ndk_should_stop(ndk)) {
        uint32_t chunk = left > NDK_STEP_CHUNK ? NDK_STEP_CHUNK : left;
        ret = MiniRV32IMAStep(ndk, ndk->core, ndk->ram, MINIRV32_RAM_IMAGE_OFFSET, elapsed_us, chunk);
        if (ret == 0x5555) {
            return LUAT_NDK_OK;
        }
        left -= chunk;
        if (ndk->core->mcause) break;
    }

    if (ndk_should_stop(ndk)) {
        return LUAT_NDK_ERR_TIMEOUT;
    }

    ndk->last_mcause = ndk->core->mcause;
    ndk->last_mtval = ndk->core->mtval;

    if (ndk->trap_pending || ndk->last_mcause) {
        rc = LUAT_NDK_ERR_TRAP;
        if (ndk->last_mcause == 11) {
            rc = LUAT_NDK_OK;
            if (retval) *retval = (int32_t)ndk->core->regs[10];
        }
    } else if (left == 0) {
        rc = LUAT_NDK_ERR_TIMEOUT;
    }
    return rc;
}

int luat_ndk_init(luat_ndk_t *ndk, const char *path, size_t mem_size, size_t exchange_size, const char *isa) {
    if (!ndk || !path) return LUAT_NDK_ERR_PARAM;
    memset(ndk, 0, sizeof(luat_ndk_t));
    ndk->state = LUAT_NDK_STATE_DEINIT;
    if (luat_rtos_mutex_create(&ndk->lock) != 0 || !ndk->lock) {
        ndk->lock = NULL;
        return LUAT_NDK_ERR_NOMEM;
    }
    ndk->state = LUAT_NDK_STATE_IDLE;
    ndk->stop_request = 0;
    ndk->lock_closing = 0;
    ndk->lock_refs = 0;

    if (mem_size == 0) mem_size = LUAT_NDK_DEFAULT_RAM_SIZE;
    if (exchange_size == 0) exchange_size = LUAT_NDK_DEFAULT_EXCHANGE_SIZE;

    if (mem_size > LUAT_NDK_MAX_RAM_SIZE || exchange_size >= mem_size) {
        ndk_init_fail_cleanup(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    int rc = ndk_set_isa(ndk, isa);
    if (rc != LUAT_NDK_OK) {
        ndk_init_fail_cleanup(ndk);
        return rc;
    }

    ndk->ram_size = mem_size;
    ndk->exchange_size = exchange_size;
    ndk->exchange_offset = mem_size - exchange_size;

    ndk->ram = luat_heap_malloc(ndk->ram_size);
    ndk->core = luat_heap_malloc(sizeof(MiniRV32IMAState));
    if (ndk->ram == NULL || ndk->core == NULL) {
        ndk_init_fail_cleanup(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    memset(ndk->ram, 0, ndk->ram_size);
    memset(ndk->core, 0, sizeof(MiniRV32IMAState));

    size_t plen = strlen(path);
    ndk->image_path = luat_heap_malloc(plen + 1);
    if (ndk->image_path == NULL) {
        ndk_init_fail_cleanup(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    memcpy(ndk->image_path, path, plen);
    ndk->image_path[plen] = '\0';

    rc = ndk_load_image(ndk, path);
    if (rc != LUAT_NDK_OK) {
        ndk_init_fail_cleanup(ndk);
        return rc;
    }

    ndk_reset_core(ndk);

    return LUAT_NDK_OK;
}

void luat_ndk_deinit(luat_ndk_t *ndk) {
    if (!ndk) return;
    uint32_t critical = luat_rtos_entry_critical();
    bool deinit_in_progress = ndk->lock && ndk->lock_closing;
    luat_rtos_exit_critical(critical);
    if (deinit_in_progress) {
        uint32_t wait_left = NDK_DEINIT_WAIT_MS;
        while (wait_left > 0) {
            luat_rtos_task_sleep(NDK_STOP_POLL_MS);
            if (wait_left >= NDK_STOP_POLL_MS) wait_left -= NDK_STOP_POLL_MS;
            else wait_left = 0;
            critical = luat_rtos_entry_critical();
            bool done = ndk->lock == NULL;
            luat_rtos_exit_critical(critical);
            if (done) return;
        }
        return;
    }

    if (!ndk->lock) {
        luat_ndk_gpio_reset(ndk);
        luat_ndk_uart_reset(ndk);
        if (ndk->ram) {
            luat_heap_free(ndk->ram);
            ndk->ram = NULL;
        }
        if (ndk->core) {
            luat_heap_free(ndk->core);
            ndk->core = NULL;
        }
        if (ndk->image_path) {
            luat_heap_free(ndk->image_path);
            ndk->image_path = NULL;
        }
        ndk->worker = NULL;
        ndk->state = LUAT_NDK_STATE_DEINIT;
        ndk->stop_request = 0;
        ndk->lock_closing = 0;
        ndk->lock_refs = 0;
        ndk->trap_pending = 0;
        ndk->image_size = 0;
        ndk->thread_id = 0;
        ndk->fcsr = 0;
        ndk->flen = 0;
        ndk->isa[0] = '\0';
        return;
    }

    int stop_rc = luat_ndk_stop_thread(ndk, NDK_DEINIT_WAIT_MS);
    if (stop_rc == LUAT_NDK_ERR_TIMEOUT) {
        LLOGE("deinit timeout waiting worker");
        return;
    }

    if (ndk_lock(ndk) != 0) return;
    luat_ndk_gpio_reset(ndk);
    luat_ndk_uart_reset(ndk);
    uint8_t *ram = ndk->ram;
    MiniRV32IMAState *core = ndk->core;
    char *image_path = ndk->image_path;
    ndk->ram = NULL;
    ndk->core = NULL;
    ndk->image_path = NULL;
    ndk->worker = NULL;
    ndk->state = LUAT_NDK_STATE_DEINIT;
    ndk->stop_request = 0;
    ndk->trap_pending = 0;
    ndk->image_size = 0;
    ndk->thread_id = 0;
    ndk->fcsr = 0;
    ndk->flen = 0;
    ndk->isa[0] = '\0';
    ndk->lock_closing = 1;
    ndk_unlock(ndk);

    uint32_t wait_left = NDK_DEINIT_WAIT_MS;
    while (wait_left > 0) {
        critical = luat_rtos_entry_critical();
        uint32_t lock_refs = ndk->lock_refs;
        luat_rtos_exit_critical(critical);
        if (lock_refs == 0) break;
        luat_rtos_task_sleep(NDK_STOP_POLL_MS);
        if (wait_left >= NDK_STOP_POLL_MS) {
            wait_left -= NDK_STOP_POLL_MS;
        } else {
            wait_left = 0;
        }
    }
    critical = luat_rtos_entry_critical();
    luat_rtos_mutex_t lock = (ndk->lock_refs == 0) ? ndk->lock : NULL;
    if (lock) {
        ndk->lock = NULL;
    }
    luat_rtos_exit_critical(critical);
    if (lock) {
        luat_rtos_mutex_delete(lock);
    }
    else {
        LLOGE("deinit timeout waiting lock refs");
    }

    if (ram) {
        luat_heap_free(ram);
    }
    if (core) {
        luat_heap_free(core);
    }
    if (image_path) {
        luat_heap_free(image_path);
    }
}

int luat_ndk_reset(luat_ndk_t *ndk) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk_state_active(ndk->state) || ndk->worker != NULL) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_BUSY;
    }
    if (ndk->state == LUAT_NDK_STATE_DEINIT || ndk->image_path == NULL || ndk->image_size == 0 || !ndk->ram || !ndk->core) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_IO;
    }

    ndk->state = LUAT_NDK_STATE_RESETTING;
    int rc = ndk_reload_image(ndk);
    if (ndk->state == LUAT_NDK_STATE_RESETTING) {
        ndk->state = LUAT_NDK_STATE_IDLE;
    }
    ndk_unlock(ndk);
    return rc;
}

int luat_ndk_set_data(luat_ndk_t *ndk, const void *data, size_t len, size_t offset) {
    if (!ndk || !data) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state == LUAT_NDK_STATE_DEINIT || !ndk->ram) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (offset >= ndk->exchange_size) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (len > ndk->exchange_size - offset) len = ndk->exchange_size - offset;
    memcpy(ndk->ram + ndk->exchange_offset + offset, data, len);
    ndk_unlock(ndk);
    return (int)len;
}

int luat_ndk_get_data(luat_ndk_t *ndk, void *out, size_t len, size_t offset, size_t *actual) {
    if (!ndk || !out) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state == LUAT_NDK_STATE_DEINIT || !ndk->ram) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (offset >= ndk->exchange_size) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (len > ndk->exchange_size - offset) len = ndk->exchange_size - offset;
    memcpy(out, ndk->ram + ndk->exchange_offset + offset, len);
    if (actual) *actual = len;
    ndk_unlock(ndk);
    return LUAT_NDK_OK;
}

int luat_ndk_exec(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us, int32_t *retval) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state != LUAT_NDK_STATE_IDLE || ndk->worker != NULL) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_BUSY;
    }
    ndk->state = LUAT_NDK_STATE_RUNNING;
    ndk->stop_request = 0;
    ndk_unlock(ndk);
    int rc = ndk_exec_inner(ndk, step_budget, elapsed_us, retval);
    if (ndk_lock(ndk) == 0) {
        if (ndk->state != LUAT_NDK_STATE_DEINIT) {
            ndk->state = LUAT_NDK_STATE_IDLE;
        }
        ndk->stop_request = 0;
        ndk_unlock(ndk);
    }
    return rc;
}

typedef struct ndk_thread_arg {
    luat_ndk_t *ctx;
    uint32_t step_budget;
    uint32_t elapsed_us;
} ndk_thread_arg_t;

static void ndk_thread_entry(void *param) {
    ndk_thread_arg_t *arg = (ndk_thread_arg_t *)param;
    if (!arg || !arg->ctx) {
        luat_heap_free(arg);
        return;
    }
    luat_ndk_t *ctx = arg->ctx;
    luat_rtos_task_handle handle = NULL;
    if (ndk_lock(ctx) == 0) {
        handle = ctx->worker;
        ndk_unlock(ctx);
    }
    ndk_exec_inner(ctx, arg->step_budget, arg->elapsed_us, NULL);
    if (ndk_lock(ctx) == 0) {
        ctx->worker = NULL;
        if (ctx->state != LUAT_NDK_STATE_DEINIT) {
            ctx->state = LUAT_NDK_STATE_IDLE;
            ctx->stop_request = 0;
        }
        ndk_unlock(ctx);
    }
    luat_heap_free(arg);
    if (handle) {
        luat_rtos_task_delete(handle);
    }
}

int luat_ndk_start_thread(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state != LUAT_NDK_STATE_IDLE || ndk->worker != NULL) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_BUSY;
    }
    ndk_thread_arg_t *arg = luat_heap_malloc(sizeof(ndk_thread_arg_t));
    if (!arg) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    arg->ctx = ndk;
    arg->step_budget = step_budget;
    arg->elapsed_us = elapsed_us;
    ndk->state = LUAT_NDK_STATE_RUNNING;
    ndk->stop_request = 0;
    int rc = luat_rtos_task_create(&ndk->worker, 2048, 60, "ndk", ndk_thread_entry, arg, 0);
    if (rc) {
        ndk->state = LUAT_NDK_STATE_IDLE;
        ndk->worker = NULL;
        ndk_unlock(ndk);
        luat_heap_free(arg);
        return LUAT_NDK_ERR_NOMEM;
    }
    static uint32_t g_thread_counter = 1;
    ndk->thread_id = g_thread_counter++;
    uint32_t tid = ndk->thread_id;
    ndk_unlock(ndk);
    return (int)tid;
}

int luat_ndk_stop_thread(luat_ndk_t *ndk, uint32_t wait_ms) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state == LUAT_NDK_STATE_DEINIT || (ndk->state == LUAT_NDK_STATE_IDLE && ndk->worker == NULL)) {
        ndk_unlock(ndk);
        return LUAT_NDK_OK;
    }
    if (ndk->state == LUAT_NDK_STATE_RUNNING) {
        ndk->state = LUAT_NDK_STATE_STOPPING;
    }
    ndk->stop_request = 1;
    ndk_unlock(ndk);

    uint32_t wait_left = wait_ms;
    while (wait_left > 0) {
        luat_rtos_task_sleep(NDK_STOP_POLL_MS);
        if (wait_left >= NDK_STOP_POLL_MS) {
            wait_left -= NDK_STOP_POLL_MS;
        } else {
            wait_left = 0;
        }
        if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_TIMEOUT;
        bool done = (ndk->state == LUAT_NDK_STATE_DEINIT) || (ndk->state == LUAT_NDK_STATE_IDLE && ndk->worker == NULL);
        if (done) {
            ndk->stop_request = 0;
            ndk_unlock(ndk);
            return LUAT_NDK_OK;
        }
        ndk_unlock(ndk);
    }

    return LUAT_NDK_ERR_TIMEOUT;
}

bool luat_ndk_is_busy(luat_ndk_t *ndk) {
    if (!ndk) return false;
    if (ndk_lock(ndk) != 0) return true;
    bool busy = ndk_state_active(ndk->state) || ndk->worker != NULL;
    ndk_unlock(ndk);
    return busy;
}

uint32_t luat_ndk_exchange_addr(const luat_ndk_t *ndk) {
    if (!ndk) return 0;
    return MINIRV32_RAM_IMAGE_OFFSET + ndk->exchange_offset;
}
