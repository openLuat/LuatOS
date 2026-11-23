/* SPDX-License-Identifier: MIT
 * Copyright (c) 2019-2026 openLuat & AirM2M
 */
#ifndef LUAT_DNS_SERVER_PACKET_H
#define LUAT_DNS_SERVER_PACKET_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t name[255]; /* 未压缩的报文格式域名，ASCII 字母统一转换为小写。 */
    size_t name_len;   /* 包含标签长度字节和末尾的根域字节。 */
    uint16_t type;
    uint16_t cls;
} luat_dns_server_question_t;

/** 解析且仅解析一个问题（QDCOUNT=1）。成功返回 0，输入无效时返回 -1。
 * 检查标签和域名的边界、压缩引用环以及保留的标签编码。
 * 压缩指针必须指向报文内更早的位置，且不能指向报文头部。
 * 其他区段不作解析：此函数用于中继的问题匹配，并非完整的 DNS 校验器。
 */
int luat_dns_server_question(const uint8_t *packet, size_t length,
                             luat_dns_server_question_t *out);

#ifdef __cplusplus
}
#endif
#endif
