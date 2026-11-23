/* SPDX-License-Identifier: MIT
 * Copyright (c) 2019-2026 openLuat & AirM2M
 * 支持多实例的 UDP/TCP DNS 中继。
 * 所有原始传输操作均限定在此专用 lwIP 后端中。
 */
#include <string.h>
#include "luat_mem.h"
#include "luat_dns_server_lwip.h"
#include "luat_dns_server_packet.h"
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"

#define DNS_TICK_MS 250
#define DNS_RANDOM_TRIES 128

typedef struct dns_request dns_request_t;
typedef struct dns_stream dns_stream_t;
typedef struct {
    luat_dns_server_t *owner;
    struct pbuf *packet;
    ip_addr_t address;
    uint64_t generation;
    uint16_t port, slot;
    uint8_t response, pending;
} dns_job_t;

struct dns_request {
    luat_dns_server_t *owner;
    struct udp_pcb *pcb;
    luat_dns_server_udp_binding_t binding;
    uint8_t *query;
    luat_dns_server_question_t question;
    ip_addr_t client, sent_server;
    uint64_t generation;
    uint32_t started;
    uint16_t length, client_port, original_id, relay_id, local_port, sent_port, slot;
    uint8_t attempt, failed;
};

typedef struct {
    dns_stream_t *stream;
    uint16_t forwarded; /* 当前被 lwIP 暂存的接收链中，已经成功入队的字节数。 */
    uint8_t side;
} dns_endpoint_t;

typedef struct {
    uint64_t messages;
    uint16_t remaining, prefix;
    uint8_t prefix_bytes;
} dns_framing_t;

struct dns_stream {
    luat_dns_server_t *owner;
    struct tcp_pcb *pcb[2];
    dns_endpoint_t endpoint[2];
    dns_framing_t framing[2];
    uint32_t activity;
    uint8_t connected, fin[2], failed;
};

struct luat_dns_server {
    luat_dns_server_config_t config;
    luat_dns_server_lwip_port_t port;
    struct udp_pcb *udp_lan;
    struct tcp_pcb *tcp_lan;
    luat_dns_server_udp_binding_t binding;
    dns_request_t *requests;
    dns_stream_t *streams;
    dns_job_t *jobs;
    ip_addr_t lan_ip, wan_ip, servers[2];
    uint32_t references;
    uint16_t upstream_port, job_count;
    uint8_t active, wan_ready, wan_index, lan_index;
};

static void dns_timer(void *arg);
static void dns_job_process(void *arg);

static struct netif *dns_lan(luat_dns_server_t const *server) {
    struct netif *lan;
    /* 解引用借用的 LAN 前，先确认它仍在接口列表中。SDK 重连时可能先移除
     * 该接口，而排队的兼容层重启命令尚未到达核心线程。
     */
#if LWIP_SINGLE_NETIF
    lan = netif_default;
    if (lan && lan == server->config.lan && netif_get_index(lan) == server->lan_index &&
        ip_addr_cmp(&lan->ip_addr, &server->lan_ip)) return lan;
#else
    for (lan = netif_list; lan; lan = lan->next) {
        if (lan == server->config.lan && netif_get_index(lan) == server->lan_index &&
            ip_addr_cmp(&lan->ip_addr, &server->lan_ip)) return lan;
    }
#endif
    return NULL;
}

static void dns_release(luat_dns_server_t *server) {
    /* 所有引用均由 tcpip_thread 持有和修改，绝不跨线程操作。 */
    if (--server->references) return;
    luat_heap_free(server->jobs);
    luat_heap_free(server->streams);
    luat_heap_free(server->requests);
    luat_heap_free(server);
}

static void dns_udp_remove(luat_dns_server_t *server, struct udp_pcb **slot) {
    if (!*slot) return;
    server->port.udp_attach(*slot, NULL);
    udp_remove(*slot);
    *slot = NULL;
}

static void dns_request_free(dns_request_t *request) {
    dns_udp_remove(request->owner, &request->pcb);
    if (request->query) luat_heap_free(request->query);
    request->query = NULL;
    request->failed = 0;
    request->generation++; /* 复用槽位前，使已投递的响应失效。 */
}

static int dns_same_question(const luat_dns_server_question_t *a,
                             const luat_dns_server_question_t *b) {
    return a->type == b->type && a->cls == b->cls && a->name_len == b->name_len &&
           memcmp(a->name, b->name, a->name_len) == 0;
}

