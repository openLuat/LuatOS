
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_spi.h"
#ifdef LUAT_USE_WINDOWS
#include "luat_ch347_pc.h"
#endif
#include <stdlib.h>
#include <string.h>

// 模拟SPI在win32下的实现
// TODO 当需要返回数据时, 调用lua方法获取需要返回的数据

#define LUAT_LOG_TAG "luat.spi"
#include "luat_log.h"

#define LUAT_WIN32_SPI_COUNT (3)
#define LUAT_PC_NAND_DEFAULT_TOTAL_SIZE    (128u * 1024u * 1024u)
#define LUAT_PC_NAND_DEFAULT_PAGE_SIZE     (2048u)
#define LUAT_PC_NAND_DEFAULT_PAGES_PER_BLK (64u)
#define LUAT_PC_NAND_DEFAULT_READ_DELAY_US (50u)
#define LUAT_PC_NAND_DEFAULT_PROG_DELAY_US (700u)
#define LUAT_PC_NAND_DEFAULT_ERASE_DELAY_US (2000u)
#define LUAT_PC_NAND_DEFAULT_BAD_RATIO     (0.001)
#define LUAT_PC_NAND_DEFAULT_SEED          (0x13572468u)
#define LUAT_PC_NAND_PROFILE_DEFAULT       "dev"

#define NAND_CMD_WRITE_STATUS_LEGACY       (0x01)
#define NAND_CMD_WRITE_STATUS              (0x1F)
#define NAND_CMD_WRITE_DISABLE             (0x04)
#define NAND_CMD_READ_STATUS_LEGACY        (0x05)
#define NAND_CMD_READ_STATUS               (0x0F)
#define NAND_CMD_WRITE_ENABLE              (0x06)
#define NAND_CMD_PAGE_PROG_DATA            (0x02)
#define NAND_CMD_READ_DATA                 (0x03)
#define NAND_CMD_PAGE_PROG_EXEC            (0x10)
#define NAND_CMD_PAGE_DATA_READ            (0x13)
#define NAND_CMD_READ_JEDEC_ID             (0x9F)
#define NAND_CMD_BLOCK_ERASE               (0xD8)
#define NAND_CMD_RESET                     (0xFF)

#define NAND_SR_BUSY                       (0x01)
#define NAND_SR_WEL                        (0x02)
#define NAND_SR_ERASE_FAIL                 (0x04)
#define NAND_SR_PROG_FAIL                  (0x08)

#define NAND_SR1_ADDR                      (0xA0)
#define NAND_SR2_ADDR                      (0xB0)
#define NAND_SR3_ADDR                      (0xC0)
#define NAND_SR4_ADDR                      (0xD0)

typedef struct win32spi {
    luat_spi_t spi;
    uint8_t open;
}win32spi_t;

typedef struct pc_vnand {
    uint8_t initialized;
    uint8_t enabled;
    uint8_t write_enable;
    uint8_t cache_loaded;
    uint8_t prog_load_active;
    uint8_t reg1;
    uint8_t reg2;
    uint8_t reg3;
    uint8_t reg4;
    uint8_t jedec[4];
    uint32_t cache_page;
    uint32_t rand_state;
    uint32_t total_size;
    uint32_t page_size;
    uint32_t pages_per_block;
    uint32_t block_size;
    uint32_t total_pages;
    uint32_t total_blocks;
    uint32_t read_delay_us;
    uint32_t prog_delay_us;
    uint32_t erase_delay_us;
    uint32_t busy_remaining_us;
    uint8_t* storage;
    uint8_t* cache;
    uint8_t* bad_blocks;
} pc_vnand_t;

typedef struct pc_vnand_profile_defaults {
    const char* name;
    uint32_t read_delay_us;
    uint32_t prog_delay_us;
    uint32_t erase_delay_us;
    double bad_ratio;
} pc_vnand_profile_defaults_t;

