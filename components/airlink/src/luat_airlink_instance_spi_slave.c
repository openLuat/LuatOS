#include "luat_base.h"
#ifdef LUAT_USE_AIRLINK_INSTANCE
#include "luat_airlink.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "luat_mcu.h"

/* EC718M has hardware SS and fixed-length RX DMA completion. Do not use the
 * legacy singleton slave task: its queues, device info and mode are global. */
#ifdef TYPE_EC718M
#include "ec7xx.h"

#define SLAVE_FRAME_SIZE 1600
#define SLAVE_TIMEOUT_MS 2000
#define SLAVE_REARM_MS 20

typedef struct {
    uint8_t opened, spi_id, rdy;
    int active, completed;
    uint64_t started, rearm_at;
} instance_slave_t;
static instance_slave_t slaves[AIRLINK_LINK_COUNT];

static SPI_TypeDef* slave_regs(instance_slave_t* s) { return s->spi_id ? SPI1 : SPI0; }

/* Stop DMA before the IO worker reads or frees either buffer. RDY stays high
 * until a fresh complete TX/RX pair has been armed. State is IRQ/task shared. */
__AIRLINK_CODE_IN_RAM__ static int slave_rx_done(int event, void* param) {
    (void)event;
    instance_slave_t* s = param;
    if (!__atomic_load_n(&s->active, __ATOMIC_ACQUIRE)) return 0;
    luat_gpio_set(s->rdy, 1);
    luat_spi_slave_transfer_pause_in_irq(s->spi_id);
    __atomic_store_n(&s->completed, 1, __ATOMIC_RELEASE);
    return 0;
}

int luat_airlink_instance_slave_check(const luat_airlink_setup_t* c) {
    /* Native SS is essential: GPIO-only CS cannot gate an unrelated master's
     * clocks. Each slave owns its controller; RDY is mandatory. */
    if (!c || !((c->spi_id == 0 && c->cs == 8) || (c->spi_id == 1 && c->cs == 12)) ||
        c->rdy == 255 || (c->rdy >= 8 && c->rdy <= 15) ||
        c->speed < 1000000 || c->speed > 20000000)
        return -4;
    return 0;
}

static void slave_stop_dma(instance_slave_t* s) {
    __atomic_store_n(&s->active, 0, __ATOMIC_RELEASE);
    luat_gpio_set(s->rdy, 1);
    luat_spi_slave_transfer_stop(s->spi_id);
    slave_regs(s)->FFR = SPI_FFR_TX_FLUSH_Msk | SPI_FFR_RX_FLUSH_Msk;
    __atomic_store_n(&s->completed, 0, __ATOMIC_RELEASE);
}

void luat_airlink_instance_slave_close(int id) {
    if (id < 0 || id >= AIRLINK_LINK_COUNT || !slaves[id].opened) return;
    instance_slave_t* s = &slaves[id];
    slave_stop_dma(s);
    luat_spi_set_slave_callback(s->spi_id, NULL, NULL);
    luat_spi_close(s->spi_id);
    s->opened = 0;
    /* Keep RDY driven high. A still-running master must not clock freed DMA
     * buffers. Instance close reserves the controller/pins until reboot. */
}