static void dns_reply(dns_request_t *request, const uint8_t *data, uint16_t length) {
    luat_dns_server_t *server = request->owner;
    struct netif *lan = dns_lan(server);
    struct pbuf *wire;
    uint8_t id[2] = {(uint8_t)(request->original_id >> 8), (uint8_t)request->original_id};
    if (!server->active || !lan || !server->udp_lan || !netif_is_up(lan)) return;
    wire = pbuf_alloc(PBUF_TRANSPORT, length, PBUF_RAM);
    if (!wire) return;
    if (pbuf_take(wire, data, length) == ERR_OK && pbuf_take(wire, id, 2) == ERR_OK) {
        udp_sendto_if_src(server->udp_lan, wire, &request->client, request->client_port,
                          lan, &lan->ip_addr);
    }
    pbuf_free(wire);
}

static void dns_fail(dns_request_t *request) {
    uint8_t reply[12 + 255 + 4] = {0};
    size_t end = 12 + request->question.name_len;
    /* 重建唯一的问题：绝不在 SERVFAIL 响应中附带过期的附加数据。 */
    reply[2] = 0x80 | (request->query[2] & 1);
    reply[3] = 0x82 | (request->query[3] & 0x10);
    reply[5] = 1;
    memcpy(reply + 12, request->question.name, request->question.name_len);
    reply[end] = (uint8_t)(request->question.type >> 8);
    reply[end + 1] = (uint8_t)request->question.type;
    reply[end + 2] = (uint8_t)(request->question.cls >> 8);
    reply[end + 3] = (uint8_t)request->question.cls;
    dns_reply(request, reply, (uint16_t)(end + 4));
}

static void dns_stream_detach(struct tcp_pcb *pcb) {
    tcp_arg(pcb, NULL);
    tcp_recv(pcb, NULL);
    tcp_err(pcb, NULL);
}

static void dns_stream_abort(dns_stream_t *stream) {
    luat_dns_server_t *owner = stream->owner;
    for (int i = 0; i < 2; i++) {
        if (!stream->pcb[i]) continue;
        dns_stream_detach(stream->pcb[i]);
        tcp_abort(stream->pcb[i]);
    }
    memset(stream, 0, sizeof(*stream));
    stream->owner = owner;
}

static err_t dns_stream_close(dns_stream_t *stream, struct tcp_pcb *current) {
    struct tcp_pcb *closing[2] = {stream->pcb[0], stream->pcb[1]};
    luat_dns_server_t *owner = stream->owner;
    err_t result = ERR_OK;
    for (int i = 0; i < 2; i++) {
        if (closing[i]) dns_stream_detach(closing[i]);
    }
    /* tcp_close 成功后会转移所有权，绝不保留半关闭状态的 PCB。 */
    memset(stream, 0, sizeof(*stream));
    stream->owner = owner;
    for (int i = 0; i < 2; i++) {
        if (closing[i] && tcp_close(closing[i]) != ERR_OK) {
            if (closing[i] == current) result = ERR_ABRT;
            tcp_abort(closing[i]);
        }
    }
    return result;
}

static void dns_cancel_requests(luat_dns_server_t *server, int reply) {
    for (unsigned i = 0; i < server->config.udp_slots; i++) {
        dns_request_t *request = &server->requests[i];
        if (reply && request->query) dns_fail(request);
        dns_request_free(request);
    }
    for (unsigned i = 0; i < server->config.tcp_slots; i++) dns_stream_abort(&server->streams[i]);
}