static const pc_vnand_profile_defaults_t g_pc_vnand_profile_fast = {
    "fast", 1u, 20u, 100u, 0.0
};

static const pc_vnand_profile_defaults_t g_pc_vnand_profile_dev = {
    "dev", LUAT_PC_NAND_DEFAULT_READ_DELAY_US, LUAT_PC_NAND_DEFAULT_PROG_DELAY_US, LUAT_PC_NAND_DEFAULT_ERASE_DELAY_US, LUAT_PC_NAND_DEFAULT_BAD_RATIO
};

static const pc_vnand_profile_defaults_t g_pc_vnand_profile_realistic = {
    "realistic", 200u, 3000u, 12000u, 0.0001
};

win32spi_t win32spis[LUAT_WIN32_SPI_COUNT] = {0};
static pc_vnand_t g_vnands[LUAT_WIN32_SPI_COUNT] = {0};

static uint32_t pc_vnand_rand32(pc_vnand_t* sim) {
    uint32_t x = sim->rand_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    sim->rand_state = x ? x : 1;
    return sim->rand_state;
}

static uint32_t pc_getenv_u32(const char* key, uint32_t fallback, uint32_t minv, uint32_t maxv) {
    const char* v = getenv(key);
    if (!v || !v[0]) {
        return fallback;
    }
    char* endptr = NULL;
    unsigned long long n = strtoull(v, &endptr, 0);
    if (endptr == v) {
        return fallback;
    }
    if (n < minv) n = minv;
    if (n > maxv) n = maxv;
    return (uint32_t)n;
}

static double pc_getenv_double(const char* key, double fallback, double minv, double maxv) {
    const char* v = getenv(key);
    if (!v || !v[0]) {
        return fallback;
    }
    char* endptr = NULL;
    double n = strtod(v, &endptr);
    if (endptr == v) {
        return fallback;
    }
    if (n < minv) n = minv;
    if (n > maxv) n = maxv;
    return n;
}

static const pc_vnand_profile_defaults_t* pc_vnand_select_profile(void) {
    const char* profile = getenv("LUAT_PC_NAND_PROFILE");
    if (!profile || !profile[0]) {
        return &g_pc_vnand_profile_dev;
    }
    if (_stricmp(profile, "fast") == 0) {
        return &g_pc_vnand_profile_fast;
    }
    if (_stricmp(profile, "realistic") == 0) {
        return &g_pc_vnand_profile_realistic;
    }
    if (_stricmp(profile, "dev") == 0) {
        return &g_pc_vnand_profile_dev;
    }
    LLOGW("unknown LUAT_PC_NAND_PROFILE=%s, fallback to %s", profile, LUAT_PC_NAND_PROFILE_DEFAULT);
    return &g_pc_vnand_profile_dev;
}

static int pc_vnand_is_busy(pc_vnand_t* sim) {
    return sim->busy_remaining_us > 0;
}

static void pc_vnand_step_busy_on_status_read(pc_vnand_t* sim) {
    if (sim->busy_remaining_us == 0) {
        return;
    }
    if (sim->busy_remaining_us <= 10) {
        sim->busy_remaining_us = 0;
    } else {
        sim->busy_remaining_us -= 10;
    }
}

static uint8_t pc_vnand_status3(pc_vnand_t* sim) {
    pc_vnand_step_busy_on_status_read(sim);
    uint8_t status = sim->reg3 & (NAND_SR_ERASE_FAIL | NAND_SR_PROG_FAIL | 0x30);
    if (pc_vnand_is_busy(sim)) {
        status |= NAND_SR_BUSY;
    }
    if (sim->write_enable) {
        status |= NAND_SR_WEL;
    }
    return status;
}

