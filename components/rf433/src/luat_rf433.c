/* RF433 通用服务层：把平台边沿、通用解码器和业务读取接口连接起来。
 * GPIO 双边沿中断 -> 采样电平/时间 -> 解码器 -> 每路静态 FIFO -> 通知有数据。
 * open/read/close 由任务调用；中断只采集、解码和入队，不执行 Lua/业务回调。
 * 没有接收任务或超时定时器，待定边沿与通知失败都依赖后续真实 GPIO 中断推进。
 * 平台操作全部通过 luat_rf433_port.h 提供，本文件不依赖芯片、GPIO HAL 或 RTOS。
 */
#include <stdint.h>
#include <string.h>
#include "luat_gpio.h"
#include "luat_rf433.h"
#include "luat_rf433_decoder.h"
#include "luat_common_api.h"
#include "luat_rtos.h"
#include "luat_mcu.h"

// #include "luat_rf433_port.h"

/* 每个接收引脚各有一份状态，解码、重复确认和结果队列互不干扰。 */
typedef struct {
    luat_rf433_decoder_t decoder; /* 当前帧、滤波和上一完整帧的重复确认历史。 */
    luat_rf433_cfg_t config; /* open 时复制的参数及通知函数，之后作为固定配置。 */
    luat_rf433_result_t fifo[LUAT_RF433_FIFO_CAPACITY]; /* 已确认结果，按先后顺序读取。 */
    luat_rf433_handle_t handle; /* 槽位 + 本次开启的代数，供调用者识别这一轮实例。 */
    uint64_t last_tick; /* 上次原始中断的 64 位硬件时钟，用于检测过长的边沿间隔。 */
    uint32_t ticks_per_us; /* 本次开启时取得的固定 tick/us 比例，接收期间不能改变。 */
    uint32_t generation; /* 每次重用槽位递增，避免旧句柄误操作新接收实例。 */
    uint8_t head; /* 下一条要读出的结果位置。 */
    uint8_t tail; /* 下一条要写入的结果位置。 */
    uint8_t count; /* 当前待取结果数，用来区分空队列和满队列。 */
    uint8_t state; /* FREE/OPENING/ACTIVE/CLOSING 生命周期状态，只有 ACTIVE 可用。 */
    uint8_t have_tick; /* 是否已记录原始中断时刻；为 0 时不能计算前一个边沿间隔。 */
    uint8_t notify_needed; /* 空变非空后需通知；通知失败保留，后续中断继续尝试。 */
} rf433_receiver_t;

/* OPENING/CLOSING 暂时保留槽位，但 read 和 IRQ 都不使用它，防止配置到一半被访问。 */
enum { RF433_FREE, RF433_ACTIVE, RF433_OPENING, RF433_CLOSING };
static rf433_receiver_t rf433_receivers[LUAT_RF433_MAX_RECEIVERS];
/* 串行化任务中的 open/close。硬件配置移到临界区外，避免长时间屏蔽其他接收引脚的边沿。
 * read 不受这个标志限制，只需保护自己的短队列操作。
 */
static uint8_t rf433_config_busy;

/* 低 8 位为槽位编号（从 1 开始），再核对完整句柄及 ACTIVE 状态。
 * 因此 close 后的旧句柄、旧通知无法命中已重新 open 的实例。
 */
static rf433_receiver_t *rf433_find_receiver(luat_rf433_handle_t handle)
{
    uint32_t index = handle & 0xffu;
    if (!index || index > LUAT_RF433_MAX_RECEIVERS) return NULL;
    rf433_receiver_t *receiver = &rf433_receivers[index - 1u];
    return receiver->state == RF433_ACTIVE && receiver->handle == handle ? receiver : NULL;
}

/* 先填默认值，再由调用者指定 pin 或调整波形参数。
 * 默认识别连续 LOW 同步 6~18 ms，数据脉宽 200~1600 us，以 600 us 区分短/长。
 * sync_level 只选择同步/尾同步的电平；数据仍按物理 HIGH 短=1、长=0 解码。
 * <150 us 的成对反向毛刺会被通用滤波吞并；较长脉冲不会跨段重建同步。
 * 相同完整帧须在 500 ms 内再次出现才输出，首次完整帧只保存为确认依据。
 */
