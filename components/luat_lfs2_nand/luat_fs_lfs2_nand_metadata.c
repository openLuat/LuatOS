#include "luat_fs_lfs2_nand_metadata.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "luat_mcu.h"

#define LUAT_LFS2_NAND_SPACE_META_MAGIC 0x4C324E44u
#define LUAT_LFS2_NAND_SPACE_META_VERSION 1u
#define LUAT_LFS2_NAND_SPACE_META_REFRESH_RETRY 4u
#define LUAT_LFS2_NAND_SPACE_META_SLOW_US 5000u
/*
 * Hot stage note:
 * Refresh still verifies each write with "verify_scan", but retry loops now reuse the
 * previous verify result as the next attempt's "scan" seed to avoid redundant full rescans.
 */
static void luat_lfs2_nand_space_meta_log(const luat_lfs2_nand_space_meta_ops_t* ops, const char* message);

static uint64_t luat_lfs2_nand_space_meta_now_us(void) {
    uint64_t tick = luat_mcu_tick64();
    uint32_t tick_per_us = luat_mcu_us_period();
    if (tick_per_us == 0) {
        tick_per_us = 1;
    }
    return tick / tick_per_us;
}

static void luat_lfs2_nand_space_meta_log_timing(const luat_lfs2_nand_space_meta_ops_t* ops, const char* stage, uint32_t attempt, uint64_t cost_us) {
    char msg[128];
    if (cost_us < LUAT_LFS2_NAND_SPACE_META_SLOW_US) {
        return;
    }
    snprintf(msg, sizeof(msg), "space metadata %s attempt=%u cost=%lu us", stage, (unsigned int)attempt, (unsigned long)cost_us);
    luat_lfs2_nand_space_meta_log(ops, msg);
}

static void luat_lfs2_nand_space_meta_log_stage(const luat_lfs2_nand_space_meta_ops_t* ops,
                                                 const char* op,
                                                 const char* stage,
                                                 uint32_t attempt,
                                                 uint64_t cost_us,
                                                 int rc) {
    char msg[128];
    snprintf(msg, sizeof(msg),
             "LFS2N_META_REFRESH_STAGE op=%s stage=%s attempt=%u cost_us=%lu rc=%d",
             op ? op : "unknown",
             stage ? stage : "unknown",
             (unsigned int)attempt,
             (unsigned long)cost_us,
             rc);
    luat_lfs2_nand_space_meta_log(ops, msg);
}

static void luat_lfs2_nand_space_meta_log_budget(const luat_lfs2_nand_space_meta_ops_t* ops,
                                                  uint32_t step_limit,
                                                  uint32_t steps,
                                                  uint32_t budget_us,
                                                  uint64_t elapsed_us,
                                                  luat_lfs2_nand_space_meta_refresh_stage_t stage,
                                                  uint32_t attempt) {
    char msg[160];
    snprintf(msg, sizeof(msg),
             "LFS2N_META_REFRESH_BUDGET step_limit=%u steps=%u budget_us=%u elapsed_us=%lu stage=%u attempt=%u",
             (unsigned int)step_limit,
             (unsigned int)steps,
             (unsigned int)budget_us,
             (unsigned long)elapsed_us,
             (unsigned int)stage,
             (unsigned int)attempt);
    luat_lfs2_nand_space_meta_log(ops, msg);
}

static void luat_lfs2_nand_space_meta_update_timing(uint64_t* total_us, uint32_t* max_us, uint64_t cost_us) {
    if (total_us) {
        *total_us += cost_us;
    }
    if (max_us) {
        if (cost_us > (uint64_t)(*max_us)) {
            *max_us = (uint32_t)cost_us;
        }
    }
}

