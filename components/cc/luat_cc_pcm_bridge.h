#ifndef LUAT_CC_PCM_BRIDGE_H
#define LUAT_CC_PCM_BRIDGE_H
#include <stdint.h>
#define LUAT_CC_AUDIO_MODE_BRIDGE_PCM 1
struct lua_State;
#ifdef LUAT_USE_CC_PCM_BRIDGE
/* 显式选择 CC 后端；独立于 VoIP 音频模式。 */
int luat_cc_pcm_selected(void);
int luat_cc_pcm_init(void);
int luat_cc_pcm_begin(void);
int luat_cc_pcm_dial_begin(void);
/* 0 表示首次请求接听；1 表示已请求或已接通；负值表示失败。 */
int luat_cc_pcm_accept_begin(void);
int luat_cc_pcm_stop(void);
int luat_cc_pcm_tone(int on);
uint32_t luat_cc_pcm_rate(void);
uint32_t luat_cc_pcm_session(void);
/* 查询当前或最近已停止的 SIP generation；存在匹配快照时返回 0。 */
int luat_cc_pcm_get_rx_lost(uint32_t sip_generation, uint32_t *lost);
void luat_cc_pcm_event(uint8_t index, uint8_t status);
int luat_cc_pcm_stats(struct lua_State *L);
#else
static inline int luat_cc_pcm_selected(void) { return 0; }
#endif
#endif
