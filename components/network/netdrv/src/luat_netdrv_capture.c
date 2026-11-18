#include "luat_base.h"

#ifdef LUAT_USE_NETDRV_IP_CAPTURE
#include "luat_netdrv_capture.h"
#include "luat_netdrv.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "lwip/pbuf.h"

static uint32_t snaplens[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
static uint32_t sequence;
static uint32_t dropped;

static void put_u16(uint8_t *dest, uint16_t value) {
    dest[0] = (uint8_t)value;
    dest[1] = (uint8_t)(value >> 8);
}

static void put_u32(uint8_t *dest, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) {
        dest[i] = (uint8_t)(value >> (8 * i));
    }
}

static void put_u64(uint8_t *dest, uint64_t value) {
    for (unsigned i = 0; i < 8; ++i) {
        dest[i] = (uint8_t)(value >> (8 * i));
    }
}

uint32_t luat_netdrv_capture_dropped(void) {
    return __atomic_load_n(&dropped, __ATOMIC_RELAXED);
}

int luat_netdrv_capture_config(int id, uint16_t snaplen) {
    if (id <= NW_ADAPTER_INDEX_LWIP_NONE || id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY
        || snaplen > LUAT_NETDRV_CAPTURE_MAX_LEN) {
        return -1;
    }
    __atomic_store_n(&snaplens[id], snaplen, __ATOMIC_RELEASE);
    return 0;
}

static uint16_t capture_limit(int id) {
    if (id <= NW_ADAPTER_INDEX_LWIP_NONE || id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        return 0;
    }
    return (uint16_t)__atomic_load_n(&snaplens[id], __ATOMIC_ACQUIRE);
}

/* Read just the headers from a possibly chained pbuf. Never move its payload. */
static int packet_info(const struct pbuf *p, int ethernet, uint16_t *offset, uint16_t *original) {
    uint8_t header[40];
    uint16_t pos = 0;
    if (ethernet) {
        if (pbuf_copy_partial(p, header, 14, 0) != 14) {
            return -1;
        }
        uint16_t type = ((uint16_t)header[12] << 8) | header[13];
        pos = 14;
        /* Support both single VLAN and provider/customer double tagging. */
        for (unsigned tags = 0; type == 0x8100 || type == 0x88A8; ++tags) {
            if (tags == 2 || pbuf_copy_partial(p, header, 4, pos) != 4) {
                return -1;
            }
            type = ((uint16_t)header[2] << 8) | header[3];
            pos += 4;
        }
        if (type != 0x0800 && type != 0x86DD) {
            return -1;
        }
    }
    if (pbuf_copy_partial(p, header, 1, pos) != 1) {
        return -1;
    }
    uint32_t length;
    if (header[0] >> 4 == 4) {
        if (pbuf_copy_partial(p, header, 20, pos) != 20) {
            return -1;
        }
        unsigned ihl = (header[0] & 15) * 4;
        length = ((uint16_t)header[2] << 8) | header[3];
        if (ihl < 20 || length < ihl) {
            return -1;
        }
    } else if (header[0] >> 4 == 6) {
        if (pbuf_copy_partial(p, header, 40, pos) != 40) {
            return -1;
        }
        length = 40 + (((uint16_t)header[4] << 8) | header[5]);
    } else {
        return -1;
    }
    if ((uint32_t)pos + length > p->tot_len) {
        return -1;
    }
    *offset = pos;
    *original = (uint16_t)length;
    return 0;
}

void luat_netdrv_capture_pbuf(int id, int tx, const struct pbuf *p, int ethernet) {
    uint16_t limit = capture_limit(id);
    if (!limit || !p) {
        return;
    }
    uint16_t offset, original;
    if (packet_info(p, ethernet, &offset, &original)) {
        return;
    }
    uint32_t seq = __sync_add_and_fetch(&sequence, 1);
    uint64_t tick = luat_mcu_tick64_ms();
    uint16_t length = original < limit ? original : limit;
    uint16_t record_len = LUAT_NETDRV_CAPTURE_HEADER_LEN + length;
    uint8_t *data = luat_heap_malloc(record_len);
    if (!data) {
        __sync_add_and_fetch(&dropped, 1);
        return;
    }
    data[0] = 1;
    data[1] = (uint8_t)id;
    data[2] = tx != 0;
    data[3] = 0;
    put_u32(data + 4, seq);
    put_u64(data + 8, tick);
    put_u16(data + 16, original);
    put_u16(data + 18, length);
    /* The platform copies the record into its existing log buffer before returning. */
    if (pbuf_copy_partial(p, data + LUAT_NETDRV_CAPTURE_HEADER_LEN, length, offset) != length
        || luat_netdrv_capture_log_write(data, record_len) != 0) {
        __sync_add_and_fetch(&dropped, 1);
    }
    luat_heap_free(data);
}

void luat_netdrv_capture_raw(int id, int tx, const uint8_t *data, uint16_t len, int ethernet) {
    if (!capture_limit(id) || !data) {
        return;
    }
    struct pbuf buffer = {0};
    buffer.payload = (void *)data;
    buffer.len = len;
    buffer.tot_len = len;
    luat_netdrv_capture_pbuf(id, tx, &buffer, ethernet);
}

#endif