static void luat_lfs2_nand_space_meta_log_diag(const luat_lfs2_nand_space_meta_ops_t* ops,
                                                const luat_lfs2_nand_space_meta_refresh_state_t* state,
                                                const char* event,
                                                const char* result) {
    char msg[320];
    if (!state) {
        return;
    }
    snprintf(msg, sizeof(msg),
             "LFS2N_META_REFRESH_DIAG event=%s result=%s attempt=%u loops=%u scan_calls=%u verify_scan_calls=%u write_calls=%u retry_advances=%u verify_mismatch=%u scan_us_total=%llu scan_us_max=%u verify_scan_us_total=%llu verify_scan_us_max=%u write_us_total=%llu write_us_max=%u",
             event ? event : "unknown",
             result ? result : "na",
             (unsigned int)state->attempt,
             (unsigned int)state->step_loops,
             (unsigned int)state->scan_calls,
             (unsigned int)state->verify_scan_calls,
             (unsigned int)state->write_calls,
             (unsigned int)state->retry_advance_count,
             (unsigned int)state->verify_mismatch_count,
             (unsigned long long)state->scan_total_us,
             (unsigned int)state->scan_max_us,
             (unsigned long long)state->verify_scan_total_us,
             (unsigned int)state->verify_scan_max_us,
             (unsigned long long)state->write_total_us,
             (unsigned int)state->write_max_us);
    luat_lfs2_nand_space_meta_log(ops, msg);
}

static uint32_t luat_lfs2_nand_space_meta_crc32(const void* data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    const unsigned char* ptr = (const unsigned char*)data;
    size_t i = 0;
    while (i < len) {
        uint32_t byte = ptr[i++];
        uint32_t bit = 0;
        crc ^= byte;
        while (bit++ < 8u) {
            uint32_t mask = 0u - (crc & 1u);
            crc = (crc >> 1) ^ (0xEDB88320u & mask);
        }
    }
    return ~crc;
}

static uint32_t luat_lfs2_nand_space_meta_crc(const luat_lfs2_nand_space_meta_t* meta) {
    luat_lfs2_nand_space_meta_t copy = *meta;
    copy.crc = 0;
    return luat_lfs2_nand_space_meta_crc32(&copy, sizeof(copy));
}

static int luat_lfs2_nand_space_meta_seq_is_newer(uint32_t lhs, uint32_t rhs) {
    return ((int32_t)(lhs - rhs)) > 0;
}

void luat_lfs2_nand_space_meta_init(luat_lfs2_nand_space_meta_t* meta, uint32_t seq, uint32_t used, uint32_t total) {
    if (!meta) {
        return;
    }
    memset(meta, 0, sizeof(*meta));
    meta->magic = LUAT_LFS2_NAND_SPACE_META_MAGIC;
    meta->version = LUAT_LFS2_NAND_SPACE_META_VERSION;
    meta->seq = seq;
    meta->used = used;
    meta->total = total;
    meta->free = (used <= total) ? (total - used) : 0;
    meta->crc = luat_lfs2_nand_space_meta_crc(meta);
}

int luat_lfs2_nand_space_meta_validate(const luat_lfs2_nand_space_meta_t* meta) {
    if (!meta) {
        return -1;
    }
    if (meta->magic != LUAT_LFS2_NAND_SPACE_META_MAGIC || meta->version != LUAT_LFS2_NAND_SPACE_META_VERSION) {
        return -1;
    }
    if (meta->total == 0 || meta->used > meta->total || meta->free > meta->total) {
        return -1;
    }
    if ((meta->used + meta->free) != meta->total) {
        return -1;
    }
    return (luat_lfs2_nand_space_meta_crc(meta) == meta->crc) ? 0 : -1;
}

