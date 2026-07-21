#include "tiny_epd_port_sim.h"

#include <stdlib.h>
#include <string.h>

static int tiny_epd_sim_write_cmd(void *user, uint8_t cmd)
{
    tiny_epd_sim_t *sim = (tiny_epd_sim_t *)user;

    if (sim == NULL) {
        return -1;
    }
    if (sim->fail_next_cmd) {
        sim->fail_next_cmd = 0;
        return -1;
    }
    sim->last_cmd = cmd;
    sim->cmd_count[cmd]++;
    sim->write_cmd_total++;
    return 0;
}

uint32_t tiny_epd_sim_checksum_bytes(const uint8_t *data, size_t len)
{
    uint32_t checksum = 0;
    size_t i;

    if (data == NULL && len != 0) {
        return 0;
    }
    for (i = 0; i < len; i++) {
        checksum = (checksum * 131u) + data[i];
    }
    return checksum;
}

static int tiny_epd_sim_write_data(void *user, const uint8_t *data, size_t len)
{
    tiny_epd_sim_t *sim = (tiny_epd_sim_t *)user;
    uint8_t cmd;
    size_t i;

    if (sim == NULL || (data == NULL && len != 0)) {
        return -1;
    }
    if (sim->fail_next_data) {
        sim->fail_next_data = 0;
        return -1;
    }

    cmd = sim->last_cmd;
    for (i = 0; i < len; i++) {
        if (!sim->has_data[cmd]) {
            sim->has_data[cmd] = 1;
            sim->first_data[cmd] = data[i];
        }
        sim->last_data[cmd] = data[i];
        sim->checksum[cmd] = (sim->checksum[cmd] * 131u) + data[i];
    }
    sim->data_count[cmd] += (uint32_t)len;
    sim->write_data_total += (uint32_t)len;
    return 0;
}

static int tiny_epd_sim_reset(void *user, const tiny_epd_reset_sequence_t *sequence)
{
    tiny_epd_sim_t *sim = (tiny_epd_sim_t *)user;
    size_t i;

    if (sim == NULL) {
        return -1;
    }
    if (sim->fail_next_reset) {
        sim->fail_next_reset = 0;
        return -1;
    }
    sim->reset_count++;
    if (sequence == NULL || sequence->steps == NULL) {
        return 0;
    }
    for (i = 0; i < sequence->count; i++) {
        sim->last_reset_level = sequence->steps[i].level;
        sim->delay_ms_total += sequence->steps[i].delay_ms;
        sim->reset_step_count++;
    }
    return 0;
}

static int tiny_epd_sim_wait_busy(void *user, uint8_t idle_level, uint32_t timeout_ms)
{
    tiny_epd_sim_t *sim = (tiny_epd_sim_t *)user;

    if (sim == NULL) {
        return -1;
    }
    if (sim->fail_next_busy) {
        sim->fail_next_busy = 0;
        return -1;
    }
    sim->busy_wait_count++;
    sim->last_busy_idle_level = idle_level;
    sim->last_busy_timeout_ms = timeout_ms;
    return 0;
}

static void tiny_epd_sim_delay_ms(void *user, uint32_t ms)
{
    tiny_epd_sim_t *sim = (tiny_epd_sim_t *)user;

    if (sim != NULL) {
        sim->delay_ms_total += ms;
    }
}

static void *tiny_epd_sim_malloc(void *user, size_t size)
{
    (void)user;
    return malloc(size);
}

static void tiny_epd_sim_free(void *user, void *ptr)
{
    (void)user;
    free(ptr);
}

void tiny_epd_sim_init(tiny_epd_sim_t *sim)
{
    if (sim != NULL) {
        memset(sim, 0, sizeof(*sim));
    }
}

void tiny_epd_sim_reset_trace(tiny_epd_sim_t *sim)
{
    uint8_t fail_next_cmd;
    uint8_t fail_next_data;
    uint8_t fail_next_reset;
    uint8_t fail_next_busy;

    if (sim == NULL) {
        return;
    }

    fail_next_cmd = sim->fail_next_cmd;
    fail_next_data = sim->fail_next_data;
    fail_next_reset = sim->fail_next_reset;
    fail_next_busy = sim->fail_next_busy;
    memset(sim, 0, sizeof(*sim));
    sim->fail_next_cmd = fail_next_cmd;
    sim->fail_next_data = fail_next_data;
    sim->fail_next_reset = fail_next_reset;
    sim->fail_next_busy = fail_next_busy;
}

tiny_epd_port_t tiny_epd_sim_port(tiny_epd_sim_t *sim)
{
    tiny_epd_port_t port;

    memset(&port, 0, sizeof(port));
    port.user = sim;
    port.write_cmd = tiny_epd_sim_write_cmd;
    port.write_data = tiny_epd_sim_write_data;
    port.reset = tiny_epd_sim_reset;
    port.wait_busy = tiny_epd_sim_wait_busy;
    port.delay_ms = tiny_epd_sim_delay_ms;
    port.malloc = tiny_epd_sim_malloc;
    port.free = tiny_epd_sim_free;
    return port;
}