static void pc_vnand_reset_state(pc_vnand_t* sim) {
    sim->write_enable = 0;
    sim->cache_loaded = 0;
    sim->prog_load_active = 0;
    sim->cache_page = 0xFFFF;
    sim->reg1 = 0x00;
    sim->reg2 = 0x00;
    sim->reg3 = 0x00;
    sim->reg4 = 0x00;
    sim->busy_remaining_us = 0;
    if (sim->cache) {
        memset(sim->cache, 0xFF, sim->page_size);
    }
}

static void pc_vnand_mark_busy(pc_vnand_t* sim, uint32_t delay_us) {
    sim->busy_remaining_us = delay_us;
}

static uint8_t pc_vnand_read_reg(pc_vnand_t* sim, uint8_t addr) {
    if (addr == 0 || addr == NAND_SR3_ADDR) return pc_vnand_status3(sim);
    if (addr == NAND_SR1_ADDR) return sim->reg1;
    if (addr == NAND_SR2_ADDR) return sim->reg2;
    if (addr == NAND_SR4_ADDR) return sim->reg4;
    return 0x00;
}

static void pc_vnand_write_reg(pc_vnand_t* sim, uint8_t addr, uint8_t val) {
    if (addr == 0 || addr == NAND_SR1_ADDR) {
        sim->reg1 = val;
        return;
    }
    if (addr == NAND_SR2_ADDR) {
        sim->reg2 = val;
        return;
    }
    if (addr == NAND_SR3_ADDR) {
        sim->reg3 = (sim->reg3 & ~(NAND_SR_ERASE_FAIL | NAND_SR_PROG_FAIL | 0x30)) | (val & (NAND_SR_ERASE_FAIL | NAND_SR_PROG_FAIL | 0x30));
        return;
    }
    if (addr == NAND_SR4_ADDR) {
        sim->reg4 = val;
    }
}

static int pc_vnand_is_bad_block(pc_vnand_t* sim, uint32_t page_addr) {
    uint32_t block = page_addr / sim->pages_per_block;
    if (block >= sim->total_blocks) {
        return 1;
    }
    return sim->bad_blocks[block] ? 1 : 0;
}

static void pc_vnand_load_page_to_cache(pc_vnand_t* sim, uint32_t page_addr) {
    if (page_addr >= sim->total_pages) {
        memset(sim->cache, 0xFF, sim->page_size);
        sim->cache_loaded = 0;
        sim->cache_page = 0xFFFF;
        pc_vnand_mark_busy(sim, sim->read_delay_us);
        return;
    }
    uint32_t offset = page_addr * sim->page_size;
    memcpy(sim->cache, sim->storage + offset, sim->page_size);
    sim->cache_loaded = 1;
    sim->cache_page = (uint16_t)page_addr;
    pc_vnand_mark_busy(sim, sim->read_delay_us);
}

static void pc_vnand_program_execute(pc_vnand_t* sim, uint32_t page_addr) {
    int fail = 0;
    if (!sim->write_enable || page_addr >= sim->total_pages || pc_vnand_is_bad_block(sim, page_addr)) {
        fail = 1;
    } else {
        uint32_t offset = page_addr * sim->page_size;
        for (uint32_t i = 0; i < sim->page_size; i++) {
            sim->storage[offset + i] &= sim->cache[i];
        }
    }
    sim->write_enable = 0;
    sim->prog_load_active = 0;
    memset(sim->cache, 0xFF, sim->page_size);
    if (fail) {
        sim->reg3 |= NAND_SR_PROG_FAIL;
    } else {
        sim->reg3 &= (uint8_t)(~NAND_SR_PROG_FAIL);
    }
    pc_vnand_mark_busy(sim, sim->prog_delay_us);
}

