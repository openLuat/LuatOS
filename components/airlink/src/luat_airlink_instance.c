#include "luat_base.h"
#ifdef LUAT_USE_AIRLINK_INSTANCE
#include "luat_airlink.h"
#include "luat_airlink_arq.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_uart.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "luat_netdrv.h"
#include "luat_netdrv_drv.h"
#include "luat_netdrv_event.h"
#include "luat_network_adapter.h"
#ifdef LUAT_USE_AIRLINK_HSPI_MASTER
#include "luat_airlink_hspi_master.h"
#endif
#define LUAT_LOG_TAG "airlink.link"
#include "luat_log.h"

#define FRAME_SIZE 1600
#define RX_SIZE 8192
#define QUEUE_DEPTH 64

typedef struct {
    luat_airlink_setup_t conf;
    luat_rtos_queue_t tx, ip, rx;
    luat_rtos_task_handle io_task, dispatch_task;
    luat_rtos_mutex_t lock;
    luat_rtos_semaphore_t net_done;
    int net_result;
    uint8_t net_owned;
    luat_airlink_dev_info_t peer;
    airlink_statistic_t stats;
    uint64_t last_rx;
    uint16_t fragment;
    uint8_t configured, uart_opened;
    volatile uint8_t running;
    volatile uint8_t tx_busy;
    uint8_t ack_due;
    uint8_t stalled, escaped, in_frame, cmd_budget;
    size_t rx_used;
    uint8_t *rxbuf, *txbuf, *wire;
} airlink_instance_t;

static airlink_instance_t links[AIRLINK_LINK_COUNT];
static struct { int used, id, initialized; luat_rtos_mutex_t lock; } buses[AIRLINK_LINK_COUNT];
static void instance_net_update(void* param);

static void uart_sent(int uart_id, void* param) {
    (void)param;
    for (int i = 0; i < AIRLINK_LINK_COUNT; i++)
        if (links[i].uart_opened && links[i].conf.uart_id == uart_id) links[i].tx_busy = 0;
}

int luat_airlink_in_dispatch(int route) {
    int id = route - AIRLINK_ROUTE_BASE;
    return luat_airlink_link_configured(id) && links[id].dispatch_task == luat_rtos_get_current_handle();
}