int luat_lfs2_nand_space_meta_select_latest(const luat_lfs2_nand_space_meta_t* slots, uint32_t slot_count, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot) {
    uint32_t i = 0;
    uint32_t best_slot = 0;
    int found = 0;
    luat_lfs2_nand_space_meta_t best = {0};

    if (!slots || slot_count == 0 || !out) {
        return -1;
    }
    while (i < slot_count) {
        if (luat_lfs2_nand_space_meta_validate(&slots[i]) == 0) {
            if (!found || luat_lfs2_nand_space_meta_seq_is_newer(slots[i].seq, best.seq)) {
                best = slots[i];
                best_slot = i;
                found = 1;
            }
        }
        i++;
    }
    if (!found) {
        return -1;
    }
    *out = best;
    if (out_slot) {
        *out_slot = best_slot;
    }
    return 0;
}

static void luat_lfs2_nand_space_meta_log(const luat_lfs2_nand_space_meta_ops_t* ops, const char* message) {
    if (ops && ops->log) {
        ops->log(ops->ctx, message);
    }
}

static int luat_lfs2_nand_space_meta_load(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot) {
    luat_lfs2_nand_space_meta_t slots[LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT];
    uint32_t i = 0;
    uint64_t t0 = 0;
    uint64_t cost_us = 0;
    int rc = -1;

    if (!ops || !ops->read_slot || !out) {
        return -1;
    }
    memset(slots, 0, sizeof(slots));
    t0 = luat_lfs2_nand_space_meta_now_us();
    while (i < LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT) {
        if (ops->read_slot(ops->ctx, i, &slots[i]) != 0) {
            memset(&slots[i], 0, sizeof(slots[i]));
        }
        i++;
    }
    cost_us = luat_lfs2_nand_space_meta_now_us() - t0;
    rc = luat_lfs2_nand_space_meta_select_latest(slots, LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT, out, out_slot);
    luat_lfs2_nand_space_meta_log_stage(ops, "load", "validate", 0, cost_us, rc);
    return rc;
}

void luat_lfs2_nand_space_meta_refresh_state_init(luat_lfs2_nand_space_meta_refresh_state_t* state,
                                                  const luat_lfs2_nand_space_meta_t* previous,
                                                  uint32_t previous_slot,
                                                  uint32_t max_retry) {
    if (!state) {
        return;
    }
    memset(state, 0, sizeof(*state));
    state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_BOOTSTRAP;
    state->max_retry = max_retry ? max_retry : LUAT_LFS2_NAND_SPACE_META_REFRESH_RETRY_DEFAULT;
    if (previous && luat_lfs2_nand_space_meta_validate(previous) == 0) {
        state->previous = *previous;
        state->has_previous = 1;
        state->previous_slot = previous_slot;
        state->seq = previous->seq + 1u;
        state->target_slot = (previous_slot + 1u) % LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT;
    }
}

void luat_lfs2_nand_space_meta_refresh_marker_from_state(const luat_lfs2_nand_space_meta_refresh_state_t* state,
                                                         luat_lfs2_nand_space_meta_refresh_marker_t* marker) {
    if (!state || !marker) {
        return;
    }
    marker->stage = state->stage;
    marker->attempt = state->attempt;
    marker->target_slot = state->target_slot;
    marker->used = state->used;
    marker->total = state->total;
}