static int dns_sync_wan(luat_dns_server_t *server, luat_dns_server_upstream_t *upstream) {
    struct netif *lan = dns_lan(server);
    uint8_t index = 0;
    int ready;
    memset(upstream, 0, sizeof(*upstream));
    ready = lan && netif_is_up(lan) && server->udp_lan &&
            server->config.select_upstream(server->config.upstream_arg, upstream) == 0;
    ready = ready && upstream->netif && netif_is_up(upstream->netif) &&
            netif_is_link_up(upstream->netif) && IP_IS_V4(&upstream->netif->ip_addr) &&
            !ip_addr_isany(&upstream->netif->ip_addr) && IP_IS_V4(&upstream->servers[0]) &&
            !ip_addr_isany(&upstream->servers[0]) &&
            !ip_addr_cmp(&upstream->servers[0], &lan->ip_addr);
    if (!upstream->port) upstream->port = 53;
    if (ready) {
        index = netif_get_index(upstream->netif);
        if (!IP_IS_V4(&upstream->servers[1]) ||
            ip_addr_cmp(&upstream->servers[1], &lan->ip_addr)) {
            ip_addr_set_zero(&upstream->servers[1]);
        }
    }
    if (server->wan_ready == ready && (!ready ||
        (server->wan_index == index && server->upstream_port == upstream->port &&
         ip_addr_cmp(&server->wan_ip, &upstream->netif->ip_addr) &&
         ip_addr_cmp(&server->servers[0], &upstream->servers[0]) &&
         ip_addr_cmp(&server->servers[1], &upstream->servers[1])))) return ready;
    dns_cancel_requests(server, 1);
    server->wan_ready = (uint8_t)ready;
    server->wan_index = index;
    if (ready) {
        ip_addr_copy(server->wan_ip, upstream->netif->ip_addr);
        memcpy(server->servers, upstream->servers, sizeof(server->servers));
        server->upstream_port = upstream->port;
    }
    return ready;
}

static void dns_enqueue(luat_dns_server_t *server, dns_request_t *request,
                         struct pbuf *packet, const ip_addr_t *address, uint16_t port) {
    if (server->active && packet->tot_len <= server->config.max_packet) {
        for (unsigned i = 0; i < server->job_count; i++) {
            dns_job_t *job = &server->jobs[i];
            if (job->pending) continue;
            job->owner = server;
            job->packet = packet;
            job->address = *address; /* 可能指向输入 pbuf 内部，须在回调返回前复制。 */
            job->port = port;
            job->response = request != NULL;
            job->slot = request ? request->slot : 0;
            job->generation = request ? request->generation : 0;
            job->pending = 1;
            server->references++;
            /* 即使已在 tcpip_thread 上，也必须投递任务。netdrv 的过滤输入路径
             * 会临时摘下 PCB 链表，并在 recv 返回后恢复。
             * 查询和响应回调都不得在此处移除任何 PCB。
             */
            if (tcpip_callback_with_block(dns_job_process, job, 0) == ERR_OK) return;
            job->pending = 0;
            job->packet = NULL;
            dns_release(server);
            break;
        }
    }
    pbuf_free(packet);
}

static void dns_udp_query(void *arg, struct udp_pcb *pcb, struct pbuf *packet,
                           const ip_addr_t *address, uint16_t port) {
    (void)pcb;
    dns_enqueue(arg, NULL, packet, address, port);
}

static void dns_udp_response(void *arg, struct udp_pcb *pcb, struct pbuf *packet,
                              const ip_addr_t *address, uint16_t port) {
    dns_request_t *request = arg;
    (void)pcb;
    dns_enqueue(request->owner, request, packet, address, port);
}

static void dns_lan_destroyed(void *arg, err_t error) {
    luat_dns_server_t *server = arg;
    (void)error;
    server->udp_lan = NULL; /* SDK 已将其释放；定时器在链表遍历结束后执行清理。 */
}

static void dns_request_destroyed(void *arg, err_t error) {
    dns_request_t *request = arg;
    (void)error;
    request->pcb = NULL;
    request->failed = 1;
    request->generation++;
}

static int dns_random16(luat_dns_server_t *server, uint16_t *value) {
    uint8_t bytes[2];
    if (server->config.random(server->config.random_arg, bytes, sizeof(bytes)) != 0) return -1;
    *value = ((uint16_t)bytes[0] << 8) | bytes[1];
    return 0;
}

static int dns_new_id(dns_request_t *request, uint16_t *id) {
    luat_dns_server_t *server = request->owner;
    for (unsigned tries = 0; tries < DNS_RANDOM_TRIES; tries++) {
        int collision = 0;
        if (dns_random16(server, id) != 0) return -1;
        /* 即使旧槽位是唯一的活动请求，重试时也必须更换 ID。 */
        if (request->attempt && *id == request->relay_id) continue;
        for (unsigned i = 0; i < server->config.udp_slots; i++) {
            dns_request_t *other = &server->requests[i];
            if (other != request && other->query && other->relay_id == *id) collision = 1;
        }
        if (!collision) return 0;
    }
    return -1;
}