void luat_rf433_set_default_cfg(luat_rf433_cfg_t *config)
{
    if (!config) return;
    memset(config, 0, sizeof(*config));
    config->pin = -1;
    config->sync_level = 0;
    config->sync_min_us = 6000;
    config->sync_max_us = 18000;
    config->pulse_min_us = 200;
    config->pulse_max_us = 1600;
    config->pulse_mid_us = 600;
    config->glitch_us = 150;
    config->repeat_window_us = 500000;
}

/* 数据与同步的范围必须分开：0 < 数据下限 < 短长分界 < 数据上限 < 同步下限 <= 同步上限。
 * 毛刺阈值必须小于数据下限，避免把最短有效数据脉冲也滤掉；设为 0 可关闭毛刺消除。
 * 引脚须非负，同步电平只允许 0/1；重复窗口为正且小于 2^31 us。
 * 具体引脚是否支持即时双边沿接收，随后由平台接口单独判断。
 */
static int rf433_config_is_valid(const luat_rf433_cfg_t *config)
{
    return config && config->pin >= 0 &&
        config->sync_level <= 1 && config->pulse_min_us > 0 &&
        config->pulse_min_us < config->pulse_mid_us &&
        config->pulse_mid_us < config->pulse_max_us &&
        config->pulse_max_us < config->sync_min_us &&
        config->sync_min_us <= config->sync_max_us &&
        config->glitch_us < config->pulse_min_us &&
        config->repeat_window_us > 0 && config->repeat_window_us < 0x80000000u;
}

/* 解码器在 GPIO 中断内同步调用这里：仅复制确认后的结果，不申请堆内存、不阻塞。
 * 满队列直接丢弃新结果，保留尚未读取的旧结果和先后顺序；不会覆盖旧键码。
 * 只有“空 -> 非空”才提出一次数据可读通知，消费者收到通知后应一直读到队列为空。
 */
static void rf433_enqueue_result(void *userdata, uint32_t code, uint32_t timestamp_us)
{
    rf433_receiver_t *receiver = userdata;
    if (receiver->state != RF433_ACTIVE || receiver->count == LUAT_RF433_FIFO_CAPACITY) return;
    if (!receiver->count) receiver->notify_needed = 1;
    luat_rf433_result_t *result = &receiver->fifo[receiver->tail];
    memset(result, 0, sizeof(*result));
    result->code = code;
    result->timestamp_us = timestamp_us;
    result->bits = 24;
    result->protocol = LUAT_RF433_PROTOCOL_EV1527;
    receiver->tail = (receiver->tail + 1u) % LUAT_RF433_FIFO_CAPACITY;
    receiver->count++;
}

/* GPIO 中断的推进顺序：检查实例 -> 检查静默间隔 -> 喂一个原始边沿 -> 尝试通知。
 * 采样电平保持物理 0/1，时间由本次中断读取的硬件计数获得，再换算成微秒送入核心。
 * 这里记录的是中断采样时刻；结果 FIFO 只保存完整键码，不能补回未采集到的边沿。
 */
static int rf433_gpio_irq_handler(int pin, void *userdata)
{
    rf433_receiver_t *receiver = userdata;
    if (!receiver || receiver->state != RF433_ACTIVE || receiver->config.pin != pin) return 0;
    uint64_t tick = luat_mcu_tick64();
    /* 两次原始中断相隔超过最大同步宽度，旧采集已经无法衔接，先重建边沿基准。
     * 间隔仍在重复窗口内时保留上一完整帧；核心还会按完整帧时间检查是否真的过期。
     * 间隔超过重复窗口则连重复历史一起清掉。两种复位都保留已入 FIFO 的结果。
     * 这里比较 64 位原始 tick，避免 32 位微秒计数整圈回绕后把长时间静默误认成短间隔。
     */
    if (receiver->have_tick &&
        tick - receiver->last_tick > (uint64_t)receiver->config.sync_max_us * receiver->ticks_per_us) {
        if (tick - receiver->last_tick <=
            (uint64_t)receiver->config.repeat_window_us * receiver->ticks_per_us) {
            luat_rf433_decoder_reset_acquisition(&receiver->decoder);
        } else {
            luat_rf433_decoder_reset(&receiver->decoder);
        }
    }
    receiver->last_tick = tick;
    receiver->have_tick = 1;
    luat_rf433_decoder_edge(&receiver->decoder, (uint8_t)luat_gpio_get(pin),
                            (uint32_t)(tick / receiver->ticks_per_us));
    /* notify 只用于通知有数据（例如向 Lua 消息总线投递句柄），不能直接执行 Lua 或业务。
     * 返回 0 才清通知标志；失败保留，下次原始中断重试，即使 FIFO 已满也仍会尝试。
     * 没有后台定时器/任务重试。队列一直非空且通知已送达时，不会每帧重复发通知。
     */
    if (receiver->notify_needed && receiver->count && receiver->config.notify &&
        receiver->config.notify(receiver->handle, receiver->config.userdata) == 0) {
        receiver->notify_needed = 0;
    }
    return 0;
}