luat_lfs2_nand_space_meta_step_result_t luat_lfs2_nand_space_meta_refresh_step(const luat_lfs2_nand_space_meta_ops_t* ops,
                                                                                luat_lfs2_nand_space_meta_refresh_state_t* state,
                                                                                const luat_lfs2_nand_space_meta_step_budget_t* budget,
                                                                                luat_lfs2_nand_space_meta_t* out,
                                                                                uint32_t* out_slot) {
    uint32_t step_limit = 1;
    uint32_t budget_us = 0;
    uint32_t steps = 0;
    uint64_t start_us = 0;

    if (!ops || !ops->scan || !ops->write_slot || !state) {
        return LUAT_LFS2_NAND_SPACE_META_STEP_ERROR;
    }
    if (budget && budget->max_steps > 0) {
        step_limit = budget->max_steps;
    }
    if (budget) {
        budget_us = budget->budget_us;
    }
    start_us = luat_lfs2_nand_space_meta_now_us();
    while (steps < step_limit) {
        int rc = 0;
        uint64_t t0 = 0;
        uint64_t cost_us = 0;
        state->step_loops++;
        if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_DONE) {
            if (out && state->candidate_valid) {
                *out = state->candidate;
            }
            if (out_slot) {
                *out_slot = state->target_slot;
            }
            return LUAT_LFS2_NAND_SPACE_META_STEP_DONE;
        }
        if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED) {
            return LUAT_LFS2_NAND_SPACE_META_STEP_ERROR;
        }
        if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_BOOTSTRAP) {
            state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_SCAN;
            steps++;
            continue;
        } else if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_SCAN) {
            if (ops->scan_mark) {
                ops->scan_mark(ops->ctx, "scan", state->attempt, state->step_loops, state->retry_advance_count);
            }
            t0 = luat_lfs2_nand_space_meta_now_us();
            rc = ops->scan(ops->ctx, &state->used, &state->total);
            cost_us = luat_lfs2_nand_space_meta_now_us() - t0;
            state->scan_calls++;
            luat_lfs2_nand_space_meta_update_timing(&state->scan_total_us, &state->scan_max_us, cost_us);
            luat_lfs2_nand_space_meta_log_timing(ops, "scan", state->attempt, cost_us);
            luat_lfs2_nand_space_meta_log_stage(ops, "refresh_step", "scan", state->attempt, cost_us, rc);
            if (rc != 0) {
                luat_lfs2_nand_space_meta_log_diag(ops, state, "scan_failed", "failed");
                luat_lfs2_nand_space_meta_log(ops, "space metadata scan failed");
                state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED;
                return LUAT_LFS2_NAND_SPACE_META_STEP_ERROR;
            }
            luat_lfs2_nand_space_meta_init(&state->candidate, state->seq, state->used, state->total);
            state->candidate_valid = 1;
            state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_WRITE;
        } else if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_WRITE) {
            if (!state->candidate_valid) {
                state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED;
                return LUAT_LFS2_NAND_SPACE_META_STEP_ERROR;
            }
            t0 = luat_lfs2_nand_space_meta_now_us();
            rc = ops->write_slot(ops->ctx, state->target_slot, &state->candidate);
            cost_us = luat_lfs2_nand_space_meta_now_us() - t0;
            state->write_calls++;
            luat_lfs2_nand_space_meta_update_timing(&state->write_total_us, &state->write_max_us, cost_us);
            luat_lfs2_nand_space_meta_log_timing(ops, "write", state->attempt, cost_us);
            luat_lfs2_nand_space_meta_log_stage(ops, "refresh_step", "write", state->attempt, cost_us, rc);
            if (rc != 0) {
                luat_lfs2_nand_space_meta_log_diag(ops, state, "write_failed", "failed");
                luat_lfs2_nand_space_meta_log(ops, "space metadata write failed");
                state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED;
                return LUAT_LFS2_NAND_SPACE_META_STEP_ERROR;
            }
            if (out) {
                *out = state->candidate;
            }
            if (out_slot) {
                *out_slot = state->target_slot;
            }
            state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_DONE;
            luat_lfs2_nand_space_meta_log_diag(ops, state, "write_done", "done");
            return LUAT_LFS2_NAND_SPACE_META_STEP_DONE;
        } else if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_VERIFY_SCAN) {
            uint32_t verify_used = 0;
            uint32_t verify_total = 0;
            if (ops->scan_mark) {
                ops->scan_mark(ops->ctx, "verify_scan", state->attempt, state->step_loops, state->retry_advance_count);
            }
            t0 = luat_lfs2_nand_space_meta_now_us();
            rc = ops->scan(ops->ctx, &verify_used, &verify_total);
            cost_us = luat_lfs2_nand_space_meta_now_us() - t0;
            state->verify_scan_calls++;
            luat_lfs2_nand_space_meta_update_timing(&state->verify_scan_total_us, &state->verify_scan_max_us, cost_us);
            luat_lfs2_nand_space_meta_log_timing(ops, "verify_scan", state->attempt, cost_us);
            luat_lfs2_nand_space_meta_log_stage(ops, "refresh_step", "verify_scan", state->attempt, cost_us, rc);
            if (rc != 0) {
                luat_lfs2_nand_space_meta_log_diag(ops, state, "verify_scan_failed", "failed");
                luat_lfs2_nand_space_meta_log(ops, "space metadata verify scan failed");
                state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED;
                return LUAT_LFS2_NAND_SPACE_META_STEP_ERROR;
            }
            state->used = verify_used;
            state->total = verify_total;
            if (state->candidate_valid &&
                verify_used == state->candidate.used &&
                verify_total == state->candidate.total) {
                if (out) {
                    *out = state->candidate;
                }
                if (out_slot) {
                    *out_slot = state->target_slot;
                }
                state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_DONE;
                luat_lfs2_nand_space_meta_log_diag(ops, state, "verify_match", "done");
                return LUAT_LFS2_NAND_SPACE_META_STEP_DONE;
            }
            state->verify_mismatch_count++;
            {
                char msg[224];
                snprintf(msg, sizeof(msg),
                         "LFS2N_META_REFRESH_DIAG event=verify_mismatch attempt=%u loop=%u retry_advances=%u verify_used=%u verify_total=%u candidate_used=%u candidate_total=%u",
                         (unsigned int)state->attempt,
                         (unsigned int)state->step_loops,
                         (unsigned int)state->retry_advance_count,
                         (unsigned int)verify_used,
                         (unsigned int)verify_total,
                         (unsigned int)state->candidate.used,
                         (unsigned int)state->candidate.total);
                luat_lfs2_nand_space_meta_log(ops, msg);
            }
            state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_RETRY_ADVANCE;
        } else {
            luat_lfs2_nand_space_meta_log_stage(ops, "refresh_step", "retry_advance", state->attempt, 0, 0);
            state->retry_advance_count++;
            luat_lfs2_nand_space_meta_log_diag(ops, state, "retry_advance", "pending");
            if (state->attempt + 1u >= state->max_retry) {
                luat_lfs2_nand_space_meta_log(ops, "space metadata did not stabilize");
                state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED;
                luat_lfs2_nand_space_meta_log_diag(ops, state, "retry_exhausted", "failed");
            } else {
                state->attempt++;
                state->seq++;
                state->target_slot = (state->target_slot + 1u) % LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT;
                state->candidate_valid = 0;
                state->stage = LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_SCAN;
            }
        }
        steps++;
        if (budget_us > 0 && (luat_lfs2_nand_space_meta_now_us() - start_us) >= budget_us) {
            luat_lfs2_nand_space_meta_log_budget(ops,
                                                 step_limit,
                                                 steps,
                                                 budget_us,
                                                 luat_lfs2_nand_space_meta_now_us() - start_us,
                                                 state->stage,
                                                 state->attempt);
            break;
        }
    }
    if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_DONE) {
        if (out && state->candidate_valid) {
            *out = state->candidate;
        }
        if (out_slot) {
            *out_slot = state->target_slot;
        }
        luat_lfs2_nand_space_meta_log_diag(ops, state, "step_done", "done");
        return LUAT_LFS2_NAND_SPACE_META_STEP_DONE;
    }
    if (state->stage == LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED) {
        luat_lfs2_nand_space_meta_log_diag(ops, state, "step_failed", "failed");
        return LUAT_LFS2_NAND_SPACE_META_STEP_ERROR;
    }
    return LUAT_LFS2_NAND_SPACE_META_STEP_MORE;
}