static int dns_udp_send(dns_request_t *request, const luat_dns_server_upstream_t *upstream,
                         unsigned attempt) {
    luat_dns_server_t *server = request->owner;
    struct pbuf *wire;
    uint16_t id, random_port = 0;
    uint8_t id_bytes[2];
    err_t result = ERR_USE;
    dns_udp_remove(server, &request->pcb);
    request->generation++;
    if (dns_new_id(request, &id) != 0) return -1;
    request->pcb = udp_new();
    if (!request->pcb) return -1;
    ip_reset_option(request->pcb, SOF_REUSEADDR);
    server->port.udp_bind_netif(request->pcb, upstream->netif);
    /* 每次尝试都使用独立随机的源端口，不启用端口复用。 */
    for (unsigned tries = 0; tries < DNS_RANDOM_TRIES; tries++) {
        if (dns_random16(server, &random_port) != 0) return -1;
        random_port = (uint16_t)(49152u + (random_port & 16383u));
        if (request->attempt && random_port == request->local_port) continue;
        result = udp_bind(request->pcb, &server->wan_ip, random_port);
        if (result == ERR_OK) break;
        if (result != ERR_USE) return -1;
    }
    if (result != ERR_OK) return -1;
    request->relay_id = id;
    request->local_port = random_port;
    request->sent_server = upstream->servers[attempt];
    request->sent_port = upstream->port;
    request->attempt = (uint8_t)(attempt + 1);
    request->started = sys_now();
    request->binding.arg = request;
    request->binding.receive = dns_udp_response;
    request->binding.destroyed = dns_request_destroyed;
    server->port.udp_attach(request->pcb, &request->binding);
    wire = pbuf_alloc(PBUF_TRANSPORT, request->length, PBUF_RAM);
    if (!wire) return -1;
    id_bytes[0] = (uint8_t)(id >> 8);
    id_bytes[1] = (uint8_t)id;
    result = pbuf_take(wire, request->query, request->length);
    if (result == ERR_OK) result = pbuf_take(wire, id_bytes, 2);
    /* SDK 发送时可能前插报文头；保存的查询字节始终保持原样。 */
    if (result == ERR_OK) result = udp_sendto_if_src(request->pcb, wire, &request->sent_server,
        request->sent_port, upstream->netif, &server->wan_ip);
    pbuf_free(wire);
    return result == ERR_OK ? 0 : -1;
}

static void dns_process_query(dns_job_t *job, uint8_t *data, uint16_t length) {
    luat_dns_server_t *server = job->owner;
    luat_dns_server_upstream_t upstream;
    dns_request_t failure = {0};
    dns_request_t *request = NULL;
    int ready;
    if (length < 12 || (data[2] & 0xf8) ||
        luat_dns_server_question(data, length, &failure.question) != 0) return;
    failure.owner = server;
    failure.client = job->address;
    failure.client_port = job->port;
    failure.original_id = ((uint16_t)data[0] << 8) | data[1];
    failure.query = data;
    ready = dns_sync_wan(server, &upstream);
    for (unsigned i = 0; i < server->config.udp_slots; i++) {
        dns_request_t *candidate = &server->requests[i];
        if (candidate->query && candidate->original_id == failure.original_id &&
            candidate->client_port == job->port && ip_addr_cmp(&candidate->client, &job->address) &&
            dns_same_question(&candidate->question, &failure.question)) return;
        if (!candidate->query && !request) request = candidate;
    }
    if (!ready || !request) { dns_fail(&failure); return; }
    request->query = luat_heap_malloc(length);
    if (!request->query) { dns_fail(&failure); return; }
    memcpy(request->query, data, length);
    request->question = failure.question;
    request->client = job->address;
    request->client_port = job->port;
    request->original_id = failure.original_id;
    request->length = length;
    request->attempt = 0;
    request->failed = 0;
    if (dns_udp_send(request, &upstream, 0) != 0) {
        dns_fail(request);
        dns_request_free(request);
    }
}

static void dns_process_response(dns_job_t *job, const uint8_t *data, uint16_t length) {
    luat_dns_server_t *server = job->owner;
    dns_request_t *request = &server->requests[job->slot];
    luat_dns_server_question_t question;
    luat_dns_server_upstream_t upstream;
    if (!dns_sync_wan(server, &upstream) || !request->query || !request->pcb || request->failed ||
        request->generation != job->generation || length < 12 || (data[2] & 0xf8) != 0x80 ||
        job->port != request->sent_port || !ip_addr_cmp(&job->address, &request->sent_server) ||
        (((uint16_t)data[0] << 8) | data[1]) != request->relay_id ||
        luat_dns_server_question(data, length, &question) != 0 ||
        !dns_same_question(&question, &request->question)) return;
    dns_reply(request, data, length);
    dns_request_free(request);
}

