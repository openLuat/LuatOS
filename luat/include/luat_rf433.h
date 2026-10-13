#ifndef LUAT_RF433_H
#define LUAT_RF433_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 每个接收器独占一个 GPIO，并各自保存解码状态和结果 FIFO。 */
#define LUAT_RF433_MAX_RECEIVERS 4u
#define LUAT_RF433_FIFO_CAPACITY 16u
#define LUAT_RF433_PROTOCOL_EV1527 1u

/* 不透明句柄：不是 GPIO 编号，关闭后原句柄失效。 */
typedef uint32_t luat_rf433_handle_t;

/** GPIO 中断中的唤醒钩子，只做中断安全、不会阻塞的通知操作。
 * 返回 0 表示通知已接收；失败时，模块在后续 GPIO 边沿再次尝试通知。
 * 此处不能调用 Lua、处理业务或调用 open/read/close；业务交给应用任务。
 * 每个句柄应只有一个消费者，收到通知后反复 read，直到返回 EEMPTY。
 * userdata 在 close 成功返回前必须始终有效，不能提前释放或销毁。
 */
typedef int (*luat_rf433_notify_t)(luat_rf433_handle_t handle, void *userdata);

typedef struct {
    int pin;                    /* 接收模块 DAT 所接的普通 GPIO，必须由本模块独占。 */
    uint8_t sync_level;          /* 同步电平：0=LOW，1=HIGH，只影响起始/结束同步。 数据始终按物理 HIGH 解码：短 HIGH=1，长 HIGH=0。 */
    uint16_t sync_min_us;        /* 同步最短时长，单位 us，默认 6000。必须大于数据上限。 */
    uint16_t sync_max_us;        /* 同步最长时长，默认 18000；上下界均包含在有效范围内。 识别的是普通毛刺滤波后的连续同步电平，不拼接多段同步。 */
    uint16_t pulse_min_us;       /* 合法数据脉宽下限，默认 200 us。 */
    uint16_t pulse_max_us;       /* 合法数据脉宽上限，默认 1600 us。 */
    uint16_t pulse_mid_us;       /* 长短分界，默认 600 us：HIGH 小于此值为 1，否则为 0。 */
    uint16_t glitch_us;          /* 通用毛刺阈值，默认 150 us，同步和数据阶段均使用。反向脉冲严格短于此值才合并；真实 280 us 数据不会被合并。 */
    uint32_t repeat_window_us;   /* 重复确认窗口，默认 500000 us。两帧码值相同且同步结束间隔不超过窗口才输出；继续按住时，后续相同帧继续输出。 */
    luat_rf433_notify_t notify;  /* FIFO 有结果时唤醒应用的中断钩子；NULL 表示应用主动读取。 */
    void *userdata;             /* 原样传给 notify，常用于保存信号量或应用上下文。 */
} luat_rf433_cfg_t;

typedef struct {
    uint32_t code;              /* 24 位原始码，高位先接收；不预先划分地址码和按键码。 */
    uint32_t timestamp_us;      /* 确认帧的结束同步边沿在中断中的采样时刻，不是任务读取时刻。单位 us，uint32 自然回绕；比较间隔使用无符号减法。 */
    uint8_t bits;               /* 当前解码器固定输出 24 位。 */
    uint8_t protocol;           /* 当前为 LUAT_RF433_PROTOCOL_EV1527，即 1527 类脉宽编码。 */
} luat_rf433_result_t;

/** 填入已验证的默认参数：LOW 同步，数据短 HIGH=1、长 HIGH=0。
 * pin 默认是 -1，打开前必须设置；本函数只填写配置，不分配资源或创建任务。
 */
void luat_rf433_set_default_cfg(luat_rf433_cfg_t *config);

/** 下面三个接口只能从任务调用，不能从中断或 notify 内调用。
 * open 复制配置并开启 GPIO 双边沿接收；一个 GPIO 必须由本模块独占。
 * GPIO 范围和双边沿支持由平台适配检查；EC7xx 只支持普通 GPIO。
 * 主库提供相同的接收服务，尚未适配的平台 open 返回 ENOTSUP，不伪装开启成功。
 * 模块在 GPIO 中断中采集和解码，不另建接收任务；应用任务读取结果并处理业务。
 * 每个接收器 FIFO 固定保存 16 个已通过重复确认的完整结果；满时丢弃新到结果。
 * 未使用 Poll 或超时定时器：待确认边沿由下一次真实边沿提交，停止发射时
 * 最后的待确认边沿/帧可能不输出，不能靠等待超时强制输出。
 */
int luat_rf433_open(const luat_rf433_cfg_t *config, luat_rf433_handle_t *handle);
/** 非阻塞地取出一个结果：OK 表示取到，EEMPTY 表示 FIFO 已空。
 * 每次被唤醒都应循环读取，通知次数不等于收到的结果个数。
 */
int luat_rf433_read(luat_rf433_handle_t handle, luat_rf433_result_t *result);
/** 成功关闭后停止中断接收并丢弃未读取结果，旧句柄失效；成功返回后可释放 userdata。
 */
int luat_rf433_close(luat_rf433_handle_t handle);

#ifdef __cplusplus
}
#endif
#endif
