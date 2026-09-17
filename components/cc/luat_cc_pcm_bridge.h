#ifndef LUAT_CC_PCM_BRIDGE_H
#define LUAT_CC_PCM_BRIDGE_H
#include <stdint.h>
#define LUAT_CC_AUDIO_MODE_BRIDGE_PCM 1
struct lua_State;
#ifdef LUAT_USE_CC_PCM_BRIDGE
/* Explicit CC backend selection; independent of the VoIP audio mode. */
int luat_cc_pcm_selected(void);
int luat_cc_pcm_init(void);
int luat_cc_pcm_deinit(void);
int luat_cc_pcm_begin(void);
int luat_cc_pcm_dial_begin(void);
/* 0 first answer request; 1 already requested/connected; negative failure. */
int luat_cc_pcm_accept_begin(void);
int luat_cc_pcm_stop(void);
int luat_cc_pcm_tone(int on);
uint32_t luat_cc_pcm_rate(void);
uint32_t luat_cc_pcm_session(void);
void luat_cc_pcm_event(uint8_t index, uint8_t status);
int luat_cc_pcm_stats(struct lua_State *L);
#else
static inline int luat_cc_pcm_selected(void) { return 0; }
#endif
#endif