int luat_lfs2_nand_space_meta_refresh(const luat_lfs2_nand_space_meta_ops_t* ops, const luat_lfs2_nand_space_meta_t* previous, uint32_t previous_slot, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot) {
    luat_lfs2_nand_space_meta_t current = {0};
    uint32_t current_slot = 0;
    luat_lfs2_nand_space_meta_refresh_state_t state = {0};
    luat_lfs2_nand_space_meta_step_result_t step_rc = LUAT_LFS2_NAND_SPACE_META_STEP_MORE;

    if (!ops || !ops->scan || !ops->write_slot || !out) {
        return -1;
    }
    if (!previous || luat_lfs2_nand_space_meta_validate(previous) != 0) {
        if (luat_lfs2_nand_space_meta_load(ops, &current, &current_slot) == 0) {
            previous = &current;
            previous_slot = current_slot;
        }
    }
    luat_lfs2_nand_space_meta_refresh_state_init(&state, previous, previous_slot, LUAT_LFS2_NAND_SPACE_META_REFRESH_RETRY);
    while (1) {
        step_rc = luat_lfs2_nand_space_meta_refresh_step(ops, &state, NULL, out, out_slot);
        if (step_rc == LUAT_LFS2_NAND_SPACE_META_STEP_DONE) {
            return 0;
        }
        if (step_rc == LUAT_LFS2_NAND_SPACE_META_STEP_ERROR) {
            return -1;
        }
    }
}