/* 任务上下文开启一条接收通道。先占槽位，再配置硬件，最后使实例可见。
 * 不允许从 ISR 调用：硬件配置和资源管理不能放在 GPIO 中断内。
 */
int luat_rf433_open(const luat_rf433_cfg_t *config, luat_rf433_handle_t *handle)
{
    // if (luat_rtos_get_ipsr()) return LUAT_ERROR_DEVICE_BUSY;
    if (!handle || !rf433_config_is_valid(config)) return LUAT_ERROR_PARAM_INVALID;
    /* 验证通过后先把输出句柄置空，只有整个开启流程成功才交给调用者。 */
    *handle = 0;
    /* 未移植的平台明确返回“不支持”，不进入 GPIO 配置，也不占用静态槽位。
     * 比例为原始 ticks/us；先保存到实例，后续中断不重新查询或改变计时单位。
     */
    uint32_t ticks_per_us = luat_mcu_us_period();
    if (!ticks_per_us) return LUAT_ERROR_PERMISSION_DENIED;
    uint32_t critical = luat_rtos_entry_critical();
    if (rf433_config_busy) {
        luat_rtos_exit_critical(critical);
        return LUAT_ERROR_DEVICE_BUSY;
    }
    /* 在短临界区中找空槽位；本服务内同引脚不可重复占用，OPENING/CLOSING 也算占用。 */
    rf433_receiver_t *receiver = NULL;
    uint32_t index = 0;
    for (uint32_t i = 0; i < LUAT_RF433_MAX_RECEIVERS; i++) {
        if (rf433_receivers[i].state != RF433_FREE && rf433_receivers[i].config.pin == config->pin) {
            luat_rtos_exit_critical(critical);
            return LUAT_ERROR_DEVICE_BUSY;
        }
        if (!receiver && rf433_receivers[i].state == RF433_FREE) {
            receiver = &rf433_receivers[i]; index = i;
        }
    }
    if (!receiver) {
        luat_rtos_exit_critical(critical);
        return LUAT_ERROR_PERMISSION_DENIED;
    }
    /* 高位编码代数、低 8 位编码槽位。代数跳过 0，句柄始终为正的 31 位值，兼容 32 位 Lua。
     * 标为 OPENING 后离开临界区，其他 read/IRQ 不会碰到尚未配置完成的实例。
     */
    receiver->generation = (receiver->generation + 1u) & 0x007fffffu;
    if (!receiver->generation) receiver->generation = 1;
    receiver->handle = (receiver->generation << 8) | (index + 1u);
    receiver->config = *config;
    receiver->ticks_per_us = ticks_per_us;
    receiver->state = RF433_OPENING;
    rf433_config_busy = 1;
    luat_rtos_exit_critical(critical);

    /* 硬件配置较慢，放在临界区外：其他通道仍能正常响应中断。
     * 先清自己的队列/时钟并初始化核心，再配置 GPIO 双边沿；IRQ 的参数指向本槽位。
     */
    receiver->head = receiver->tail = receiver->count = 0;
    receiver->notify_needed = receiver->have_tick = 0;
    receiver->last_tick = 0;
    luat_rf433_decoder_init(&receiver->decoder, &receiver->config, rf433_enqueue_result, receiver);

    luat_gpio_cfg_t gpio = {0};
    gpio.pin = receiver->config.pin;
    gpio.mode = LUAT_GPIO_IRQ;
    gpio.irq_type = LUAT_GPIO_BOTH_IRQ;
    gpio.pull = LUAT_GPIO_PULLUP;
    gpio.irq_cb = rf433_gpio_irq_handler;
    gpio.irq_args = receiver;
    int ret = luat_gpio_open(&gpio);
    /* 开启失败则关闭本次 GPIO 配置；最后仅用短临界区提交 ACTIVE 或归还 FREE 槽位。 */
    if (ret != 0) luat_gpio_close(receiver->config.pin);
    critical = luat_rtos_entry_critical();
    receiver->state = ret == 0 ? RF433_ACTIVE : RF433_FREE;
    rf433_config_busy = 0;
    if (ret == 0) *handle = receiver->handle;
    luat_rtos_exit_critical(critical);
    return ret == 0 ? LUAT_ERROR_NONE : LUAT_ERROR_DEVICE_BUSY;
}