static void pc_vnand_block_erase(pc_vnand_t* sim, uint32_t page_addr) {
    int fail = 0;
    if (!sim->write_enable || page_addr >= sim->total_pages || pc_vnand_is_bad_block(sim, page_addr)) {
        fail = 1;
    } else {
        uint32_t block = page_addr / sim->pages_per_block;
        uint32_t start_page = block * sim->pages_per_block;
        uint32_t offset = start_page * sim->page_size;
        memset(sim->storage + offset, 0xFF, sim->block_size);
    }
    sim->write_enable = 0;
    if (fail) {
        sim->reg3 |= NAND_SR_ERASE_FAIL;
    } else {
        sim->reg3 &= (uint8_t)(~NAND_SR_ERASE_FAIL);
    }
    pc_vnand_mark_busy(sim, sim->erase_delay_us);
}

static void pc_vnand_program_load(pc_vnand_t* sim, const uint8_t* send_buf, size_t send_length) {
    if (send_length < 3) {
        return;
    }
    uint32_t column = ((uint32_t)send_buf[1] << 8) | send_buf[2];
    size_t payload = send_length - 3;
    if (!sim->prog_load_active) {
        memset(sim->cache, 0xFF, sim->page_size);
        sim->prog_load_active = 1;
    }
    if (column >= sim->page_size) {
        return;
    }
    if (payload > (size_t)(sim->page_size - column)) {
        payload = sim->page_size - column;
    }
    memcpy(sim->cache + column, send_buf + 3, payload);
}

static int pc_vnand_transfer(pc_vnand_t* sim, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    if (recv_buf && recv_length) {
        memset(recv_buf, 0xFF, recv_length);
    }
    if (!sim || !sim->enabled || !send_buf || send_length == 0) {
        return (int)recv_length;
    }
    const uint8_t* tx = (const uint8_t*)send_buf;
    uint8_t* rx = (uint8_t*)recv_buf;
    uint8_t cmd = tx[0];
    switch (cmd) {
        case NAND_CMD_READ_JEDEC_ID:
            if (rx && recv_length) {
                for (size_t i = 0; i < recv_length; i++) {
                    rx[i] = i < sizeof(sim->jedec) ? sim->jedec[i] : 0xFF;
                }
            }
            return (int)recv_length;
        case NAND_CMD_READ_STATUS:
        case NAND_CMD_READ_STATUS_LEGACY: {
            uint8_t addr = send_length >= 2 ? tx[1] : 0;
            if (rx && recv_length) {
                rx[0] = pc_vnand_read_reg(sim, addr);
            }
            return (int)recv_length;
        }
        case NAND_CMD_WRITE_STATUS:
        case NAND_CMD_WRITE_STATUS_LEGACY:
            if (send_length >= 3) {
                pc_vnand_write_reg(sim, tx[1], tx[2]);
            } else if (send_length >= 2) {
                pc_vnand_write_reg(sim, 0, tx[1]);
            }
            return (int)send_length;
        case NAND_CMD_WRITE_ENABLE:
            sim->write_enable = 1;
            return (int)send_length;
        case NAND_CMD_WRITE_DISABLE:
            sim->write_enable = 0;
            return (int)send_length;
        case NAND_CMD_RESET:
            pc_vnand_reset_state(sim);
            return (int)send_length;
        case NAND_CMD_PAGE_DATA_READ:
            if (send_length >= 4) {
                uint32_t page_addr = ((uint32_t)tx[1] << 16) | ((uint32_t)tx[2] << 8) | tx[3];
                pc_vnand_load_page_to_cache(sim, page_addr);
            }
            return (int)send_length;
        case NAND_CMD_READ_DATA:
            if (send_length >= 4 && rx && recv_length) {
                uint32_t column = ((uint32_t)tx[1] << 8) | tx[2];
                if (column >= sim->page_size || !sim->cache_loaded) {
                    memset(rx, 0xFF, recv_length);
                } else {
                    size_t copy = recv_length;
                    if (copy > (size_t)(sim->page_size - column)) {
                        copy = sim->page_size - column;
                    }
                    memcpy(rx, sim->cache + column, copy);
                    if (copy < recv_length) {
                        memset(rx + copy, 0xFF, recv_length - copy);
                    }
                }
            }
            return (int)recv_length;
        case NAND_CMD_PAGE_PROG_DATA:
            pc_vnand_program_load(sim, tx, send_length);
            return (int)send_length;
        case NAND_CMD_PAGE_PROG_EXEC:
            if (send_length >= 4) {
                uint32_t page_addr = ((uint32_t)tx[1] << 16) | ((uint32_t)tx[2] << 8) | tx[3];
                pc_vnand_program_execute(sim, page_addr);
            }
            return (int)send_length;
        case NAND_CMD_BLOCK_ERASE:
            if (send_length >= 4) {
                uint32_t page_addr = ((uint32_t)tx[1] << 16) | ((uint32_t)tx[2] << 8) | tx[3];
                pc_vnand_block_erase(sim, page_addr);
            }
            return (int)send_length;
        default:
            break;
    }
    return recv_length ? (int)recv_length : (int)send_length;
}