int luat_lfs2_nand_space_meta_load_or_rebuild(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot, uint8_t* rebuilt) {
    uint64_t t0 = luat_lfs2_nand_space_meta_now_us();
    int rc = luat_lfs2_nand_space_meta_load(ops, out, out_slot);
    luat_lfs2_nand_space_meta_log_stage(ops, "load_or_rebuild", "load_validate", 0,
                                        luat_lfs2_nand_space_meta_now_us() - t0, rc);
    if (rc == 0) {
        if (rebuilt) {
            *rebuilt = 0;
        }
        return 0;
    }
    luat_lfs2_nand_space_meta_log(ops, "space metadata invalid, rebuilding");
    t0 = luat_lfs2_nand_space_meta_now_us();
    rc = luat_lfs2_nand_space_meta_refresh(ops, NULL, 0, out, out_slot);
    luat_lfs2_nand_space_meta_log_stage(ops, "load_or_rebuild", "rebuild", 0,
                                        luat_lfs2_nand_space_meta_now_us() - t0, rc);
    if (rc != 0) {
        return -1;
    }
    if (rebuilt) {
        *rebuilt = 1;
    }
    return 0;
}

int luat_lfs2_nand_space_meta_load_prefer_fast(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint8_t* rebuilt, uint8_t* persisted) {
    uint64_t t0 = 0;
    int rc = -1;
    if (persisted) {
        *persisted = 0;
    }
    t0 = luat_lfs2_nand_space_meta_now_us();
    rc = luat_lfs2_nand_space_meta_load_or_rebuild(ops, out, NULL, rebuilt);
    luat_lfs2_nand_space_meta_log_stage(ops, "load_prefer_fast", "load_validate", 0,
                                        luat_lfs2_nand_space_meta_now_us() - t0, rc);
    if (rc == 0) {
        if (persisted) {
            *persisted = 1;
        }
        return 0;
    }
    if (!ops || !ops->scan || !out) {
        return -1;
    }
    luat_lfs2_nand_space_meta_log(ops, "space metadata rebuild persistence failed, using scan result");
    t0 = luat_lfs2_nand_space_meta_now_us();
    rc = ops->scan(ops->ctx, &out->used, &out->total);
    luat_lfs2_nand_space_meta_log_stage(ops, "load_prefer_fast", "scan", 0,
                                        luat_lfs2_nand_space_meta_now_us() - t0, rc);
    if (rc != 0) {
        return -1;
    }
    luat_lfs2_nand_space_meta_init(out, 0, out->used, out->total);
    if (rebuilt) {
        *rebuilt = 1;
    }
    return 0;
}
