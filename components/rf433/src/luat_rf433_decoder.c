/* RF433 纯 C 解码核心：当前支持这次遥控器的 EV1527 类 24 位波形。
 * 处理流程：原始边沿 -> 成对毛刺过滤 -> 当前帧状态机 -> 重复帧确认 -> 内部输出。
 * 主状态：WAIT_SYNC 等同步，READ_BITS 接收 24 位，WAIT_TAIL 检查结束同步。
 * 只调整同步电平不会翻转数据；物理 HIGH 短脉冲=1，长脉冲=0。
 * 本文件不操作 GPIO、任务、FIFO 或 Lua，这些由服务层负责。
 * 过滤器保留边沿原始时刻；调用方保证同一实例串行执行，输出函数不能阻塞。
 */
#include "luat_rf433_decoder.h"
#include <string.h>

/* 放弃当前帧，回到等待同步；保留滤波器和上一完整帧的重复确认历史。 */
static void rf433_decoder_drop_frame(luat_rf433_decoder_t *decoder)
{
    decoder->state = LUAT_RF433_DECODER_WAIT_SYNC;
    decoder->tail_phase = LUAT_RF433_DECODER_TAIL_START;
    decoder->bits = 0u;
    decoder->code = 0u;
    decoder->frame_start_us = 0u;
}

/* HIGH 同步时的数据配对检查：前一个 LOW 与当前 HIGH 都在数据范围内，
 * 并且一个短、一个长。这里返回是否合格，数据位的值仍只由 HIGH 宽度决定。
 */
static uint8_t rf433_decoder_pair_is_valid(luat_rf433_decoder_t *decoder, uint32_t low_us, uint32_t high_us)
{
    return (uint8_t)(decoder->have_low &&
        low_us >= decoder->config.pulse_min_us && low_us <= decoder->config.pulse_max_us &&
        high_us >= decoder->config.pulse_min_us && high_us <= decoder->config.pulse_max_us &&
        ((low_us < decoder->config.pulse_mid_us) != (high_us < decoder->config.pulse_mid_us)));
}

/* 帧尾已经通过检查：先和上一完整帧比较，再更新历史。
 * 首次收到只记录；窗口内再次收到同码才输出，后续同码重复帧也逐帧输出。
 * now_us 使用帧尾同步结束的采样时刻，而不是函数真正运行到这里的时刻。
 */
static void rf433_decoder_confirm_frame(luat_rf433_decoder_t *decoder, uint32_t now_us)
{
    uint8_t confirmed = (uint8_t)(decoder->last_valid && decoder->code == decoder->last_code &&
        (uint32_t)(now_us - decoder->last_frame_us) <= decoder->config.repeat_window_us);
    /* 即使本次未确认或换了键，也用本次完整帧更新历史。 */
    decoder->last_valid = 1u;
    decoder->last_code = decoder->code;
    decoder->last_frame_us = now_us;
    if (confirmed && decoder->emit) decoder->emit(decoder->emit_userdata, decoder->code, now_us);
}

/* 同步结束后重新开始接收：丢掉旧的未完成帧，下一数据 HIGH 才会计为第 1 位。 */
static void rf433_decoder_start_frame(luat_rf433_decoder_t *decoder, uint32_t end_us)
{
    decoder->state = LUAT_RF433_DECODER_READ_BITS;
    decoder->tail_phase = LUAT_RF433_DECODER_TAIL_START;
    decoder->bits = 0u;
    decoder->code = 0u;
    decoder->frame_start_us = end_us;
}

/* 检查一段已结束的 sync_level 电平，既用于寻找新同步，也用于确认旧帧尾。
 * width 是这段连续电平的宽度；end_us 是它结束时的原始采样时刻。
 * 返回值仅表示这段本身是否满足同步长度，新帧稍后由 rf433_decoder_handle_filtered_edge 启动。
 */
