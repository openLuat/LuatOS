/* SPDX-License-Identifier: MIT
 * Copyright (c) 2019-2026 openLuat & AirM2M
 */
#include "luat_dns_server_packet.h"
#include <string.h>

int luat_dns_server_question(const uint8_t *packet, size_t length,
                             luat_dns_server_question_t *out) {
    size_t pos = 12, end = 0, used = 0;
    unsigned steps = 0;
    if (!packet || !out || length < 17 || packet[4] != 0 || packet[5] != 1) return -1;
    memset(out, 0, sizeof(*out));
    /* 步数上限也用于限制恶意循环压缩引用链带来的处理开销。 */
    while (pos < length && ++steps <= 255) {
        uint8_t label = packet[pos++];
        if ((label & 0xc0) == 0xc0) {
            size_t target, boundary = 12;
            if (pos >= length) return -1;
            target = ((size_t)(label & 0x3f) << 8) | packet[pos++];
            if (target < 12 || target >= pos - 2) return -1;
            /* 指针必须指向前面某个标签的边界，不能指向标签内容。
             * 由于报文中只有第一个问题，重复访问其自身标签会形成循环，
             * 随后因展开域名长度或步数超限而被拒绝。
             */
            while (boundary < target) {
                uint8_t previous = packet[boundary];
                if (!previous || previous > 63 || length - boundary - 1 < previous) return -1;
                boundary += 1 + previous;
            }
            if (boundary != target) return -1;
            if (!end) end = pos;
            pos = target;
            continue;
        }
        if (label & 0xc0) return -1;
        if (label == 0) {
            if (used >= sizeof(out->name)) return -1;
            out->name[used++] = 0;
            if (!end) end = pos;
            if (end > length || length - end < 4) return -1;
            out->name_len = used;
            out->type = ((uint16_t)packet[end] << 8) | packet[end + 1];
            out->cls = ((uint16_t)packet[end + 2] << 8) | packet[end + 3];
            return 0;
        }
        /* 在最多 255 字节的展开域名中，为末尾的根域字节预留空间。 */
        if (length - pos < label || used + 1 + label >= sizeof(out->name)) return -1;
        out->name[used++] = label;
        for (unsigned i = 0; i < label; i++) {
            uint8_t c = packet[pos++];
            out->name[used++] = (c >= 'A' && c <= 'Z') ? (uint8_t)(c + ('a' - 'A')) : c;
        }
    }
    return -1;
}
