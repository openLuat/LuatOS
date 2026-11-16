/* SPDX-License-Identifier: MIT
 * 版权和许可声明见 LICENSE。
 * 用于独立以太网/Wi-Fi 局域网的有界 DHCPv4 引擎（不支持中继）。
 */
#include "luat_dhcps.h"
#include <string.h>

static uint32_t read32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}

static void write32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static int unicast(uint32_t ip)
{
    return (ip >> 24) && (ip >> 24) != 127 && ip < 0xe0000000u;
}

static int subnet_host(uint32_t ip, uint32_t network, uint32_t mask)
{
    return unicast(ip) && (ip & mask) == network &&
           (ip & ~mask) && (ip & ~mask) != ~mask;
}

void luat_dhcps_config_default(luat_dhcps_config_t *config, uint32_t ip,
                              uint32_t mask, unsigned clients)
{
    if (!config) return;
    memset(config, 0, sizeof(*config));
    config->server_ip = ip;
    config->netmask = mask;
    config->client_count = clients;
    config->lease_seconds = 3600;
}

int luat_dhcps_init(luat_dhcps_t *server, const luat_dhcps_config_t *config,
                    luat_dhcps_lease_t *leases, size_t capacity)
{
    if (!server || !config || !leases || !config->client_count ||
        config->client_count > capacity || !config->lease_seconds) return -1;
    luat_dhcps_config_t c = *config;
    uint32_t host = ~c.netmask, network = c.server_ip & c.netmask;
    if (c.netmask < 0xff000000u || (host & (host + 1)) ||
        !subnet_host(c.server_ip, network, c.netmask)) return -1;
    if (!c.pool_start && !c.pool_end) {
        c.pool_start = network + 1;
        c.pool_end = (network | host) - 1;
    }
    if (c.pool_start > c.pool_end ||
        !subnet_host(c.pool_start, network, c.netmask) ||
        !subnet_host(c.pool_end, network, c.netmask)) return -1;
    uint64_t available = (uint64_t)c.pool_end - (uint64_t)c.pool_start + 1;
    if (c.server_ip >= c.pool_start && c.server_ip <= c.pool_end) available--;
    if (available < c.client_count ||
        (c.router && !subnet_host(c.router, network, c.netmask))) return -1;
    for (unsigned i = 0; i < LUAT_DHCPS_DNS_MAX; i++) {
        if (c.dns[i] && !unicast(c.dns[i])) return -1;
    }
    server->config = c;
    server->leases = leases;
    uint32_t candidate = c.pool_start;
    for (unsigned i = 0; i < c.client_count; i++) {
        if (candidate == c.server_ip) candidate++;
        memset(&leases[i], 0, sizeof(leases[i]));
        leases[i].ip = candidate++;
    }
    return 0;
}

void luat_dhcps_deinit(luat_dhcps_t *server)
{
    if (!server) return;
    if (server->leases) {
        for (unsigned i = 0; i < server->config.client_count; i++) {
            memset(&server->leases[i], 0, sizeof(server->leases[i]));
        }
    }
    memset(server, 0, sizeof(*server));
}

static uint64_t deadline(uint64_t now, uint32_t seconds)
{
    return now > UINT64_MAX - seconds ? UINT64_MAX : now + seconds;
}

static void option32(uint8_t *out, size_t *pos, uint8_t tag, uint32_t value)
{
    out[(*pos)++] = tag;
    out[(*pos)++] = 4;
    write32(out + *pos, value);
    *pos += 4;
}