static uint8_t rf433_decoder_handle_sync_pulse(luat_rf433_decoder_t *decoder, uint32_t width, uint32_t end_us)
{
    uint8_t sync_valid = (uint8_t)(width > decoder->config.pulse_max_us &&
        width >= decoder->config.sync_min_us && width <= decoder->config.sync_max_us);
    /* 未接满 24 位时，只识别是否出现新同步，不尝试输出旧帧。 */
    if (decoder->state != LUAT_RF433_DECODER_WAIT_TAIL) return sync_valid;

    /* 已满 24 位：下面检查尾部顺序。LOW 同步允许一次尾部数据 LOW，
     * 随后必须是短 HIGH 头和长 LOW 同步；也允许直接接长 LOW 同步。
     */
    if (width <= decoder->config.pulse_max_us) {
        if (decoder->config.sync_level == 0u && decoder->tail_phase == LUAT_RF433_DECODER_TAIL_START && width >= decoder->config.pulse_min_us) {
            decoder->tail_phase = LUAT_RF433_DECODER_TAIL_SHORT_HIGH;
        } else {
            /* 多余数据脉冲或不合法的尾部顺序，不能继续当作 24 位有效帧。 */
            rf433_decoder_drop_frame(decoder);
        }
        return sync_valid;
    }
    /* 还在等待短 HIGH 头，不能跳过这个阶段直接确认长 LOW 帧尾。 */
    if (decoder->config.sync_level == 0u &&
        decoder->tail_phase == LUAT_RF433_DECODER_TAIL_SHORT_HIGH) {
        rf433_decoder_drop_frame(decoder);
        return sync_valid;
    }
    /* HIGH 同步的长 HIGH 前面必须有一个合格的短 LOW 头。
     * LOW 同步已经通过上面的阶段检查，不在这里重新解释数据极性。
     */
    if (decoder->config.sync_level == 1u &&
        (!decoder->have_low || decoder->low_us < decoder->config.pulse_min_us ||
         decoder->low_us >= decoder->config.pulse_mid_us)) {
        rf433_decoder_drop_frame(decoder);
        return sync_valid;
    }
    if (sync_valid) rf433_decoder_confirm_frame(decoder, end_us);
    /* 本段帧尾处理结束，无论长度合格与否都结束旧帧。
     * 不允许用后面的另一段同步片段补救断裂帧尾。
     */
    rf433_decoder_drop_frame(decoder);
    return sync_valid;
}

/* 处理一个已结束的物理 HIGH 段：接收数据位，或检查 LOW 同步的短 HIGH 尾头。
 * 数据规则固定为 HIGH 短=1、长=0，与同步电平配置无关。
 */
static void rf433_decoder_handle_high_pulse(luat_rf433_decoder_t *decoder, uint32_t start_us, uint32_t end_us)
{
    uint32_t width = end_us - start_us;
    uint8_t valid;
    if (decoder->state == LUAT_RF433_DECODER_WAIT_SYNC) return;
    /* 只在收到 HIGH 段时检查总接收时长，避免异常波形让一帧无限保留。
     * 这里没有启动超时定时器，只利用本次边沿的时间差。
     */
    if ((uint32_t)(end_us - decoder->frame_start_us) >
        (uint32_t)(LUAT_RF433_DECODER_BITS * 2u * decoder->config.pulse_max_us +
                   decoder->config.sync_max_us)) {
        rf433_decoder_drop_frame(decoder);
        return;
    }
    switch (decoder->state) {
    /* 已满 24 位：LOW 同步时只允许尾部短 HIGH 头，不能再累加数据。 */
    case LUAT_RF433_DECODER_WAIT_TAIL:
        if (decoder->config.sync_level == 0u) {
            if (decoder->tail_phase == LUAT_RF433_DECODER_TAIL_SHORT_HIGH &&
                width >= decoder->config.pulse_min_us && width < decoder->config.pulse_mid_us) {
                decoder->tail_phase = LUAT_RF433_DECODER_TAIL_SYNC;
            } else {
                rf433_decoder_drop_frame(decoder);
            }
        }
        /* 合法的 HIGH 同步帧尾会先在 rf433_decoder_handle_sync_pulse 中确认并清掉旧帧。 */
        return;
    case LUAT_RF433_DECODER_READ_BITS:
        if (decoder->config.sync_level == 0u) {
            /* LOW 同步后，第一个数据 HIGH 的前面是长 LOW 同步，不能拿它配对。
             * 后续 HIGH 前的 LOW 必须在数据范围内；这个 LOW 可能属于前一位，
             * 所以这里不要求它与当前 HIGH 一短一长，避免把相位判断错。
             */
            valid = (uint8_t)(width >= decoder->config.pulse_min_us &&
                              width <= decoder->config.pulse_max_us &&
                              (!decoder->bits || (decoder->have_low &&
                               decoder->low_us >= decoder->config.pulse_min_us &&
                               decoder->low_us <= decoder->config.pulse_max_us)));
        } else {
            /* HIGH 同步的数据相位允许用最近 LOW 与本次 HIGH 做互补配对。 */
            valid = rf433_decoder_pair_is_valid(decoder, decoder->low_us, width);
        }
        if (valid) {
            /* 先左移旧数据，再把新位放入最低位，按波形先后顺序累计 24 位。 */
            decoder->code = (decoder->code << 1) | (width < decoder->config.pulse_mid_us ? 1u : 0u);
            /* 接满后只切换到尾部检查，输出还要等待结束同步和重复确认。 */
            if (++decoder->bits == LUAT_RF433_DECODER_BITS) {
                decoder->state = LUAT_RF433_DECODER_WAIT_TAIL;
                decoder->tail_phase = LUAT_RF433_DECODER_TAIL_START;
            }
        } else {
            rf433_decoder_drop_frame(decoder);
        }
        return;
    default:
        rf433_decoder_drop_frame(decoder);
        return;
    }
}
/* 输入一个过滤后确认的边沿。
 * level 是这个边沿之后的新电平；本次算出的 width 属于刚结束的 last_level 电平段。
 * 例如从 HIGH 变 LOW 的下降沿到来时，才知道前一段 HIGH 究竟有多长。
 */