static void pc_vnand_init_if_needed(int spi_id) {
    if (spi_id < 0 || spi_id >= LUAT_WIN32_SPI_COUNT) {
        return;
    }
    pc_vnand_t* sim = &g_vnands[spi_id];
    if (sim->initialized) {
        return;
    }
    sim->initialized = 1;
    uint32_t legacy_enable = pc_getenv_u32("LUAT_VNAND_ENABLE", 1, 0, 1);
    const char* sim_enable_env = getenv("LUAT_PC_NAND_SIM_ENABLE");
    if (sim_enable_env && sim_enable_env[0]) {
        // explicit per-simulator switch is a stronger override
        sim->enabled = pc_getenv_u32("LUAT_PC_NAND_SIM_ENABLE", legacy_enable, 0, 1);
    } else {
        sim->enabled = legacy_enable;
        const char* lf_nand_mode = getenv("LF_NAND_TEST_MODE");
        if (lf_nand_mode && lf_nand_mode[0] && _stricmp(lf_nand_mode, "RED") == 0) {
            sim->enabled = 0;
            LLOGI("virtual nand disabled by LF_NAND_TEST_MODE=RED");
        }
    }
    if (!sim->enabled) {
        return;
    }

    uint32_t page_size = pc_getenv_u32("LUAT_PC_NAND_PAGE_SIZE", LUAT_PC_NAND_DEFAULT_PAGE_SIZE, 256, 16384);
    uint32_t pages_per_block = pc_getenv_u32("LUAT_PC_NAND_PAGES_PER_BLOCK", LUAT_PC_NAND_DEFAULT_PAGES_PER_BLK, 4, 512);
    uint32_t total_size = pc_getenv_u32("LUAT_PC_NAND_TOTAL_SIZE", LUAT_PC_NAND_DEFAULT_TOTAL_SIZE, page_size * pages_per_block, 512u * 1024u * 1024u);
    uint32_t total_pages = total_size / page_size;
    total_pages -= total_pages % pages_per_block;
    if (total_pages == 0) {
        total_pages = LUAT_PC_NAND_DEFAULT_TOTAL_SIZE / LUAT_PC_NAND_DEFAULT_PAGE_SIZE;
        page_size = LUAT_PC_NAND_DEFAULT_PAGE_SIZE;
        pages_per_block = LUAT_PC_NAND_DEFAULT_PAGES_PER_BLK;
    }
    total_size = total_pages * page_size;
    uint32_t total_blocks = total_pages / pages_per_block;

    const pc_vnand_profile_defaults_t* profile = pc_vnand_select_profile();

    sim->total_size = total_size;
    sim->page_size = page_size;
    sim->pages_per_block = pages_per_block;
    sim->total_pages = total_pages;
    sim->total_blocks = total_blocks;
    sim->block_size = page_size * pages_per_block;
    sim->read_delay_us = pc_getenv_u32("LUAT_PC_NAND_READ_DELAY_US", profile->read_delay_us, 0, 5000000);
    sim->prog_delay_us = pc_getenv_u32("LUAT_PC_NAND_PROG_DELAY_US", profile->prog_delay_us, 0, 5000000);
    sim->erase_delay_us = pc_getenv_u32("LUAT_PC_NAND_ERASE_DELAY_US", profile->erase_delay_us, 0, 60000000);
    sim->rand_state = pc_getenv_u32("LUAT_PC_NAND_SEED", LUAT_PC_NAND_DEFAULT_SEED, 1, 0xFFFFFFFFu);
    sim->jedec[0] = 0x00;
    sim->jedec[1] = (uint8_t)pc_getenv_u32("LUAT_PC_NAND_JEDEC_MFR", 0xEF, 0, 0xFF);
    uint16_t jedec_dev = (uint16_t)pc_getenv_u32("LUAT_PC_NAND_JEDEC_DEV", 0xAA21, 0, 0xFFFF);
    sim->jedec[2] = (uint8_t)(jedec_dev >> 8);
    sim->jedec[3] = (uint8_t)(jedec_dev & 0xFF);

    sim->storage = malloc(sim->total_size);
    sim->cache = malloc(sim->page_size);
    sim->bad_blocks = malloc(sim->total_blocks);
    if (!sim->storage || !sim->cache || !sim->bad_blocks) {
        LLOGW("virtual nand allocation failed, disable backend");
        if (sim->storage) free(sim->storage);
        if (sim->cache) free(sim->cache);
        if (sim->bad_blocks) free(sim->bad_blocks);
        memset(sim, 0, sizeof(*sim));
        sim->initialized = 1;
        sim->enabled = 0;
        return;
    }
    memset(sim->storage, 0xFF, sim->total_size);
    memset(sim->cache, 0xFF, sim->page_size);
    memset(sim->bad_blocks, 0, sim->total_blocks);

    double bad_ratio = pc_getenv_double("LUAT_PC_NAND_BAD_BLOCK_RATIO", profile->bad_ratio, 0.0, 1.0);
    uint32_t threshold = (uint32_t)(bad_ratio * 1000000.0);
    for (uint32_t i = 0; i < sim->total_blocks; i++) {
        uint32_t r = pc_vnand_rand32(sim) % 1000000u;
        sim->bad_blocks[i] = (r < threshold) ? 1 : 0;
    }
    if (sim->total_blocks) {
        sim->bad_blocks[0] = 0;
    }
    pc_vnand_reset_state(sim);
    LLOGI("virtual nand enabled profile=%s size=%u page=%u block_pages=%u read_us=%u prog_us=%u erase_us=%u bad_ratio=%.4f seed=%u jedec=%02X %02X %02X %02X",
          profile->name, sim->total_size, sim->page_size, sim->pages_per_block,
          sim->read_delay_us, sim->prog_delay_us, sim->erase_delay_us, bad_ratio, sim->rand_state,
          sim->jedec[0], sim->jedec[1], sim->jedec[2], sim->jedec[3]);
}