static void dns_job_process(void *arg) {
    dns_job_t *job = arg;
    luat_dns_server_t *server = job->owner;
    if (server->active && server->udp_lan && job->packet) {
        uint16_t length = job->packet->tot_len;
        uint8_t *data = luat_heap_malloc(length);
        if (data) {
            if (pbuf_copy_partial(job->packet, data, length, 0) == length) {
                if (job->response) dns_process_response(job, data, length);
                else dns_process_query(job, data, length);
            }
            luat_heap_free(data);
        }
    }
    if (job->packet) pbuf_free(job->packet);
    job->packet = NULL;
    job->pending = 0;
    dns_release(server);
}

static void dns_count_frames(dns_framing_t *framing, const uint8_t *data, uint16_t length) {
    while (length) {
        if (framing->remaining) {
            uint16_t used = length < framing->remaining ? length : framing->remaining;
            framing->remaining -= used;
            data += used;
            length -= used;
            if (!framing->remaining) framing->messages++;
        } else {
            framing->prefix = (uint16_t)((framing->prefix << 8) | *data++);
            length--;
            if (++framing->prefix_bytes == 2) {
                framing->remaining = framing->prefix;
                framing->prefix = 0;
                framing->prefix_bytes = 0;
                if (!framing->remaining) framing->messages++;
            }
        }
    }
}

static int dns_answers_complete(const dns_stream_t *stream) {
    return stream->fin[0] && !stream->framing[0].remaining && !stream->framing[0].prefix_bytes &&
           !stream->framing[1].remaining && !stream->framing[1].prefix_bytes &&
           stream->framing[0].messages == stream->framing[1].messages;
}

static void dns_tcp_error(void *arg, err_t error) {
    dns_endpoint_t *endpoint = arg;
    (void)error;
    if (!endpoint) return;
    endpoint->stream->pcb[endpoint->side] = NULL;
    /* SDK 销毁接口时可能正在遍历另一端的 PCB，应延后中止该 PCB。 */
    endpoint->stream->failed = 1;
}

static err_t dns_tcp_connected(void *arg, struct tcp_pcb *pcb, err_t error) {
    dns_endpoint_t *endpoint = arg;
    if (error != ERR_OK) { dns_stream_abort(endpoint->stream); return ERR_ABRT; }
    if (endpoint->stream->failed) return ERR_OK;
    endpoint->stream->connected = 1;
    endpoint->stream->activity = sys_now();
    tcp_output(pcb);
    return ERR_OK;
}

static err_t dns_tcp_receive(void *arg, struct tcp_pcb *pcb, struct pbuf *packet, err_t error) {
    dns_endpoint_t *endpoint = arg;
    dns_stream_t *stream = endpoint->stream;
    struct tcp_pcb *peer = stream->pcb[1 - endpoint->side];
    uint16_t skip = endpoint->forwarded;
    if (stream->failed || error != ERR_OK || !peer) {
        if (packet) pbuf_free(packet);
        dns_stream_abort(stream);
        return ERR_ABRT;
    }
    if (!packet) {
        stream->activity = sys_now();
        stream->fin[endpoint->side] = 1;
        /* 收到客户端 FIN 后，须等完整的响应帧入队，才能关闭上游连接。 */
        if (endpoint->side == 1 || dns_answers_complete(stream)) return dns_stream_close(stream, pcb);
        return ERR_OK;
    }
    /* 上游 lwIP 在 SYN_SENT 状态下拒绝 tcp_write。将原始 pbuf 留给 lwIP，
     * 等待上游握手完成后，由其重试先前拒收的数据。
     */
    if (!endpoint->side && !stream->connected) return ERR_MEM;
    for (const struct pbuf *part = packet; part; part = part->next) {
        if (skip >= part->len) { skip -= part->len; continue; }
        while (skip < part->len) {
            uint16_t n = part->len - skip;
            uint16_t room = tcp_sndbuf(peer);
            const uint8_t *data = (const uint8_t *)part->payload + skip;
            if (n > room) n = room;
            err_t result = n ? stream->owner->port.tcp_write_copy(peer, data, n) : ERR_MEM;
            if (result == ERR_MEM) {
                tcp_output(peer);
                return ERR_MEM; /* lwIP 重投同一接收链，从 forwarded 继续。 */
            }
            if (result != ERR_OK) {
                pbuf_free(packet);
                dns_stream_abort(stream);
                return ERR_ABRT;
            }
            dns_count_frames(&stream->framing[endpoint->side], data, n);
            endpoint->forwarded += n;
            skip += n;
            stream->activity = sys_now();
        }
        skip = 0;
    }
    endpoint->forwarded = 0;
    tcp_recved(pcb, packet->tot_len);
    pbuf_free(packet);
    tcp_output(peer);
    if (dns_answers_complete(stream)) return dns_stream_close(stream, pcb);
    return ERR_OK;
}