static void rf433_decoder_handle_filtered_edge(luat_rf433_decoder_t *decoder, uint8_t level, uint32_t now_us)
{
    uint32_t width;
    /* 首个已确认边沿只有起点，没有上一段完整宽度，先建立计时基准。 */
    if (!decoder->have_edge) {
        decoder->have_edge = 1u;
        decoder->last_level = level;
        decoder->last_edge_us = now_us;
        return;
    }
    /* uint32_t 无符号差值允许微秒计数在正常接收期间回绕。 */
    width = now_us - decoder->last_edge_us;
    uint8_t sync_valid = 0u;
    /* 先处理旧帧的同步/尾部，再处理数据；最后才用同一同步开启下一帧。 */
    if (decoder->last_level == decoder->config.sync_level)
        sync_valid = rf433_decoder_handle_sync_pulse(decoder, width, now_us);
    if (decoder->last_level == 1u)
        rf433_decoder_handle_high_pulse(decoder, decoder->last_edge_us, now_us);
    else {
        decoder->low_us = width;
        decoder->have_low = 1u;
    }
    /* 新帧必须最后启动，防止同一个同步 HIGH 被算成新帧的第 1 位。
     * 这个同步也可能刚完成上一帧，所以连续重复帧可以在这里衔接。
     */
    if (sync_valid) {
        rf433_decoder_start_frame(decoder, now_us);
    }
    decoder->last_level = level;
    decoder->last_edge_us = now_us;
}

/* 提交上一待定边沿：使用它最初采样的时间，保证脉宽和帧尾时间不被推迟。
 * 提交后，过滤器的已提交电平切换到该边沿之后的电平。
 */
static void rf433_decoder_commit_pending_edge(luat_rf433_decoder_t *decoder)
{
    rf433_decoder_handle_filtered_edge(decoder, decoder->filter_pending_level, decoder->filter_pending_us);
    decoder->filter_stable_level = decoder->filter_pending_level;
    decoder->filter_pending = 0u;
}

/* 原始 GPIO 边沿入口，分三步看：
 * 1. 首次输入或同电平异常时建立基准；
 * 2. 正常交替边沿时，取消短反向毛刺，或提交上一边沿并暂存当前边沿；
 * 3. 最后检查上一完整帧的重复窗口是否过期。
 * 注意：时间经过 glitch_us 本身不会提交 pending，仍要等下一个实际边沿。
 */
