#ifndef LUAT_NETDRV_CAPTURE_H
#define LUAT_NETDRV_CAPTURE_H

#include <stddef.h>
#include <stdint.h>

#define LUAT_NETDRV_CAPTURE_CMD 21
#define LUAT_NETDRV_CAPTURE_MAX_LEN 1500
#define LUAT_NETDRV_CAPTURE_HEADER_LEN 20

struct pbuf;

#ifdef LUAT_USE_NETDRV_IP_CAPTURE
int luat_netdrv_capture_config(int id, uint16_t snaplen);
void luat_netdrv_capture_raw(int id, int tx, const uint8_t *data, uint16_t len, int ethernet);
void luat_netdrv_capture_pbuf(int id, int tx, const struct pbuf *p, int ethernet);
uint32_t luat_netdrv_capture_dropped(void);

/* Called in network task context. Copy/enqueue before return, without waiting. */
int luat_netdrv_capture_log_write(const uint8_t *record, size_t len);
#else
#define luat_netdrv_capture_raw(id, tx, data, len, ethernet) ((void)0)
#define luat_netdrv_capture_pbuf(id, tx, p, ethernet) ((void)0)
#endif

#endif