int luat_airlink_link_configured(int id) {
    return id >= 0 && id < AIRLINK_LINK_COUNT && links[id].configured;
}
int luat_airlink_instance_enabled(void) { return links[0].configured || links[1].configured; }
int luat_airlink_context_link(void) {
    luat_rtos_task_handle self = luat_rtos_get_current_handle();
    if (!self) return -1;
    for (int i = 0; i < AIRLINK_LINK_COUNT; i++)
        if (links[i].configured && (links[i].io_task == self || links[i].dispatch_task == self)) return i;
    return -1;
}
airlink_statistic_t* luat_airlink_link_statistics(int id) {
    return luat_airlink_link_configured(id) ? &links[id].stats : NULL;
}
int luat_airlink_link_snapshot(int id, airlink_statistic_t* stats, luat_airlink_dev_info_t* peer) {
    if (!luat_airlink_link_configured(id)) return -1;
    airlink_instance_t* l = &links[id];
    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
    if (stats) luat_airlink_statistics_copy(stats, &l->stats);
    if (peer) *peer = l->peer;
    luat_rtos_mutex_unlock(l->lock);
    return 0;
}
int luat_airlink_link_peer_copy(int id, luat_airlink_dev_info_t* peer) {
    return luat_airlink_link_snapshot(id, NULL, peer);
}
void luat_airlink_link_update_peer(int id, const luat_airlink_dev_info_t* peer) {
    if (!luat_airlink_link_configured(id) || !peer) return;
    luat_rtos_mutex_lock(links[id].lock, LUAT_WAIT_FOREVER);
    links[id].peer = *peer;
    luat_rtos_mutex_unlock(links[id].lock);
    tcpip_callback(instance_net_update, &links[id]);
}
int luat_airlink_link_ready(int id) {
    if (!luat_airlink_link_configured(id)) return 0;
    airlink_instance_t* l = &links[id];
    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
    int ready = l->running && !l->stalled && l->last_rx && luat_mcu_tick64_ms() - l->last_rx < 20000;
    luat_rtos_mutex_unlock(l->lock);
    return ready;
}
static int features(int drv) {
    /* Current Air6205 firmware also provides BLE over RPC. */
    if (drv == AIRLINK_DRV_6208 || drv == AIRLINK_DRV_6205) return AIRLINK_FEATURE_WIFI | AIRLINK_FEATURE_BLE;
    if (drv == AIRLINK_DRV_780EPM) return AIRLINK_FEATURE_CELLULAR;
    return 0;
}
int luat_airlink_feature_route(int feature) {
    for (int i = 0; i < AIRLINK_LINK_COUNT; i++)
        if (links[i].configured && (features(links[i].conf.drv) & feature)) return AIRLINK_ROUTE_BASE + i;
    return luat_airlink_instance_enabled() ? -1 : luat_airlink_current_mode_get();
}
int luat_airlink_feature_rpc_supported(int feature) {
    int route = luat_airlink_feature_route(feature);
    if (!luat_airlink_instance_enabled()) return route >= 0 && luat_airlink_peer_rpc_supported();
    return route >= AIRLINK_ROUTE_BASE && luat_airlink_link_ready(route - AIRLINK_ROUTE_BASE) &&
        luat_airlink_flags_supported_link(route - AIRLINK_ROUTE_BASE, 1);
}
int luat_airlink_rpc_route(int route, unsigned rpc_id) {
    if (!luat_airlink_instance_enabled() || (route >= AIRLINK_ROUTE_BASE && route < AIRLINK_ROUTE_BASE + AIRLINK_LINK_COUNT)) return route;
    int source = luat_airlink_context_link();
    if (source >= 0) return AIRLINK_ROUTE_BASE + source;
    switch (rpc_id >> 8) {
    case 3: return luat_airlink_feature_route(AIRLINK_FEATURE_WIFI);
    case 6: return luat_airlink_feature_route(AIRLINK_FEATURE_BLE);
    case 7: return luat_airlink_feature_route(AIRLINK_FEATURE_CELLULAR);
    default: return AIRLINK_ROUTE_BASE + (links[0].configured ? 0 : 1);
    }
}
int luat_airlink_instance_default_route(const luat_airlink_cmd_t* cmd) {
    int source = luat_airlink_context_link();
    if (source >= 0) return AIRLINK_ROUTE_BASE + source;
    if (cmd->cmd >= 0x200 && cmd->cmd < 0x300) return luat_airlink_feature_route(AIRLINK_FEATURE_WIFI);
    if (cmd->cmd >= 0x500 && cmd->cmd < 0x600) return luat_airlink_feature_route(AIRLINK_FEATURE_BLE);
    if (cmd->cmd >= 0x800 && cmd->cmd < 0x900) return luat_airlink_feature_route(AIRLINK_FEATURE_CELLULAR);
    return AIRLINK_ROUTE_BASE + (links[0].configured ? 0 : 1);
}
int luat_airlink_link_adapter(int id, int remote) {
    if (!luat_airlink_link_configured(id)) return -1;
    luat_airlink_setup_t* c = &links[id].conf;
    if (remote == NW_ADAPTER_INDEX_LWIP_WIFI_STA) return c->sta_adapter;
    if (remote == NW_ADAPTER_INDEX_LWIP_WIFI_AP) return c->ap_adapter;
    if (remote == NW_ADAPTER_INDEX_LWIP_GP_GW) return c->cellular_adapter;
    return -1;
}
static int remote_adapter(const luat_airlink_setup_t* c, int local) {
    if (local < 0) return -1;
    if (local == c->sta_adapter) return NW_ADAPTER_INDEX_LWIP_WIFI_STA;
    if (local == c->ap_adapter) return NW_ADAPTER_INDEX_LWIP_WIFI_AP;
    if (local == c->cellular_adapter) return NW_ADAPTER_INDEX_LWIP_GP_GW;
    return -1;
}