void luat_rf433_decoder_edge(luat_rf433_decoder_t *decoder, uint8_t level, uint32_t now_us)
{
    if (!decoder) return;
    /* 统一为物理电平 0/1，只在同步判断中使用 sync_level，不翻转数据电平。 */
    level = level ? 1u : 0u;
    if (!decoder->filter_have_raw || level == decoder->filter_raw_level) {
        /* 双边沿输入正常应 HIGH/LOW 交替。已初始化后又收到同一电平，
         * 说明原相位无法继续可靠解码（例如漏边沿），丢弃当前帧并重建基准。
         * 首次输入只需建立基准，不走异常清理。
         */
        if (decoder->filter_have_raw) {
            rf433_decoder_drop_frame(decoder);
            decoder->have_edge = decoder->have_low = decoder->filter_pending = 0u;
        }
        /* 过滤器从此有了首条记录，原始电平和已提交电平先设为一致。 */
        decoder->filter_have_raw = 1u;
        decoder->filter_raw_level = decoder->filter_stable_level = level;
        rf433_decoder_handle_filtered_edge(decoder, level, now_us);
    } else {
        /* 即使下面吞掉毛刺，也必须记住本次实际读到的原始电平。 */
        decoder->filter_raw_level = level;
        /* 回到原来的已提交电平，且反向停留严格小于 glitch_us：
         * 这是一对短反向切换，把两条边沿一起消除，原电平视为继续保持。
         * 恰好等于阈值时保留为真实变化；默认阈值为 150 微秒。
         */
        if (decoder->filter_pending && level == decoder->filter_stable_level && (uint32_t)(now_us - decoder->filter_pending_us) < decoder->config.glitch_us) {
            decoder->filter_pending = 0u;
        } else {
            /* 若已有 pending 且未被消除，先提交它，仍使用原始采样时刻。 */
            if (decoder->filter_pending) 
                rf433_decoder_commit_pending_edge(decoder);
            /* 当前边沿暂时不交给状态机，等后一个边沿判断它是否会被短脉冲抵消。 */
            decoder->filter_pending = 1u;
            decoder->filter_pending_level = level;
            decoder->filter_pending_us = now_us;
        }
    }
    /* 顺序不能反过来：先让 pending 帧尾按其采样时刻完成重复确认，
     * 再按本次原始边沿的 now_us 过期历史，避免错过重复窗口的精确边界。
     * 被过滤掉的毛刺也走到这里，持续噪声不会让旧重复历史一直有效。
     */
    if (decoder->last_valid && (uint32_t)(now_us - decoder->last_frame_us) > decoder->config.repeat_window_us)
        decoder->last_valid = 0u;
}

/* 初始化：先复制配置，再清上下文，允许 config 指向 decoder 自己的配置成员。 */
void luat_rf433_decoder_init(luat_rf433_decoder_t *decoder,
                             const luat_rf433_cfg_t *config,
                             luat_rf433_decoder_emit_t emit, void *userdata)
{
    luat_rf433_cfg_t saved_config;
    if (!decoder || !config) return;
    saved_config = *config;
    memset(decoder, 0, sizeof(*decoder));
    decoder->config = saved_config;
    decoder->emit = emit;
    decoder->emit_userdata = userdata;
}

/* 完整重置：保留配置和输出函数，清掉当前采集与重复确认历史。 */
void luat_rf433_decoder_reset(luat_rf433_decoder_t *decoder)
{
    luat_rf433_cfg_t saved_config;
    luat_rf433_decoder_emit_t saved_emit;
    void *saved_userdata;
    if (!decoder) return;
    saved_config = decoder->config;
    saved_emit = decoder->emit;
    saved_userdata = decoder->emit_userdata;
    luat_rf433_decoder_init(decoder, &saved_config, saved_emit, saved_userdata);
}

/* 仅重置采集：先保存上一完整帧历史，重置当前帧/边沿/滤波，再恢复历史。
 * 服务层在静默间隔超过同步上限、但尚未超过重复窗口时使用这个入口。
 */
void luat_rf433_decoder_reset_acquisition(luat_rf433_decoder_t *decoder)
{
    uint8_t saved_valid;
    uint32_t saved_code, saved_frame_us;
    if (!decoder) return;
    saved_valid = decoder->last_valid;
    saved_code = decoder->last_code;
    saved_frame_us = decoder->last_frame_us;
    luat_rf433_decoder_reset(decoder);
    decoder->last_valid = saved_valid;
    decoder->last_code = saved_code;
    decoder->last_frame_us = saved_frame_us;
}