size_t luat_dhcps_reply(luat_dhcps_t *s, const uint8_t *in, size_t length,
                       uint8_t *out, size_t capacity, uint64_t now)
{
    if (!s || !s->leases || !in || !out || capacity < LUAT_DHCPS_REPLY_SIZE ||
        length < 240 || length > LUAT_DHCPS_REQUEST_MAX ||
        in[0] != 1 || in[1] != 1 || in[2] != 6 || in[3] || read32(in + 24) ||
        read32(in + 236) != 0x63825363 || (in[28] & 1) ||
        !memcmp(in + 28, "\0\0\0\0\0\0", 6)) return 0;
    unsigned type = 0, ended = 0, have_type = 0, have_request = 0, have_server = 0;
    uint32_t requested = 0, server = 0, ciaddr = read32(in + 12);
    for (size_t pos = 240; pos < length;) {
        unsigned tag = in[pos++];
        if (tag == 255) { ended = 1; break; }
        if (!tag) continue;
        if (pos == length) return 0;
        unsigned n = in[pos++];
        if (n > length - pos) return 0;
        if (tag == 53) { if (n != 1 || have_type++) return 0; type = in[pos]; }
        if (tag == 50) { if (n != 4 || have_request++) return 0; requested = read32(in + pos); }
        if (tag == 54) { if (n != 4 || have_server++) return 0; server = read32(in + pos); }
        if (tag == 52) return 0; /* 不支持 BOOTP 字段复用。 */
        pos += n;
    }
    if (!ended || !type || (have_server && server != s->config.server_ip)) return 0;
    luat_dhcps_lease_t *own = NULL, *free_slot = NULL, *target = NULL;
    for (unsigned i = 0; i < s->config.client_count; i++) {
        luat_dhcps_lease_t *l = &s->leases[i];
        if (l->expires <= now) { l->expires = 0; memset(l->mac, 0, 6); }
        if (l->expires && !memcmp(l->mac, in + 28, 6)) own = l;
        if (!l->expires && !free_slot) free_slot = l;
        if (l->ip == (have_request ? requested : ciaddr)) target = l;
    }
    if (type == 7) { /* RELEASE 必须指明本服务器和已租用的地址。 */
        if (have_server && own && own->ip == ciaddr) own->expires = 0;
        return 0;
    }
    if (type == 4) { /* 将客户端拒绝的已提供地址隔离一分钟。 */
        if (have_server && have_request && own && own->ip == requested) {
            memset(own->mac, 0, 6);
            own->expires = deadline(now, 60);
        }
        return 0;
    }
    unsigned reply;
    luat_dhcps_lease_t *lease = NULL;
    if (type == 1) {
        lease = own ? own : free_slot;
        if (!lease) return 0;
        reply = 2;
        if (!own) { memcpy(lease->mac, in + 28, 6); lease->expires = deadline(now, 60); }
    } else if (type == 3) {
        if ((have_request && ciaddr) || (!have_request && !ciaddr) ||
            (have_server && !have_request)) return 0;
        if (target && (!target->expires || target == own)) {
            if (own && own != target) own->expires = 0;
            lease = target;
            memcpy(lease->mac, in + 28, 6);
            lease->expires = deadline(now, s->config.lease_seconds);
            reply = 5;
        } else reply = 6;
    } else if (type == 8 && ciaddr &&
               (ciaddr & s->config.netmask) == (s->config.server_ip & s->config.netmask)) {
        reply = 5; /* INFORM：仅返回配置，不分配租约或填写 yiaddr。 */
    } else return 0;

    memset(out, 0, LUAT_DHCPS_REPLY_SIZE);
    out[0] = 2; out[1] = 1; out[2] = 6;
    memcpy(out + 4, in + 4, 4);
    memcpy(out + 10, in + 10, 2);
    memcpy(out + 28, in + 28, 16);
    if (reply != 6) write32(out + 12, ciaddr);
    if (lease) write32(out + 16, lease->ip);
    write32(out + 236, 0x63825363);
    size_t pos = 240;
    out[pos++] = 53; out[pos++] = 1; out[pos++] = (uint8_t)reply;
    option32(out, &pos, 54, s->config.server_ip);
    if (reply != 6) {
        option32(out, &pos, 1, s->config.netmask);
        if (lease) option32(out, &pos, 51, s->config.lease_seconds);
        if (s->config.router) option32(out, &pos, 3, s->config.router);
        unsigned dns_count = 0;
        for (unsigned i = 0; i < LUAT_DHCPS_DNS_MAX; i++) {
            if (s->config.dns[i]) dns_count++;
        }
        if (dns_count) {
            out[pos++] = 6; out[pos++] = (uint8_t)(dns_count * 4);
            for (unsigned i = 0; i < LUAT_DHCPS_DNS_MAX; i++) {
                if (s->config.dns[i]) { write32(out + pos, s->config.dns[i]); pos += 4; }
            }
        }
    }
    out[pos] = 255;
    return LUAT_DHCPS_REPLY_SIZE;
}