int luat_airlink_instance_slave_open(int id, const luat_airlink_setup_t* c) {
    int rc = luat_airlink_instance_slave_check(c);
    if (rc) return rc;
    if (id < 0 || id >= AIRLINK_LINK_COUNT || slaves[id].opened) return -4;
    instance_slave_t* s = &slaves[id];
    memset(s, 0, sizeof(*s));
    s->spi_id = c->spi_id; s->rdy = c->rdy;
    luat_gpio_cfg_t gpio;
    luat_gpio_set_default_cfg(&gpio);
    gpio.pin = c->rdy; gpio.mode = Luat_GPIO_OUTPUT;
    gpio.pull = Luat_GPIO_PULLUP; gpio.output_level = 1;
    if (luat_gpio_open(&gpio)) return -6;
    luat_spi_t spi = {0};
    spi.id = c->spi_id; spi.cs = c->cs; spi.master = 0;
    spi.CPOL = spi.CPHA = 1; spi.dataw = 8; spi.bit_dict = 1;
    /* Keep the existing EC718M slave HAL clock configuration. The wire clock
     * is driven by the peer; c->speed describes that external clock. */
    spi.mode = 1; spi.bandrate = 60000000;
    /* Setup hardware SS last; opening its pad as GPIO would replace the mux. */
    if (luat_spi_setup(&spi)) return -6;
    s->opened = 1;
    SPI_TypeDef* regs = slave_regs(s);
    /* A 1600-byte frame is an exact multiple of the 8-byte DMA burst. Request
     * the last burst directly, without an EOR/timeout callback or FIFO append. */
    regs->DRLR = (regs->DRLR & ~SPI_DRLR_RX_REQ_LVL_Msk) | 8;
    regs->DRRCR &= ~SPI_DRRCR_RX_TO_REQ_EN_Msk;
    if (luat_spi_set_slave_callback(c->spi_id, slave_rx_done, s)) {
        luat_airlink_instance_slave_close(id);
        return -6;
    }
    return 0;
}

int luat_airlink_instance_slave_start(int id, uint8_t* tx, uint8_t* rx, size_t len) {
    if (id < 0 || id >= AIRLINK_LINK_COUNT || !tx || !rx || len != SLAVE_FRAME_SIZE) return -1;
    instance_slave_t* s = &slaves[id];
    if (!s->opened || __atomic_load_n(&s->active, __ATOMIC_ACQUIRE)) return -1;
    if (luat_mcu_tick64_ms() < s->rearm_at) return -1;
    memset(rx, 0, len);
    __atomic_store_n(&s->completed, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&s->active, 1, __ATOMIC_RELEASE);
    s->started = luat_mcu_tick64_ms();
    if (luat_spi_slave_transfer(s->spi_id, (const char*)tx, (char*)rx, len)) {
        slave_stop_dma(s);
        return -1;
    }
    luat_gpio_set(s->rdy, 0);
    return 0;
}

int luat_airlink_instance_slave_poll(int id) {
    if (id < 0 || id >= AIRLINK_LINK_COUNT || !slaves[id].opened) return -1;
    instance_slave_t* s = &slaves[id];
    if (luat_mcu_tick64_ms() < s->rearm_at) return -2;
    if (!__atomic_load_n(&s->active, __ATOMIC_ACQUIRE)) return 0;
    if (__atomic_load_n(&s->completed, __ATOMIC_ACQUIRE)) {
        slave_stop_dma(s);
        return SLAVE_FRAME_SIZE;
    }
    if (luat_mcu_tick64_ms() - s->started >= SLAVE_TIMEOUT_MS) {
        /* Recover a master reset or a truncated transaction, not just full
         * frames. Hold RDY high longer than one frame at the minimum 1 MHz
         * before rearming, allowing an in-flight transaction to drain. */
        slave_stop_dma(s);
        s->rearm_at = luat_mcu_tick64_ms() + SLAVE_REARM_MS;
        return -1;
    }
    return 0;
}
#else
int luat_airlink_instance_slave_check(const luat_airlink_setup_t* c) { (void)c; return -3; }
int luat_airlink_instance_slave_open(int id, const luat_airlink_setup_t* c) { (void)id; (void)c; return -3; }
int luat_airlink_instance_slave_start(int id, uint8_t* tx, uint8_t* rx, size_t len) {
    (void)id; (void)tx; (void)rx; (void)len; return -3;
}
int luat_airlink_instance_slave_poll(int id) { (void)id; return -3; }
void luat_airlink_instance_slave_close(int id) { (void)id; }
#endif
#endif