int luat_airlink_link_send(int id, const luat_airlink_cmd_t* cmd) {
    if (!luat_airlink_link_configured(id) || !cmd || cmd->cmd == AIRLINK_CMD_ARQ) return -1;
    airlink_instance_t* l = &links[id];
    unsigned max_data = l->conf.mode == LUAT_AIRLINK_MODE_UART ? AIRLINK_ARQ_MAX_DATA : 1580;
    unsigned chunk = max_data - 8;
    unsigned count = cmd->len <= max_data ? 1 : (cmd->len + chunk - 1) / chunk;
    if (count > QUEUE_DEPTH || (count > 1 && !luat_airlink_flags_supported_link(id, 0))) return -5;
    /* Allocate the entire group before enqueueing. All producers take this lock;
     * consumers can only make more room, so a failed allocation publishes nothing. */
    luat_airlink_cmd_t* group[QUEUE_DEPTH] = {0};
    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
    int ret = -1;
    size_t queued = 0;
    if (!l->running || luat_rtos_queue_get_cnt(l->tx, &queued) || queued + count > QUEUE_DEPTH) goto done;
    uint16_t frag = ++l->fragment;
    for (unsigned n = 0, off = 0; n < count; n++) {
        unsigned len = count == 1 ? cmd->len : (cmd->len - off > chunk ? chunk : cmd->len - off);
        group[n] = luat_airlink_cmd_new(count == 1 ? cmd->cmd : AIRLINK_CMD_FRAGMENT, len + (count == 1 ? 0 : 8));
        if (!group[n]) goto done;
        uint8_t* dst = group[n]->data;
        if (count > 1) {
            memcpy(dst, &cmd->cmd, 2); memcpy(dst + 2, &frag, 2); memcpy(dst + 4, &cmd->len, 2);
            dst[6] = n; dst[7] = count; dst += 8;
        }
        memcpy(dst, cmd->data + off, len); off += len;
    }
    for (unsigned n = 0; n < count; n++) {
        airlink_queue_item_t item = {sizeof(*group[n]) + group[n]->len, group[n]};
        if (luat_rtos_queue_send(l->tx, &item, 0, 0)) goto done;
        group[n] = NULL;
    }
    ret = 0;
done:
    for (unsigned n = 0; n < count; n++) luat_airlink_cmd_free(group[n]);
    luat_rtos_mutex_unlock(l->lock);
    return ret;
}
int luat_airlink_link_send_ip(uint8_t adapter, const uint8_t* data, size_t len) {
    if (!data || len < 8) return -1;
    for (int id = 0; id < AIRLINK_LINK_COUNT; id++) {
        airlink_instance_t* l = &links[id];
        int remote = l->configured ? remote_adapter(&l->conf, adapter) : -1;
        if (remote < 0) continue;
        unsigned max_data = l->conf.mode == LUAT_AIRLINK_MODE_UART ? AIRLINK_ARQ_MAX_DATA : 1580;
        if (len >= max_data) return -5;
        luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x100, len + 1);
        if (!cmd) return -2;
        cmd->data[0] = remote;
        memcpy(cmd->data + 1, data, len);
        airlink_queue_item_t item = {sizeof(*cmd) + cmd->len, cmd};
        luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
        int ret = l->running ? luat_rtos_queue_send(l->ip, &item, 0, 0) : -1;
        if (ret) { luat_airlink_statistics_add(&l->stats.tx_ip.drop, 1); luat_airlink_statistics_add(&l->stats.tx_bytes.drop, len); }
        luat_rtos_mutex_unlock(l->lock);
        if (ret) luat_airlink_cmd_free(cmd);
        return ret;
    }
    return -1; // Never redirect an unbound or stopped adapter to another peer.
}
int luat_airlink_link_receive(int id, const uint8_t* data, size_t len) {
    if (!luat_airlink_link_configured(id) || !data || len < sizeof(luat_airlink_cmd_t)) return -1;
    uint16_t command, payload;
    memcpy(&command, data, 2); memcpy(&payload, data + 2, 2);
    if (payload > len - sizeof(luat_airlink_cmd_t)) return -1;
    airlink_instance_t* l = &links[id];
    if (!command) return l->running ? 0 : -1;
    luat_airlink_cmd_t* copy = luat_airlink_cmd_new(command, payload);
    if (!copy) return -1;
    memcpy(copy->data, data + sizeof(*copy), payload);
    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
    int ret = l->running ? luat_rtos_queue_send(l->rx, &copy, 0, 0) : -1;
    luat_rtos_mutex_unlock(l->lock);
    if (ret) luat_airlink_cmd_free(copy);
    return ret; // ARQ commits ACK only after ownership transfers to this queue.
}
static void dispatch_task(void* param) {
    airlink_instance_t* l = param;
    l->dispatch_task = luat_rtos_get_current_handle();
    while (l->running) {
        luat_airlink_cmd_t* cmd = NULL;
        if (luat_rtos_queue_recv(l->rx, &cmd, 0, 20) || !cmd) continue;
        if (l->running) {
            luat_airlink_instance_dispatch(cmd);
        }
        luat_airlink_cmd_free(cmd);
    }
    luat_airlink_cmd_t* cmd;
    while (!luat_rtos_queue_recv(l->rx, &cmd, 0, 0)) luat_airlink_cmd_free(cmd);
    luat_airlink_fragment_reset();
    luat_rtos_task_handle self = l->dispatch_task;
    l->dispatch_task = NULL;
    luat_rtos_task_delete(self);
}
int luat_airlink_link_spi_transfer(int id, const uint8_t* tx, uint8_t* rx, size_t len) {
    if (!luat_airlink_link_configured(id)) return -1;
    luat_airlink_setup_t* c = &links[id].conf;
    int bus = -1;
    for (int i = 0; i < AIRLINK_LINK_COUNT; i++) if (buses[i].used && buses[i].id == c->spi_id) bus = i;
    if (bus < 0) return -1;
    luat_rtos_mutex_lock(buses[bus].lock, LUAT_WAIT_FOREVER);
    luat_spi_t spi = {0};
    spi.id = c->spi_id; spi.master = 1; spi.mode = 1; spi.dataw = 8;
    spi.bit_dict = 1; spi.cs = 255; spi.bandrate = c->speed;
    spi.CPHA = spi.CPOL = c->mode == LUAT_AIRLINK_MODE_SPI_MASTER ? 1 : 0;
    int ret;
    if (!buses[bus].initialized) {
        ret = luat_spi_setup(&spi);
        if (!ret) buses[bus].initialized = 1;
    } else {
        luat_spi_device_t dev = {0}; dev.bus_id = c->spi_id; dev.spi_config = spi;
        ret = luat_spi_device_config(&dev);
    }
    if (!ret) {
        luat_gpio_set(c->cs, 0);
        ret = luat_spi_transfer(c->spi_id, (const char*)tx, len, (char*)rx, len);
        luat_gpio_set(c->cs, 1);
        if (ret != (int)len) ret = -1;
    } else ret = -1;
    luat_rtos_mutex_unlock(buses[bus].lock);
    return ret;
}
static void receive_frame(airlink_instance_t* l, airlink_link_data_t* frame) {
    int id = (int)(l - links);
    int ret = l->conf.mode == LUAT_AIRLINK_MODE_UART ? luat_airlink_arq_receive(frame) :
        luat_airlink_link_receive(id, frame->data, frame->len);
    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
    luat_airlink_statistics_add(&l->stats.rx_pkg.total, 1);
    if (!ret) { l->last_rx = luat_mcu_tick64_ms(); luat_airlink_statistics_add(&l->stats.rx_pkg.ok, 1); }
    else luat_airlink_statistics_add(&l->stats.rx_pkg.drop, 1);
    luat_rtos_mutex_unlock(l->lock);
}
static void uart_feed(airlink_instance_t* l, const uint8_t* bytes, size_t len) {
    for (size_t i = 0; i < len; i++) {
        uint8_t b = bytes[i];
        if (b == 0x7E) {
            if (l->in_frame && l->rx_used >= sizeof(airlink_link_data_t) && !l->escaped) {
                airlink_link_data_t* f = luat_airlink_data_unpack_uart(l->rxbuf, l->rx_used);
                if (f) receive_frame(l, f);
            }
            l->rx_used = 0; l->escaped = 0; l->in_frame = 1;
        } else if (l->in_frame) {
            if (l->escaped) {
                l->escaped = 0;
                if (b == 1) b = 0x7D;
                else if (b == 2) b = 0x7E;
                else { l->in_frame = 0; continue; }
            } else if (b == 0x7D) { l->escaped = 1; continue; }
            if (l->rx_used == RX_SIZE) { l->in_frame = 0; l->rx_used = 0; }
            else l->rxbuf[l->rx_used++] = b;
        }
    }
}
static int send_frame(airlink_instance_t* l, size_t len) {
    if (!len || len > FRAME_SIZE) return -1;
    if (l->conf.mode == LUAT_AIRLINK_MODE_UART) {
        if (l->tx_busy) return -1;
        size_t out = 0;
        l->wire[out++] = 0x7E;
        for (size_t i = 0; i < len; i++) {
            uint8_t b = l->txbuf[i];
            if (b == 0x7D || b == 0x7E) { l->wire[out++] = 0x7D; l->wire[out++] = b == 0x7D ? 1 : 2; }
            else l->wire[out++] = b;
        }
        l->wire[out++] = 0x7E;
        l->tx_busy = 1;
        if (luat_uart_write(l->conf.uart_id, l->wire, out) == (int)out) return 0;
        l->tx_busy = 0;
        return -1;
    }
    if (len < FRAME_SIZE) memset(l->txbuf + len, 0, FRAME_SIZE - len);
    int ret = luat_airlink_link_spi_transfer((int)(l - links), l->txbuf, l->rxbuf, FRAME_SIZE);
    if (ret != FRAME_SIZE) return -1;
    airlink_link_data_t* f = luat_airlink_data_unpack(l->rxbuf, FRAME_SIZE);
    if (f) receive_frame(l, f);
    return 0;
}
static int send_cmd(airlink_instance_t* l, const luat_airlink_cmd_t* cmd, int reliable) {
#ifdef LUAT_USE_AIRLINK_HSPI_MASTER
    if (l->conf.mode == LUAT_AIRLINK_MODE_HSPI_MASTER)
        return xt804_hspi_send_cmd(cmd->cmd, cmd->data, cmd->len, NULL, NULL, 0);
#endif
    size_t len;
    if (reliable) len = luat_airlink_arq_pack(l->txbuf, FRAME_SIZE, cmd, luat_airlink_arq_pending_seq());
    else {
        if (cmd->len > 1580) return -1;
        len = sizeof(airlink_link_data_t) + sizeof(*cmd) + cmd->len;
        luat_airlink_data_pack((uint8_t*)cmd, sizeof(*cmd) + cmd->len, l->txbuf);
    }
    int ret = send_frame(l, len);
    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
    luat_airlink_statistics_add(&l->stats.tx_pkg.total, 1);
    luat_airlink_statistics_add(ret ? &l->stats.tx_pkg.err : &l->stats.tx_pkg.ok, 1);
    luat_rtos_mutex_unlock(l->lock);
    return ret;
}
static int next_item(airlink_instance_t* l, airlink_queue_item_t* item) {
    /* Four commands at most before servicing waiting IP traffic. */
    if (l->cmd_budget >= 4 && !luat_rtos_queue_recv(l->ip, item, 0, 0)) { l->cmd_budget = 0; return 0; }
    if (!luat_rtos_queue_recv(l->tx, item, 0, 0)) { if (l->cmd_budget < 4) l->cmd_budget++; return 0; }
    l->cmd_budget = 0;
    return luat_rtos_queue_recv(l->ip, item, 0, 0);
}
static void io_task(void* param) {
    airlink_instance_t* l = param;
    l->io_task = luat_rtos_get_current_handle();
    int id = (int)(l - links);
    luat_airlink_arq_init();
    uint64_t heartbeat = 0;
#ifdef LUAT_USE_AIRLINK_HSPI_MASTER
    if (l->conf.mode == LUAT_AIRLINK_MODE_HSPI_MASTER) xt804_hspi_enable_host_int();
#endif
    while (l->running) {
        if (l->conf.mode == LUAT_AIRLINK_MODE_UART) {
            uint8_t bytes[512];
            for (int burst = 0; burst < 32 && l->running; burst++) {
                int n = luat_uart_read(l->conf.uart_id, bytes, sizeof(bytes));
                if (n <= 0) break;
                uart_feed(l, bytes, n);
            }
        }
#ifdef LUAT_USE_AIRLINK_HSPI_MASTER
        if (l->conf.mode == LUAT_AIRLINK_MODE_HSPI_MASTER) {
            uint16_t len = FRAME_SIZE - 4, cmd = 0;
            if (!xt804_hspi_read_data_intr(l->rxbuf + 4, &len, &cmd)) {
                memcpy(l->rxbuf, &cmd, 2); memcpy(l->rxbuf + 2, &len, 2);
                if (!luat_airlink_link_receive(id, l->rxbuf, len + 4)) {
                    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
                    l->last_rx = luat_mcu_tick64_ms();
                    luat_rtos_mutex_unlock(l->lock);
                }
            }
        }
#endif
        uint64_t now = luat_mcu_tick64_ms();
        luat_airlink_arq_pending_try_ack();
        luat_airlink_arq_check_giveup(now);
        luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
        if (luat_airlink_arq_consume_force_down()) l->stalled = 1;
        if (!luat_airlink_arq_pending_active()) l->stalled = 0;
        luat_rtos_mutex_unlock(l->lock);
        l->ack_due |= luat_airlink_arq_take_need_ack();
        /* One frame in the HAL at a time, including legacy traffic. RX keeps
         * draining while TX is busy; no unbounded UART heap backlog. */
        if (l->tx_busy) { luat_rtos_task_sleep(1); continue; }
        if (l->conf.mode == LUAT_AIRLINK_MODE_SPI_MASTER && l->conf.rdy != 255 && luat_gpio_get(l->conf.rdy)) {
            luat_rtos_task_sleep(1);
            continue;
        }
        if (now - heartbeat >= 1000 || luat_airlink_arq_devinfo_pending()) {
            uint8_t info[sizeof(luat_airlink_cmd_t) + sizeof(luat_airlink_dev_info_t) + AIRLINK_ARQ_HELLO_SIZE];
            luat_airlink_arq_devinfo(info, luat_airlink_self_dev_info_ptr());
            if (!send_cmd(l, (void*)info, 0)) luat_airlink_arq_set_devinfo_pending(0);
            heartbeat = now;
            tcpip_callback(instance_net_update, l);
        }
        if (l->tx_busy) { luat_rtos_task_sleep(1); continue; }
        int sent = 0;
        if (luat_airlink_arq_pending_active()) {
            if (now - luat_airlink_arq_pending_sent_ms() >= ARQ_RTO_MS) {
                sent = !send_cmd(l, luat_airlink_arq_pending_cmd(), 1);
                luat_airlink_arq_pending_retransmit(now);
            }
        } else if (luat_airlink_arq_state() != ARQ_STATE_NEGOTIATING && !luat_airlink_arq_peer_mem_high()) {
            airlink_queue_item_t item = {0};
            if (!next_item(l, &item) && item.cmd) {
                if (item.cmd->cmd == 0x100) {
                    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER);
                    luat_airlink_statistics_add(&l->stats.tx_ip.total, 1);
                    luat_airlink_statistics_add(&l->stats.tx_bytes.total, item.cmd->len - 1);
                    luat_rtos_mutex_unlock(l->lock);
                }
                int reliable = l->conf.mode == LUAT_AIRLINK_MODE_UART && luat_airlink_arq_state() == ARQ_STATE_ARQ && item.cmd->cmd != 0x10;
                if (reliable && !luat_airlink_arq_pending_set(item.cmd, now)) {
                    sent = !send_cmd(l, item.cmd, 1);
                    item.cmd = NULL;
                } else if (!reliable) {
                    send_cmd(l, item.cmd, 0);
                }
                luat_airlink_cmd_free(item.cmd);
            } else if (l->conf.mode == LUAT_AIRLINK_MODE_SPI_MASTER && (l->conf.rdy == 255 || !luat_gpio_get(l->conf.rdy))) {
                luat_airlink_cmd_t empty = {0}; send_cmd(l, &empty, 0);
            }
        }
        if (sent) l->ack_due = 0;
        if (l->ack_due && !l->tx_busy && !send_frame(l, luat_airlink_arq_pack(l->txbuf, FRAME_SIZE, NULL, 0))) l->ack_due = 0;
        luat_rtos_task_sleep(1);
    }
    luat_airlink_arq_stop();
    if (l->uart_opened) {
        luat_uart_close(l->conf.uart_id); l->uart_opened = 0;
    }
    airlink_queue_item_t item;
    while (!luat_rtos_queue_recv(l->tx, &item, 0, 0)) luat_airlink_cmd_free(item.cmd);
    while (!luat_rtos_queue_recv(l->ip, &item, 0, 0)) luat_airlink_cmd_free(item.cmd);
    luat_heap_free(l->rxbuf); luat_heap_free(l->txbuf); luat_heap_free(l->wire);
    l->rxbuf = l->txbuf = l->wire = NULL;
    luat_rtos_task_handle self = l->io_task;
    l->io_task = NULL;
    luat_rtos_task_delete(self);
}
static void instance_net_update(void* param) {
    airlink_instance_t* l = param;
    int id = (int)(l - links);
    luat_airlink_dev_info_t peer;
    luat_airlink_link_peer_copy(id, &peer);
    int online = luat_airlink_link_ready(id);
    int adapters[] = {l->conf.sta_adapter, l->conf.ap_adapter, l->conf.cellular_adapter};
    for (int i = 0; i < 3; i++) {
        if (adapters[i] < 0 || !(l->net_owned & (1u << i))) continue;
        luat_netdrv_t* drv = luat_netdrv_get(adapters[i]);
        if (!drv || !drv->netif) continue;
        int up = 0;
        if (i < 2 && peer.tp == 1) {
            const uint8_t* mac = i == 0 ? peer.wifi.sta_mac : peer.wifi.ap_mac;
            if (memcmp(mac, "\0\0\0\0\0\0", 6) && memcmp(drv->netif->hwaddr, mac, 6)) {
                memcpy(drv->netif->hwaddr, mac, 6); drv->netif->hwaddr_len = 6;
#if LWIP_IPV6
                extern int net_lwip2_ipv6_create_linklocal(uint8_t adapter_index);
                net_lwip2_ipv6_create_linklocal(adapters[i]);
#endif
            }
            up = online && (i == 0 ? peer.wifi.sta_state : peer.wifi.ap_state);
        } else if (i == 2 && peer.tp == 2) {
            /* GP_GW is the inter-device routed subnet. The modem's WAN IP is
             * informational: never overwrite the application's NAPT-side IP. */
            up = online && (peer.cat1.cat_state == 1 || peer.cat1.cat_state == 5);
        }
        if (!!netif_is_link_up(drv->netif) != !!up) luat_netdrv_set_link_updown(drv, !!up);
    }
}
static void instance_net_setup(void* param) {
    airlink_instance_t* l = param;
    int adapters[] = {l->conf.sta_adapter, l->conf.ap_adapter, l->conf.cellular_adapter};
    l->net_result = -1;
    /* setup owns new adapters exclusively; never reboot an unrelated driver. */
    for (int i = 0; i < 3; i++)
        if (adapters[i] >= 0 && luat_netdrv_get(adapters[i])) goto done;
    for (int i = 0; i < 3; i++) {
        if (adapters[i] < 0) continue;
        luat_netdrv_conf_t c = {0}; c.id = adapters[i]; c.impl = LUAT_NETDRV_IMPL_WHALE;
        if (i < 2) {
            c.flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP;
#if LWIP_IGMP
            c.flags |= NETIF_FLAG_IGMP;
#endif
#if LWIP_IPV6
            c.flags |= NETIF_FLAG_MLD6;
#endif
        }
        luat_netdrv_t* drv = luat_netdrv_setup(&c);
        if (drv) l->net_owned |= 1u << i;
        if (!drv || !drv->netif) goto done;
        if (i == 0) drv->dhcp_enable = 1;
        luat_netdrv_set_link_updown(drv, 0);
    }
    l->net_result = 0;
done:
    luat_rtos_semaphore_release(l->net_done);
}
static void uart_rx(int uart_id, uint32_t len) { (void)uart_id; (void)len; }
static void release_instance(airlink_instance_t* l) {
    if (l->uart_opened) {
        luat_uart_close(l->conf.uart_id);
    }
    if (l->tx) luat_rtos_queue_delete(l->tx);
    if (l->ip) luat_rtos_queue_delete(l->ip);
    if (l->rx) luat_rtos_queue_delete(l->rx);
    if (l->lock) luat_rtos_mutex_delete(l->lock);
    if (l->net_done) luat_rtos_semaphore_delete(l->net_done);
    luat_heap_free(l->rxbuf); luat_heap_free(l->txbuf); luat_heap_free(l->wire);
    memset(l, 0, sizeof(*l));
}
int luat_airlink_setup_link(int id, const luat_airlink_setup_t* c) {
    extern luat_rtos_queue_t airlink_cmd_queue;
    if (airlink_cmd_queue || luat_airlink_current_mode_get() >= 0) return -7;
    if (id < 0 || id >= AIRLINK_LINK_COUNT || !c || !features(c->drv)) return -1;
    if (links[id].configured) return -2;
    if (c->mode != LUAT_AIRLINK_MODE_UART && c->mode != LUAT_AIRLINK_MODE_SPI_MASTER && c->mode != LUAT_AIRLINK_MODE_HSPI_MASTER) return -3;
#ifndef LUAT_USE_AIRLINK_HSPI_MASTER
    if (c->mode == LUAT_AIRLINK_MODE_HSPI_MASTER) return -3;
#endif
    if (!c->speed || (c->mode == LUAT_AIRLINK_MODE_UART && c->uart_id >= 10)) return -4;
    if (c->drv == AIRLINK_DRV_780EPM ? c->sta_adapter >= 0 || c->ap_adapter >= 0 : c->cellular_adapter >= 0) return -4;
    int adapters[] = {c->sta_adapter, c->ap_adapter, c->cellular_adapter};
    for (int a = 0; a < 3; a++) {
        if (adapters[a] < -1 || adapters[a] >= LUAT_AIRLINK_MAX_ADAPTERS) return -4;
        if (adapters[a] >= 0) for (int b = 0; b < a; b++) if (adapters[a] == adapters[b]) return -4;
    }
    for (int i = 0; i < AIRLINK_LINK_COUNT; i++) {
        if (!links[i].configured) continue;
        luat_airlink_setup_t* o = &links[i].conf;
        if (c->mode == LUAT_AIRLINK_MODE_UART && o->mode == c->mode && o->uart_id == c->uart_id) return -5;
        if (c->mode != LUAT_AIRLINK_MODE_UART && o->mode != LUAT_AIRLINK_MODE_UART && c->spi_id == o->spi_id && c->cs == o->cs) return -5;
        for (int a = 0; a < 3; a++) if (remote_adapter(o, adapters[a]) >= 0) return -5;
    }
    airlink_instance_t* l = &links[id];
    l->conf = *c;
    if (luat_rtos_semaphore_create(&l->net_done, 0)) goto fail;
    luat_rtos_semaphore_take(l->net_done, 0);
    if (luat_rtos_mutex_create(&l->lock) || luat_rtos_queue_create(&l->tx, QUEUE_DEPTH, sizeof(airlink_queue_item_t)) ||
        luat_rtos_queue_create(&l->ip, QUEUE_DEPTH, sizeof(airlink_queue_item_t)) || luat_rtos_queue_create(&l->rx, QUEUE_DEPTH, sizeof(luat_airlink_cmd_t*))) goto fail;
    l->rxbuf = luat_heap_malloc(RX_SIZE); l->txbuf = luat_heap_malloc(FRAME_SIZE); l->wire = luat_heap_malloc(FRAME_SIZE * 2 + 2);
    if (!l->rxbuf || !l->txbuf || !l->wire) goto fail;
    if (c->mode == LUAT_AIRLINK_MODE_UART) {
        luat_uart_t uart = {0}; uart.id = c->uart_id; uart.baud_rate = c->speed;
        uart.data_bits = 8; uart.stop_bits = 1; uart.bufsz = RX_SIZE; uart.pin485 = 255;
        if (luat_uart_setup(&uart)) goto fail;
        l->uart_opened = 1;
        if (luat_uart_ctrl(c->uart_id, LUAT_UART_SET_RECV_CALLBACK, uart_rx)) goto fail;
        if (luat_uart_ctrl(c->uart_id, LUAT_UART_SET_SENT_CALLBACK, uart_sent)) goto fail;
    } else {
        if (c->cs == 255) goto fail;
        luat_gpio_cfg_t gpio; luat_gpio_set_default_cfg(&gpio);
        gpio.pin = c->cs; gpio.mode = Luat_GPIO_OUTPUT; gpio.output_level = 1;
        if (luat_gpio_open(&gpio)) goto fail;
        if (c->rdy != 255) {
            luat_gpio_set_default_cfg(&gpio); gpio.pin = c->rdy; gpio.mode = Luat_GPIO_INPUT; gpio.pull = Luat_GPIO_PULLUP;
            if (luat_gpio_open(&gpio)) goto fail;
        }
        int bus = -1;
        for (int i = 0; i < AIRLINK_LINK_COUNT; i++) if (buses[i].used && buses[i].id == c->spi_id) bus = i;
        if (bus < 0) for (int i = 0; i < AIRLINK_LINK_COUNT; i++) if (!buses[i].used) {
            if (luat_rtos_mutex_create(&buses[i].lock)) goto fail;
            buses[i].id = c->spi_id; buses[i].used = 1; bus = i; break;
        }
        if (bus < 0) goto fail;
    }
    luat_airlink_init();
    l->configured = 1;
    if (tcpip_callback(instance_net_setup, l) != ERR_OK) {
        l->configured = 0;
        goto fail;
    }
    luat_rtos_semaphore_take(l->net_done, LUAT_WAIT_FOREVER);
    luat_rtos_semaphore_delete(l->net_done); l->net_done = NULL;
    if (l->net_result) {
        if (!l->net_owned) { l->configured = 0; goto fail; }
        goto started_fail;
    }
    l->running = 1;
    if (luat_rtos_task_create(&l->dispatch_task, 16 * 1024, 50, "airlink_rx", dispatch_task, l, 0)) goto started_fail;
    if (luat_rtos_task_create(&l->io_task, 16 * 1024, 50, "airlink_io", io_task, l, 0)) goto started_fail;
    LLOGI("setup link=%d mode=%d uart=%d speed=%u", id, c->mode, c->uart_id, c->speed);
    return 0;
started_fail:
    l->running = 0;
    while (l->dispatch_task || l->io_task) luat_rtos_task_sleep(5);
    if (l->uart_opened) { luat_uart_close(l->conf.uart_id); l->uart_opened = 0; }
    luat_heap_free(l->rxbuf); luat_heap_free(l->txbuf); luat_heap_free(l->wire);
    l->rxbuf = l->txbuf = l->wire = NULL;
    /* Netdrv has no destroy API. Keep a failed claim reserved, like close(),
     * so partial network creation cannot route into a later different peer. */
    return -6;
fail:
    release_instance(l);
    return -6;
}
int luat_airlink_stop_link(int id) {
    if (!luat_airlink_link_configured(id)) return -1;
    airlink_instance_t* l = &links[id];
    luat_rtos_mutex_lock(l->lock, LUAT_WAIT_FOREVER); l->running = 0; luat_rtos_mutex_unlock(l->lock);
    tcpip_callback(instance_net_update, l);
    /* Keep routing reserved so late responses never fall through to another peer.
     * Workers drain payloads and release transport buffers before exiting. */
    return 0;
}
#endif
