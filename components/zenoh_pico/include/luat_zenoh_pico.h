/* SPDX-License-Identifier: MIT */
#ifndef LUAT_ZENOH_PICO_H
#define LUAT_ZENOH_PICO_H
#include <stddef.h>
#include <stdint.h>

#define LUAT_ZP_KEY_MAX 255
#define LUAT_ZP_PAYLOAD_MAX 4096
#define LUAT_ZP_QUEUE_MAX 8
#define LUAT_ZP_SUB_MAX 4
#define LUAT_ZP_STACK_SIZE 8192
enum { LUAT_ZP_CLOSED, LUAT_ZP_OPENING, LUAT_ZP_ONLINE, LUAT_ZP_CLOSING, LUAT_ZP_FAILED };
enum { LUAT_ZP_PUBLISH = 1, LUAT_ZP_SUBSCRIBE, LUAT_ZP_UNSUBSCRIBE };
typedef struct {
    uint32_t generation, id, subscriber;
    int code;
    size_t key_len, payload_len;
    const char *kind, *operation;
    char key[LUAT_ZP_KEY_MAX + 1];
    uint8_t payload[LUAT_ZP_PAYLOAD_MAX];
} luat_zp_event_t;

/* 所有公开入口由唯一 Lua VM 线程调用，工作任务独占 zenoh 对象。 */
int luat_zenoh_pico_open(const char *endpoint, int adapter, uint32_t *generation);
int luat_zenoh_pico_command(uint32_t generation, int op, uint32_t id,
                           const char *key, const void *payload, size_t length);
void luat_zenoh_pico_close(uint32_t generation);
int luat_zenoh_pico_state(uint32_t generation);
uint32_t luat_zenoh_pico_dropped(void);
int luat_zenoh_pico_adapter(void);
int luat_zenoh_pico_pop(luat_zp_event_t **event);
void luat_zenoh_pico_event_free(luat_zp_event_t *event);
void luat_zenoh_pico_wake(void);
void luat_zenoh_pico_io_fail(void);
int luat_zenoh_pico_io_failed(void);
void luat_zenoh_pico_rng_fail(void);
int luat_zenoh_pico_rng_failed(void);
#endif
