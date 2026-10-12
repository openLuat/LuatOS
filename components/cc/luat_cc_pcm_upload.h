#ifndef LUAT_CC_PCM_UPLOAD_H
#define LUAT_CC_PCM_UPLOAD_H

/* 由 SoC 管理的 PCM 适配器，使用未经修改的 SDK HAL。 */
#include "luat_cc_pcm_upload_core.h"
#ifdef __cplusplus
extern "C" {
#endif
/* 上电后，在 CC 空闲且旧语音上传器尚未运行时，从任务上下文选择本后端。
 * CC 初始化的所有者负责串行化 enable；
 * 本次启动期间后端选择保持不变。
 * 不初始化物理音频驱动。本次启动的后续运行期间始终
 * 拒绝旧 speech_upload API。重复调用 enable 是幂等的，
 * 会保留 epoch/计数器，也不会清除已锁存的故障。
 * codec 0 = NB/8000/320 字节，codec 1 = WB/16000/640 字节，PCM16 单声道/20 ms。
 * 提交接口返回前复制输入数据。HAL 持有每份副本，直到真实的
 * audioFreeRecordBuf 回调到达。编码完成不代表 RTP 已发送。
 * 停止操作与正在执行的提交串行化；不会等待编码
 * 完成。旧槽位归还前收到录音启动请求时，启动将被延后；
 * 直到使用新 epoch 和 codec 设置 stats.active，上传才恢复活动状态。
 * 停止会取消延后的启动。超过 1000 ms 仍有槽位未归还时，故障锁存
 * 到重启为止。codec 切换也遵循先排空再启动的顺序。
 * API 仅限任务上下文调用，不得从 ISR 或语音录音通知中调用。
 */
int luat_cc_pcm_upload_enable(void);
int luat_cc_pcm_upload_submit(const void *pcm, uint32_t len, uint32_t epoch);
void luat_cc_pcm_upload_stop(void);
int luat_cc_pcm_upload_get_stats(luat_cc_pcm_upload_stats_t *stats);
#ifdef __cplusplus
}
#endif
#endif