/* 任务中每次读取一条结果：OK=已取到，EEMPTY=暂时无结果，ECLOSED=句柄已关闭/失效。
 * 查句柄、复制结果、移动 head 和减少 count 一起放在短临界区，避免和 ISR 入队交错。
 * 不等待新数据；收到通知后循环读取到 EEMPTY，已取出的结果可在任务中逐条处理。
 */
int luat_rf433_read(luat_rf433_handle_t handle, luat_rf433_result_t *result)
{
    // if (luat_rtos_get_ipsr()) return LUAT_ERROR_DEVICE_BUSY;
    if (!result) return LUAT_ERROR_PARAM_INVALID;
    uint32_t critical = luat_rtos_entry_critical();
    rf433_receiver_t *receiver = rf433_find_receiver(handle);
    int ret = LUAT_ERROR_PERMISSION_DENIED;
    if (receiver) {
        ret = LUAT_ERROR_NO_DATA;
        if (receiver->count) {
            *result = receiver->fifo[receiver->head];
            receiver->head = (receiver->head + 1u) % LUAT_RF433_FIFO_CAPACITY;
            receiver->count--;
            /* 最后一条被取走后恢复为空；下一次 ISR 入队会重新提出数据可读通知。 */
            if (!receiver->count) receiver->notify_needed = 0;
            ret = LUAT_ERROR_NONE;
        }
    }
    luat_rtos_exit_critical(critical);
    return ret;
}

/* 任务中关闭通道：先使实例不可用，再关闭硬件，最后释放槽位。
 * 老句柄立即失效；下一次 open 将得到新的代数句柄，不会继承旧 FIFO 或通知函数。
 */
int luat_rf433_close(luat_rf433_handle_t handle)
{
    // if (luat_rtos_get_ipsr()) return LUAT_ERROR_DEVICE_BUSY;
    uint32_t critical = luat_rtos_entry_critical();
    rf433_receiver_t *receiver = rf433_find_receiver(handle);
    if (!receiver) {
        luat_rtos_exit_critical(critical);
        return LUAT_ERROR_PERMISSION_DENIED;
    }
    if (rf433_config_busy) {
        luat_rtos_exit_critical(critical);
        return LUAT_ERROR_DEVICE_BUSY;
    }
    /* 短临界区只改生命周期状态。CLOSING 期间，后续 IRQ/read 不再使用本实例。 */
    receiver->state = RF433_CLOSING;
    rf433_config_busy = 1;
    luat_rtos_exit_critical(critical);
    /* 实际关闭 GPIO 放在临界区外，其他接收通道的中断继续运行。 */
    luat_gpio_close(receiver->config.pin);
    critical = luat_rtos_entry_critical();
    /* GPIO 关闭后，在短临界区中清理队列和通知入口并归还槽位，避免重用旧回调参数。 */
    receiver->count = 0;
    receiver->notify_needed = 0;
    receiver->config.notify = NULL;
    receiver->config.userdata = NULL;
    receiver->state = RF433_FREE;
    rf433_config_busy = 0;
    luat_rtos_exit_critical(critical);
    return LUAT_ERROR_NONE;
}