static err_t dns_tcp_accept(void *arg, struct tcp_pcb *pcb, err_t error) {
    luat_dns_server_t *server = arg;
    luat_dns_server_upstream_t upstream;
    dns_stream_t *stream = NULL;
    if (error != ERR_OK) return error;
    if (!server->active || !dns_sync_wan(server, &upstream)) { tcp_abort(pcb); return ERR_ABRT; }
    for (unsigned i = 0; i < server->config.tcp_slots; i++) {
        dns_stream_t *candidate = &server->streams[i];
        if (!candidate->pcb[0] && !candidate->pcb[1] && !candidate->failed) {
            stream = candidate;
            break;
        }
    }
    if (!stream) { tcp_abort(pcb); return ERR_ABRT; }
    stream->pcb[0] = pcb;
    stream->pcb[1] = tcp_new();
    stream->activity = sys_now();
    for (int i = 0; i < 2; i++) {
        stream->endpoint[i].stream = stream;
        stream->endpoint[i].side = (uint8_t)i;
        if (!stream->pcb[i]) continue;
        tcp_arg(stream->pcb[i], &stream->endpoint[i]);
        tcp_recv(stream->pcb[i], dns_tcp_receive);
        tcp_err(stream->pcb[i], dns_tcp_error);
    }
    if (!stream->pcb[1] || tcp_bind(stream->pcb[1], &server->wan_ip, 0) != ERR_OK ||
        server->port.tcp_select_netif(stream->pcb[1], upstream.netif, &server->servers[0]) != ERR_OK ||
        tcp_connect(stream->pcb[1], &server->servers[0], server->upstream_port, dns_tcp_connected) != ERR_OK) {
        dns_stream_abort(stream);
        return ERR_ABRT;
    }
    return ERR_OK;
}

static void dns_timer(void *arg) {
    luat_dns_server_t *server = arg;
    luat_dns_server_upstream_t upstream;
    uint32_t now = sys_now();
    int ready = dns_sync_wan(server, &upstream);
    for (unsigned i = 0; i < server->config.udp_slots; i++) {
        dns_request_t *request = &server->requests[i];
        if (!request->query) continue;
        if (!request->failed && (uint32_t)(now - request->started) < server->config.retry_ms) continue;
        if (!request->failed && request->attempt == 1 && ready && !ip_addr_isany(&upstream.servers[1]) &&
            dns_udp_send(request, &upstream, 1) == 0) continue;
        dns_fail(request);
        dns_request_free(request);
    }
    for (unsigned i = 0; i < server->config.tcp_slots; i++) {
        dns_stream_t *stream = &server->streams[i];
        if (stream->failed || ((stream->pcb[0] || stream->pcb[1]) &&
            (uint32_t)(now - stream->activity) >= server->config.tcp_idle_ms)) dns_stream_abort(stream);
    }
    sys_timeout(DNS_TICK_MS, dns_timer, server);
}

int luat_dns_server_running(const luat_dns_server_t *server) {
    return server && server->active && server->udp_lan && server->tcp_lan && dns_lan(server);
}