int luat_spi_device_config(luat_spi_device_t* spi_dev){
    return 0;
}

int luat_spi_bus_setup(luat_spi_device_t* spi_dev){
    int bus_id = spi_dev->bus_id;
    if (bus_id < 0 || bus_id >= LUAT_WIN32_SPI_COUNT) {
        return -1;
    }
    memcpy(&win32spis[bus_id].spi, &(spi_dev->spi_config), sizeof(luat_spi_t));
    win32spis[bus_id].open = 1;
    luat_spi_setup(&spi_dev->spi_config);
    return 0;
}

int luat_spi_setup(luat_spi_t* spi) {
    if (spi->id < 0 || spi->id >= LUAT_WIN32_SPI_COUNT) {
        return -1;
    }
    #ifdef LUAT_USE_WINDOWS
    if(!g_ch3470_DevIsOpened)
        luat_load_ch347(0);
    if(g_ch3470_DevIsOpened) {
        if(luat_ch347_spi_setup(spi->id, spi->CPHA, spi->CPOL, spi->dataw, spi->bit_dict, spi->bandrate, spi->cs, spi->mode)) {
            LLOGD("spi set up success");
        } else {
            LLOGD("spi set up failed");
            return 0;
        }
    }
    #endif
    memcpy(&win32spis[spi->id].spi, spi, sizeof(luat_spi_t));
    win32spis[spi->id].open = 1;
    pc_vnand_init_if_needed(spi->id);
    return 0;
}
//关闭SPI，成功返回0
int luat_spi_close(int spi_id) {
    if (spi_id < 0 || spi_id >= LUAT_WIN32_SPI_COUNT) {
        return -1;
    }
    win32spis[spi_id].open = 0;
    return 0;
}
//收发SPI数据，返回接收字节数
int luat_spi_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    if (spi_id < 0 || spi_id >= LUAT_WIN32_SPI_COUNT) {
        return -1;
    }
    if (win32spis[spi_id].open == 0)
        return -1;
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened) {
        return luat_ch347_spi_transfer(spi_id, send_buf, send_length, recv_buf, recv_length);
    }
    #endif
    pc_vnand_init_if_needed(spi_id);
    if (g_vnands[spi_id].enabled) {
        return pc_vnand_transfer(&g_vnands[spi_id], send_buf, send_length, recv_buf, recv_length);
    }
    if (recv_buf && recv_length) memset(recv_buf, 0, recv_length);
    return recv_length;
}
//收SPI数据，返回接收字节数
int luat_spi_recv(int spi_id, char* recv_buf, size_t length) {
    if (spi_id < 0 || spi_id >= LUAT_WIN32_SPI_COUNT) {
        return -1;
    }
    if (win32spis[spi_id].open == 0) {
        return -1;
    }
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened) {
        return luat_ch347_spi_recv(spi_id, recv_buf, length);
    }
    #endif
    pc_vnand_init_if_needed(spi_id);
    if (g_vnands[spi_id].enabled) {
        if (recv_buf && length) memset(recv_buf, 0xFF, length);
        return length;
    }
    if (recv_buf && length) memset(recv_buf, 0, length);
    return length;
}
//发SPI数据，返回发送字节数
int luat_spi_send(int spi_id, const char* send_buf, size_t length) {
    if (spi_id < 0 || spi_id >= LUAT_WIN32_SPI_COUNT) {
        return -1;
    }
    if (win32spis[spi_id].open == 0)
        return -1;
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened) {
        return luat_ch347_spi_transfer(spi_id, send_buf, length, NULL, 0);
    }
    #endif
    pc_vnand_init_if_needed(spi_id);
    if (g_vnands[spi_id].enabled) {
        return pc_vnand_transfer(&g_vnands[spi_id], send_buf, length, NULL, 0);
    }
    return length;
}

int luat_spi_change_speed(int spi_id, uint32_t speed){
    return 0;
}

#ifdef LUAT_USE_LCD
#include "luat_lcd.h"

int luat_lcd_qspi_config(luat_lcd_conf_t* conf, luat_lcd_qspi_conf_t *qspi_config) {
    return -1;
};

int luat_lcd_qspi_auto_flush_on_off(luat_lcd_conf_t* conf, uint8_t on_off) {
    return -1;
}
int luat_lcd_run_api_in_service(luat_lcd_api api, void *param, uint32_t param_len) {
    return -1;
};


#endif

int luat_spi_lock(int spi_id)
{
    return -1;
}

int luat_spi_unlock(int spi_id)
{
	return -1;
}

#ifdef LUAT_USE_LCD
#include "luat_lcd.h"
uint8_t luat_lcd_qspi_is_no_ram(luat_lcd_conf_t* conf) {
    return 0;
}
#endif