void luat_dns_server_stop(luat_dns_server_t **handle) {
    luat_dns_server_t *server;
    if (!handle || !*handle) return;
    server = *handle;
    *handle = NULL;
    server->active = 0;
    sys_untimeout(dns_timer, server);
    dns_cancel_requests(server, 0);
    dns_udp_remove(server, &server->udp_lan);
    if (server->tcp_lan) {
        tcp_accept(server->tcp_lan, NULL);
        tcp_arg(server->tcp_lan, NULL);
        tcp_close(server->tcp_lan); /* LISTEN 状态的 PCB 没有发送队列，可直接关闭。 */
        server->tcp_lan = NULL;
    }
    for (unsigned i = 0; i < server->job_count; i++) {
        if (server->jobs[i].packet) pbuf_free(server->jobs[i].packet);
        server->jobs[i].packet = NULL;
    }
    /* 已投递的回调仅持有 server/job 存储，不持有任何外部指针。 */
    memset(&server->config, 0, sizeof(server->config));
    memset(&server->port, 0, sizeof(server->port));
    dns_release(server);
}

int luat_dns_server_start(const luat_dns_server_config_t *config, luat_dns_server_t **out) {
    luat_dns_server_t *server;
    struct tcp_pcb *listener;
    err_t error = ERR_MEM;
    if (!out) return ERR_ARG;
    *out = NULL;
    if (!config || !config->lan || !IP_IS_V4(&config->lan->ip_addr) ||
        ip_addr_isany(&config->lan->ip_addr) || !config->select_upstream || !config->random ||
        !config->port || !config->port->udp_attach || !config->port->udp_bind_netif ||
        !config->port->tcp_write_copy || !config->port->tcp_select_netif ||
        config->udp_slots > 128 || config->tcp_slots > 64 ||
        (config->max_packet && config->max_packet < 17) ||
        config->retry_ms > 0x7fffffffU || config->tcp_idle_ms > 0x7fffffffU) return ERR_ARG;
    server = luat_heap_calloc(1, sizeof(*server));
    if (!server) return ERR_MEM;
    server->config = *config;
    server->lan_ip = config->lan->ip_addr;
    server->lan_index = netif_get_index(config->lan);
    server->port = *config->port;
    server->config.port = NULL; /* 不借用调用方的移植层函数表本身。 */
    if (!server->config.listen_port) server->config.listen_port = 53;
    if (!server->config.udp_slots) server->config.udp_slots = 16;
    if (!server->config.tcp_slots) server->config.tcp_slots = 4;
    if (!server->config.max_packet) server->config.max_packet = 4096;
    if (!server->config.retry_ms) server->config.retry_ms = 2000;
    if (!server->config.tcp_idle_ms) server->config.tcp_idle_ms = 15000;
    server->references = 1;
    server->job_count = (uint16_t)(server->config.udp_slots * 2);
    server->requests = luat_heap_calloc(server->config.udp_slots, sizeof(*server->requests));
    server->streams = luat_heap_calloc(server->config.tcp_slots, sizeof(*server->streams));
    server->jobs = luat_heap_calloc(server->job_count, sizeof(*server->jobs));
    if (!server->requests || !server->streams || !server->jobs) {
        dns_release(server);
        return ERR_MEM;
    }
    for (unsigned i = 0; i < server->config.udp_slots; i++) {
        server->requests[i].owner = server;
        server->requests[i].slot = (uint16_t)i;
    }
    for (unsigned i = 0; i < server->config.tcp_slots; i++) server->streams[i].owner = server;
    server->active = 1;
    server->binding.arg = server;
    server->binding.receive = dns_udp_query;
    server->binding.destroyed = dns_lan_destroyed;
    server->udp_lan = udp_new();
    if (!server->udp_lan) goto failed;
    server->port.udp_bind_netif(server->udp_lan, config->lan);
    error = udp_bind(server->udp_lan, &config->lan->ip_addr, server->config.listen_port);
    if (error != ERR_OK) goto failed;
    server->port.udp_attach(server->udp_lan, &server->binding);
    listener = tcp_new();
    if (!listener) { error = ERR_MEM; goto failed; }
    error = tcp_bind(listener, &config->lan->ip_addr, server->config.listen_port);
    if (error == ERR_OK) {
        server->tcp_lan = tcp_listen(listener);
        if (!server->tcp_lan) error = ERR_MEM;
    }
    if (!server->tcp_lan) { tcp_abort(listener); goto failed; }
    tcp_arg(server->tcp_lan, server);
    tcp_accept(server->tcp_lan, dns_tcp_accept);
    sys_timeout(DNS_TICK_MS, dns_timer, server);
    *out = server;
    return 0;
failed:
    luat_dns_server_stop(&server);
    return error;
}
