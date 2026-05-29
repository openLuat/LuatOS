
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_spi.h"
#ifdef LUAT_USE_WINDOWS
#include "luat_ch347_pc.h"
#include <windows.h>
#endif
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <direct.h>
#include <unistd.h>

// 模拟SPI在win32下的实现
// TODO 当需要返回数据时, 调用lua方法获取需要返回的数据

#define LUAT_LOG_TAG "luat.spi"
#include "luat_log.h"

#define LUAT_WIN32_SPI_LEGACY_COUNT (3)
#define LUAT_WIN32_SPI_COUNT (32)
#define LUAT_PC_VBUS_ID (20)
#define LUAT_PC_VBUS_CS_NAND (21)
#define LUAT_PC_VBUS_CS_NOR (22)
#define LUAT_PC_VBUS_CS_SD (23)
#define LUAT_PC_NAND_DEFAULT_TOTAL_SIZE    (128u * 1024u * 1024u)
#define LUAT_PC_NAND_DEFAULT_PAGE_SIZE     (2048u)
#define LUAT_PC_NAND_DEFAULT_PAGES_PER_BLK (64u)
#define LUAT_PC_NAND_DEFAULT_READ_DELAY_US (50u)
#define LUAT_PC_NAND_DEFAULT_PROG_DELAY_US (700u)
#define LUAT_PC_NAND_DEFAULT_ERASE_DELAY_US (2000u)
#define LUAT_PC_NAND_DEFAULT_BAD_RATIO     (0.001)
#define LUAT_PC_NAND_DEFAULT_SEED          (0x13572468u)
#define LUAT_PC_NAND_PROFILE_DEFAULT       "dev"
// NOR flash speed defaults: read ~2us/byte, program ~100us/byte, erase ~100ms/sector
#define LUAT_PC_NOR_DEFAULT_READ_DELAY_US_PER_BYTE   (2u)
#define LUAT_PC_NOR_DEFAULT_PROG_DELAY_US_PER_BYTE   (100u)
#define LUAT_PC_NOR_DEFAULT_ERASE_DELAY_US_PER_4K    (100000u)
// SD/TF card speed defaults: read/write ~50us/block (512B block)
#define LUAT_PC_SD_DEFAULT_READ_DELAY_US_PER_BLOCK   (50u)
#define LUAT_PC_SD_DEFAULT_WRITE_DELAY_US_PER_BLOCK  (50u)
#define LUAT_PC_SD_DEFAULT_ERASE_DELAY_US            (10000u)
#define LUAT_PC_SD_TOTAL_SIZE              (64u * 1024u * 1024u)
#define LUAT_PC_SD_BLOCK_SIZE              (512u)
#define LUAT_PC_SD_IMAGE_PATH              "spidrv\\tf.bin"

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

typedef enum pc_spi_backend {
    PC_SPI_BACKEND_NONE = 0,
    PC_SPI_BACKEND_NAND = 1,
    PC_SPI_BACKEND_NOR = 2,
    PC_SPI_BACKEND_SD = 3,
} pc_spi_backend_t;

typedef struct pc_spi_route {
    uint8_t active_cs;
} pc_spi_route_t;

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
    double speed_factor;
} pc_vnand_t;

typedef struct pc_vnand_profile_defaults {
    const char* name;
    uint32_t read_delay_us;
    uint32_t prog_delay_us;
    uint32_t erase_delay_us;
    double bad_ratio;
} pc_vnand_profile_defaults_t;

typedef struct pc_vnor_speed_profile {
    uint32_t read_delay_us_per_byte;
    uint32_t prog_delay_us_per_byte;
    uint32_t erase_delay_us_per_4k;
} pc_vnor_speed_profile_t;

typedef struct pc_vnor {
    uint8_t initialized;
    uint8_t enabled;
    uint8_t jedec[3];
    double speed_factor;
    pc_vnor_speed_profile_t speed_profile;
} pc_vnor_t;

typedef struct pc_vsd_speed_profile {
    uint32_t read_delay_us_per_block;
    uint32_t write_delay_us_per_block;
    uint32_t erase_delay_us;
} pc_vsd_speed_profile_t;

typedef struct pc_vsd {
    uint8_t initialized;
    uint8_t enabled;
    uint8_t idle;
    uint8_t app_cmd;
    uint8_t high_capacity;
    uint8_t pending_data;
    uint8_t read_mult;
    uint8_t write_mult;
    uint8_t write_collecting;
    uint8_t write_accept_pending;
    uint16_t write_collect_pos;
    uint16_t busy_bytes;
    uint8_t cmd_buf[6];
    uint8_t cmd_len;
    uint16_t defer_bytes;
    uint8_t write_buf[LUAT_PC_SD_BLOCK_SIZE + 2];
    uint8_t csd_data[16];
    uint8_t resp_buf[2048];
    uint16_t resp_pos;
    uint16_t resp_len;
    uint32_t sector_count;
    uint32_t rw_lba;
    FILE* fp;
    char image_path[64];
    double speed_factor;
    pc_vsd_speed_profile_t speed_profile;
} pc_vsd_t;

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
static pc_vnor_t g_vnors[LUAT_WIN32_SPI_COUNT] = {0};
static pc_vsd_t g_vsds[LUAT_WIN32_SPI_COUNT] = {0};
static pc_spi_route_t g_spi_routes[LUAT_WIN32_SPI_COUNT] = {0};

static int pc_spi_bus_is_valid(int bus_id) {
    return (bus_id >= 0 && bus_id < LUAT_WIN32_SPI_COUNT);
}

static void pc_spi_route_set_active_cs(int bus_id, int cs) {
    if (!pc_spi_bus_is_valid(bus_id)) {
        return;
    }
    if (cs < 0 || cs > 255) {
        g_spi_routes[bus_id].active_cs = 0xFF;
        return;
    }
    g_spi_routes[bus_id].active_cs = (uint8_t)cs;
}

static uint8_t pc_spi_route_get_active_cs(int bus_id) {
    if (!pc_spi_bus_is_valid(bus_id)) {
        return 0xFF;
    }
    return g_spi_routes[bus_id].active_cs;
}

static pc_spi_backend_t pc_spi_route_backend(int bus_id, uint8_t cs) {
    if (bus_id == LUAT_PC_VBUS_ID) {
        if (cs == LUAT_PC_VBUS_CS_NAND) return PC_SPI_BACKEND_NAND;
        if (cs == LUAT_PC_VBUS_CS_NOR) return PC_SPI_BACKEND_NOR;
        if (cs == LUAT_PC_VBUS_CS_SD) return PC_SPI_BACKEND_SD;
        return PC_SPI_BACKEND_NONE;
    }
    if (bus_id >= 0 && bus_id < LUAT_WIN32_SPI_LEGACY_COUNT) {
        return PC_SPI_BACKEND_NAND;
    }
    return PC_SPI_BACKEND_NONE;
}

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

// Speed simulation helpers
// Get global speed factor (default 1.0, min 0.0, max 100.0)
static double pc_spi_get_global_speed_factor(void) {
    return pc_getenv_double("LUAT_SPI_SPEED_FACTOR", 1.0, 0.0, 100.0);
}

// Check if speed delays should be disabled
static int pc_spi_delays_disabled(void) {
    return pc_getenv_u32("LUAT_SPI_DISABLE_DELAYS", 0, 0, 1);
}

// Apply delay in microseconds
static void pc_spi_apply_delay_us(uint32_t delay_us) {
    if (delay_us == 0 || pc_spi_delays_disabled()) {
        return;
    }
    // Convert microseconds to milliseconds, using usleep for subsecond precision
    // usleep takes microseconds on POSIX, Sleep takes milliseconds on Windows
    #ifdef _WIN32
    if (delay_us >= 1000) {
        Sleep(delay_us / 1000);
    } else if (delay_us > 0) {
        // For sub-millisecond delays on Windows, we use a busy-wait approach
        // Sleep minimum is 1ms, so we'll just use usleep-equivalent
        #ifdef __MINGW32__
        usleep(delay_us);
        #else
        // MSVC doesn't have usleep, approximate with Sleep(1) for very small delays
        if (delay_us < 1000) {
            // Sleep(1) is ~1000 microseconds, not ideal but acceptable for simulation
            Sleep(1);
        }
        #endif
    }
    #else
    usleep(delay_us);
    #endif
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
    if (recv_buf && recv_length && recv_buf != send_buf) {
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
                // Apply read delay (per-byte)
                pc_spi_apply_delay_us((uint32_t)(sim->read_delay_us / sim->page_size * recv_length));
            }
            return (int)recv_length;
        case NAND_CMD_PAGE_PROG_DATA:
            pc_vnand_program_load(sim, tx, send_length);
            return (int)send_length;
        case NAND_CMD_PAGE_PROG_EXEC:
            if (send_length >= 4) {
                uint32_t page_addr = ((uint32_t)tx[1] << 16) | ((uint32_t)tx[2] << 8) | tx[3];
                pc_vnand_program_execute(sim, page_addr);
                // Apply program delay
                pc_spi_apply_delay_us(sim->prog_delay_us);
            }
            return (int)send_length;
        case NAND_CMD_BLOCK_ERASE:
            if (send_length >= 4) {
                uint32_t page_addr = ((uint32_t)tx[1] << 16) | ((uint32_t)tx[2] << 8) | tx[3];
                pc_vnand_block_erase(sim, page_addr);
                // Apply erase delay
                pc_spi_apply_delay_us(sim->erase_delay_us);
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
    
    // Apply speed factors (per-device and global)
    double global_speed_factor = pc_spi_get_global_speed_factor();
    sim->speed_factor = pc_getenv_double("LUAT_NAND_SPEED_FACTOR", 1.0, 0.0, 100.0);
    sim->speed_factor *= global_speed_factor;
    
    // Apply speed factor to delays
    sim->read_delay_us = (uint32_t)(sim->read_delay_us * sim->speed_factor);
    sim->prog_delay_us = (uint32_t)(sim->prog_delay_us * sim->speed_factor);
    sim->erase_delay_us = (uint32_t)(sim->erase_delay_us * sim->speed_factor);

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
    LLOGI("virtual nand enabled profile=%s size=%u page=%u block_pages=%u read_us=%u prog_us=%u erase_us=%u bad_ratio=%.4f speed_factor=%.2f seed=%u jedec=%02X %02X %02X %02X",
          profile->name, sim->total_size, sim->page_size, sim->pages_per_block,
          sim->read_delay_us, sim->prog_delay_us, sim->erase_delay_us, bad_ratio, sim->speed_factor, sim->rand_state,
          sim->jedec[0], sim->jedec[1], sim->jedec[2], sim->jedec[3]);
}

static void pc_vnor_init_if_needed(int spi_id) {
    if (!pc_spi_bus_is_valid(spi_id)) {
        return;
    }
    pc_vnor_t* sim = &g_vnors[spi_id];
    if (sim->initialized) {
        return;
    }
    sim->initialized = 1;
    sim->enabled = 1;
    sim->jedec[0] = 0xEF;
    sim->jedec[1] = 0x40;
    sim->jedec[2] = 0x18;
    
    // Initialize NOR speed profile
    sim->speed_profile.read_delay_us_per_byte = LUAT_PC_NOR_DEFAULT_READ_DELAY_US_PER_BYTE;
    sim->speed_profile.prog_delay_us_per_byte = LUAT_PC_NOR_DEFAULT_PROG_DELAY_US_PER_BYTE;
    sim->speed_profile.erase_delay_us_per_4k = LUAT_PC_NOR_DEFAULT_ERASE_DELAY_US_PER_4K;
    
    // Apply speed factors
    double global_speed_factor = pc_spi_get_global_speed_factor();
    sim->speed_factor = pc_getenv_double("LUAT_NOR_SPEED_FACTOR", 1.0, 0.0, 100.0);
    sim->speed_factor *= global_speed_factor;
    
    // Apply per-operation overrides if specified
    sim->speed_profile.read_delay_us_per_byte = pc_getenv_u32("LUAT_NOR_READ_US_PER_BYTE", 
        (uint32_t)(LUAT_PC_NOR_DEFAULT_READ_DELAY_US_PER_BYTE * sim->speed_factor), 0, 100000);
    sim->speed_profile.prog_delay_us_per_byte = pc_getenv_u32("LUAT_NOR_PROG_US_PER_BYTE", 
        (uint32_t)(LUAT_PC_NOR_DEFAULT_PROG_DELAY_US_PER_BYTE * sim->speed_factor), 0, 100000);
    sim->speed_profile.erase_delay_us_per_4k = pc_getenv_u32("LUAT_NOR_ERASE_US_PER_4K", 
        (uint32_t)(LUAT_PC_NOR_DEFAULT_ERASE_DELAY_US_PER_4K * sim->speed_factor), 0, 10000000);
    
    LLOGI("virtual nor enabled jedec=%02X %02X %02X speed_factor=%.2f read_us/byte=%u prog_us/byte=%u erase_us/4k=%u",
          sim->jedec[0], sim->jedec[1], sim->jedec[2], sim->speed_factor,
          sim->speed_profile.read_delay_us_per_byte, sim->speed_profile.prog_delay_us_per_byte,
          sim->speed_profile.erase_delay_us_per_4k);
}

static uint16_t pc_sd_crc16_ccitt(const uint8_t* data, size_t len) {
    uint16_t crc = 0;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int b = 0; b < 8; b++) {
            if (crc & 0x8000) {
                crc = (uint16_t)((crc << 1) ^ 0x1021);
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}

static void pc_vsd_resp_clear(pc_vsd_t* sim) {
    sim->resp_pos = 0;
    sim->resp_len = 0;
}

static void pc_vsd_resp_push_byte(pc_vsd_t* sim, uint8_t v) {
    if (sim->resp_len < (uint16_t)sizeof(sim->resp_buf)) {
        sim->resp_buf[sim->resp_len++] = v;
    }
}

static void pc_vsd_resp_push_data(pc_vsd_t* sim, const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        pc_vsd_resp_push_byte(sim, data[i]);
    }
}

static int pc_vsd_open_or_create(pc_vsd_t* sim, int create_if_missing) {
    if (sim->fp) {
        return 0;
    }
    sim->fp = fopen(sim->image_path, "rb+");
    if (!sim->fp && create_if_missing) {
        _mkdir("spidrv");
        sim->fp = fopen(sim->image_path, "wb+");
        if (!sim->fp) {
            return -1;
        }
        static uint8_t ff_buf[4096];
        memset(ff_buf, 0xFF, sizeof(ff_buf));
        uint32_t remaining = LUAT_PC_SD_TOTAL_SIZE;
        while (remaining > 0) {
            uint32_t now = remaining > sizeof(ff_buf) ? (uint32_t)sizeof(ff_buf) : remaining;
            if (fwrite(ff_buf, 1, now, sim->fp) != now) {
                fclose(sim->fp);
                sim->fp = NULL;
                return -1;
            }
            remaining -= now;
        }
        fflush(sim->fp);
    }
    return sim->fp ? 0 : -1;
}

static int pc_vsd_read_sector(pc_vsd_t* sim, uint32_t lba, uint8_t* out512) {
    if (lba >= sim->sector_count || pc_vsd_open_or_create(sim, 1)) {
        memset(out512, 0xFF, LUAT_PC_SD_BLOCK_SIZE);
        return -1;
    }
    if (fseek(sim->fp, (long)(lba * LUAT_PC_SD_BLOCK_SIZE), SEEK_SET)) {
        memset(out512, 0xFF, LUAT_PC_SD_BLOCK_SIZE);
        return -1;
    }
    size_t n = fread(out512, 1, LUAT_PC_SD_BLOCK_SIZE, sim->fp);
    if (n != LUAT_PC_SD_BLOCK_SIZE) {
        memset(out512 + n, 0xFF, LUAT_PC_SD_BLOCK_SIZE - n);
        return -1;
    }
    // Apply read delay for SD
    pc_spi_apply_delay_us(sim->speed_profile.read_delay_us_per_block);
    return 0;
}

static int pc_vsd_write_sector(pc_vsd_t* sim, uint32_t lba, const uint8_t* in512) {
    if (lba >= sim->sector_count || pc_vsd_open_or_create(sim, 1)) {
        return -1;
    }
    if (fseek(sim->fp, (long)(lba * LUAT_PC_SD_BLOCK_SIZE), SEEK_SET)) {
        return -1;
    }
    if (fwrite(in512, 1, LUAT_PC_SD_BLOCK_SIZE, sim->fp) != LUAT_PC_SD_BLOCK_SIZE) {
        return -1;
    }
    fflush(sim->fp);
    // Apply write delay for SD
    pc_spi_apply_delay_us(sim->speed_profile.write_delay_us_per_block);
    return 0;
}

static void pc_vsd_queue_data_block(pc_vsd_t* sim, uint32_t lba) {
    uint8_t blk[LUAT_PC_SD_BLOCK_SIZE];
    pc_vsd_read_sector(sim, lba, blk);
    uint16_t crc = pc_sd_crc16_ccitt(blk, sizeof(blk));
    pc_vsd_resp_push_byte(sim, 0xFE);
    pc_vsd_resp_push_data(sim, blk, sizeof(blk));
    pc_vsd_resp_push_byte(sim, (uint8_t)(crc >> 8));
    pc_vsd_resp_push_byte(sim, (uint8_t)(crc & 0xFF));
}

static void pc_vsd_handle_cmd(pc_vsd_t* sim) {
    uint8_t cmd = sim->cmd_buf[0] & 0x3F;
    uint32_t arg = ((uint32_t)sim->cmd_buf[1] << 24) | ((uint32_t)sim->cmd_buf[2] << 16) |
                   ((uint32_t)sim->cmd_buf[3] << 8) | sim->cmd_buf[4];
    uint8_t r1 = sim->idle ? 0x01 : 0x00;
    pc_vsd_resp_push_byte(sim, 0xFF);

    if (cmd == 12) {
        sim->read_mult = 0;
        sim->write_mult = 0;
        sim->write_collecting = 0;
        sim->pending_data = 0;
        sim->defer_bytes = 0;
        pc_vsd_resp_push_byte(sim, 0x00);
        return;
    }
    if (sim->app_cmd && cmd == 41) {
        sim->app_cmd = 0;
        sim->idle = 0;
        sim->high_capacity = (arg & 0x40000000u) ? 1 : 0;
        pc_vsd_resp_push_byte(sim, 0x00);
        return;
    }
    sim->app_cmd = 0;

    switch (cmd) {
        case 0:
            sim->idle = 1;
            sim->read_mult = 0;
            sim->write_mult = 0;
            sim->write_collecting = 0;
            sim->pending_data = 0;
            sim->defer_bytes = 0;
            r1 = 0x01;
            pc_vsd_resp_push_byte(sim, r1);
            break;
        case 8:
            r1 = sim->idle ? 0x01 : 0x00;
            pc_vsd_resp_push_byte(sim, r1);
            pc_vsd_resp_push_byte(sim, 0x00);
            pc_vsd_resp_push_byte(sim, 0x00);
            pc_vsd_resp_push_byte(sim, 0x01);
            pc_vsd_resp_push_byte(sim, 0xAA);
            break;
        case 55:
            sim->app_cmd = 1;
            pc_vsd_resp_push_byte(sim, sim->idle ? 0x01 : 0x00);
            break;
        case 58:
            pc_vsd_resp_push_byte(sim, sim->idle ? 0x01 : 0x00);
            pc_vsd_resp_push_byte(sim, (uint8_t)((sim->high_capacity ? 0x40u : 0x00u) | 0x00));
            pc_vsd_resp_push_byte(sim, 0xFF);
            pc_vsd_resp_push_byte(sim, 0x80);
            pc_vsd_resp_push_byte(sim, 0x00);
            break;
        case 9:
            if (sim->idle) {
                pc_vsd_resp_push_byte(sim, 0x01);
                break;
            }
            pc_vsd_resp_push_byte(sim, 0x00);
            sim->pending_data = 1;
            sim->defer_bytes = 64;
            break;
        case 16:
            pc_vsd_resp_push_byte(sim, (arg == LUAT_PC_SD_BLOCK_SIZE) ? 0x00 : 0x04);
            break;
        case 17:
            if (sim->idle) {
                pc_vsd_resp_push_byte(sim, 0x01);
                break;
            }
            sim->rw_lba = sim->high_capacity ? arg : (arg / LUAT_PC_SD_BLOCK_SIZE);
            sim->read_mult = 0;
            sim->pending_data = 2;
            sim->defer_bytes = 64;
            pc_vsd_resp_push_byte(sim, 0x00);
            break;
        case 18:
            if (sim->idle) {
                pc_vsd_resp_push_byte(sim, 0x01);
                break;
            }
            sim->rw_lba = sim->high_capacity ? arg : (arg / LUAT_PC_SD_BLOCK_SIZE);
            sim->read_mult = 1;
            sim->pending_data = 2;
            sim->defer_bytes = 64;
            pc_vsd_resp_push_byte(sim, 0x00);
            break;
        case 24:
        case 25:
            if (sim->idle) {
                pc_vsd_resp_push_byte(sim, 0x01);
                break;
            }
            sim->rw_lba = sim->high_capacity ? arg : (arg / LUAT_PC_SD_BLOCK_SIZE);
            sim->write_mult = (cmd == 25) ? 1 : 0;
            sim->write_collecting = 0;
            sim->write_collect_pos = 0;
            pc_vsd_resp_push_byte(sim, 0x00);
            break;
        default:
            pc_vsd_resp_push_byte(sim, r1);
            break;
    }
}

static int pc_vsd_transfer(pc_vsd_t* sim, int cs_pin, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    size_t length = send_length > recv_length ? send_length : recv_length;
    if (recv_buf && recv_length && recv_buf != send_buf) {
        memset(recv_buf, 0xFF, recv_length);
    }
    if (!sim || !sim->enabled || length == 0) {
        return (int)(recv_length ? recv_length : send_length);
    }
    int selected = (cs_pin >= 0 && cs_pin < 128) ? (luat_gpio_get(cs_pin) == 0) : 1;
    if (!selected) {
        sim->cmd_len = 0;
        sim->read_mult = 0;
        sim->write_mult = 0;
        sim->write_collecting = 0;
        sim->write_accept_pending = 0;
        sim->busy_bytes = 0;
        sim->defer_bytes = 0;
        sim->pending_data = 0;
        pc_vsd_resp_clear(sim);
        return (int)(recv_length ? recv_length : send_length);
    }

    uint8_t* rx = (uint8_t*)recv_buf;
    const uint8_t* tx = (const uint8_t*)send_buf;
    for (size_t i = 0; i < length; i++) {
        uint8_t out = 0xFF;
        uint8_t in = (tx && i < send_length) ? tx[i] : 0xFF;
        int command_active = (sim->cmd_len > 0) || ((in & 0xC0) == 0x40);
        if (sim->read_mult && sim->cmd_len == 0 && ((in & 0xC0) == 0x40)) {
            pc_vsd_resp_clear(sim);
            sim->pending_data = 0;
        }

        if (sim->busy_bytes) {
            out = 0x00;
            sim->busy_bytes--;
        } else if (sim->write_accept_pending) {
            out = 0x05;
            sim->write_accept_pending = 0;
            sim->busy_bytes = 4;
        } else if (sim->resp_pos < sim->resp_len) {
            out = sim->resp_buf[sim->resp_pos++];
            if (sim->resp_pos >= sim->resp_len) {
                pc_vsd_resp_clear(sim);
            }
        } else if (sim->defer_bytes && !command_active) {
            sim->defer_bytes--;
        } else if (sim->pending_data == 1 && !command_active) {
            sim->pending_data = 0;
            pc_vsd_resp_clear(sim);
            pc_vsd_resp_push_byte(sim, 0xFE);
            pc_vsd_resp_push_data(sim, sim->csd_data, sizeof(sim->csd_data));
            pc_vsd_resp_push_byte(sim, 0xFF);
            pc_vsd_resp_push_byte(sim, 0xFF);
            if (sim->resp_pos < sim->resp_len) {
                out = sim->resp_buf[sim->resp_pos++];
                if (sim->resp_pos >= sim->resp_len) pc_vsd_resp_clear(sim);
            }
        } else if ((sim->pending_data == 2 || sim->read_mult) && !command_active) {
            pc_vsd_resp_clear(sim);
            pc_vsd_queue_data_block(sim, sim->rw_lba);
            sim->rw_lba++;
            if (!sim->read_mult) {
                sim->pending_data = 0;
            }
            if (sim->resp_pos < sim->resp_len) {
                out = sim->resp_buf[sim->resp_pos++];
                if (sim->resp_pos >= sim->resp_len) pc_vsd_resp_clear(sim);
            }
        }

        if (sim->write_mult || sim->write_collecting) {
            if (!sim->write_collecting) {
                if (in == 0xFC || in == 0xFE) {
                    sim->write_collecting = 1;
                    sim->write_collect_pos = 0;
                } else if (in == 0xFD && sim->write_mult) {
                    sim->write_mult = 0;
                }
            } else {
                if (sim->write_collect_pos < sizeof(sim->write_buf)) {
                    sim->write_buf[sim->write_collect_pos++] = in;
                }
                if (sim->write_collect_pos >= sizeof(sim->write_buf)) {
                    pc_vsd_write_sector(sim, sim->rw_lba, sim->write_buf);
                    sim->rw_lba++;
                    sim->write_collecting = 0;
                    sim->write_collect_pos = 0;
                    sim->write_accept_pending = 1;
                    if (!sim->write_mult) {
                        sim->write_mult = 0;
                    }
                }
            }
        } else {
            if (sim->cmd_len == 0) {
                if ((in & 0xC0) == 0x40) {
                    sim->cmd_buf[sim->cmd_len++] = in;
                }
            } else {
                sim->cmd_buf[sim->cmd_len++] = in;
                if (sim->cmd_len >= sizeof(sim->cmd_buf)) {
                    sim->cmd_len = 0;
                    pc_vsd_handle_cmd(sim);
                }
            }
        }

        if (rx && i < recv_length) {
            rx[i] = out;
        }
    }
    return (int)(recv_length ? recv_length : send_length);
}

static void pc_vsd_init_if_needed(int spi_id) {
    if (!pc_spi_bus_is_valid(spi_id)) {
        return;
    }
    pc_vsd_t* sim = &g_vsds[spi_id];
    if (sim->initialized) {
        return;
    }
    sim->initialized = 1;
    sim->enabled = 1;
    sim->idle = 1;
    sim->high_capacity = 1;
    sim->sector_count = LUAT_PC_SD_TOTAL_SIZE / LUAT_PC_SD_BLOCK_SIZE;
    memcpy(sim->image_path, LUAT_PC_SD_IMAGE_PATH, sizeof(LUAT_PC_SD_IMAGE_PATH));
    memset(sim->csd_data, 0, sizeof(sim->csd_data));
    sim->csd_data[0] = 0x40;
    sim->csd_data[1] = 0x0E;
    sim->csd_data[2] = 0x00;
    sim->csd_data[3] = 0x32;
    sim->csd_data[4] = 0x5B;
    sim->csd_data[5] = 0x59;
    sim->csd_data[6] = 0x00;
    sim->csd_data[7] = 0x00;
    sim->csd_data[8] = 0x00;
    sim->csd_data[9] = (uint8_t)((sim->sector_count / 1024u) - 1u);
    sim->csd_data[10] = 0x7F;
    sim->csd_data[11] = 0x80;
    sim->csd_data[12] = 0x0A;
    sim->csd_data[13] = 0x40;
    sim->csd_data[14] = 0x00;
    sim->csd_data[15] = 0x01;
    
    // Initialize SD speed profile
    sim->speed_profile.read_delay_us_per_block = LUAT_PC_SD_DEFAULT_READ_DELAY_US_PER_BLOCK;
    sim->speed_profile.write_delay_us_per_block = LUAT_PC_SD_DEFAULT_WRITE_DELAY_US_PER_BLOCK;
    sim->speed_profile.erase_delay_us = LUAT_PC_SD_DEFAULT_ERASE_DELAY_US;
    
    // Apply speed factors
    double global_speed_factor = pc_spi_get_global_speed_factor();
    sim->speed_factor = pc_getenv_double("LUAT_SD_SPEED_FACTOR", 1.0, 0.0, 100.0);
    sim->speed_factor *= global_speed_factor;
    
    // Apply per-operation overrides if specified
    sim->speed_profile.read_delay_us_per_block = pc_getenv_u32("LUAT_SD_READ_US_PER_BLOCK", 
        (uint32_t)(LUAT_PC_SD_DEFAULT_READ_DELAY_US_PER_BLOCK * sim->speed_factor), 0, 100000);
    sim->speed_profile.write_delay_us_per_block = pc_getenv_u32("LUAT_SD_WRITE_US_PER_BLOCK", 
        (uint32_t)(LUAT_PC_SD_DEFAULT_WRITE_DELAY_US_PER_BLOCK * sim->speed_factor), 0, 100000);
    sim->speed_profile.erase_delay_us = pc_getenv_u32("LUAT_SD_ERASE_US", 
        (uint32_t)(LUAT_PC_SD_DEFAULT_ERASE_DELAY_US * sim->speed_factor), 0, 10000000);
    
    LLOGI("virtual sd enabled size=%u bytes image=%s speed_factor=%.2f read_us/blk=%u write_us/blk=%u erase_us=%u",
          LUAT_PC_SD_TOTAL_SIZE, sim->image_path, sim->speed_factor,
          sim->speed_profile.read_delay_us_per_block, sim->speed_profile.write_delay_us_per_block,
          sim->speed_profile.erase_delay_us);
}

static int pc_spi_backend_transfer_nand(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    pc_vnand_init_if_needed(spi_id);
    if (!g_vnands[spi_id].enabled) {
        return -1;
    }
    return pc_vnand_transfer(&g_vnands[spi_id], send_buf, send_length, recv_buf, recv_length);
}

static int pc_spi_backend_transfer_nor(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    (void)send_buf;
    pc_vnor_init_if_needed(spi_id);
    if (!g_vnors[spi_id].enabled) {
        return -1;
    }
    if (recv_buf && recv_length) {
        memset(recv_buf, 0xFF, recv_length);
        // Apply read delay for NOR
        pc_vsd_t* sd = &g_vsds[spi_id];
        uint32_t read_delay = g_vnors[spi_id].speed_profile.read_delay_us_per_byte * recv_length;
        pc_spi_apply_delay_us(read_delay);
    }
    return recv_length ? (int)recv_length : (int)send_length;
}

static int pc_spi_backend_transfer_sd(int spi_id, int cs_pin, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    pc_vsd_init_if_needed(spi_id);
    if (!g_vsds[spi_id].enabled) {
        return -1;
    }
    return pc_vsd_transfer(&g_vsds[spi_id], cs_pin, send_buf, send_length, recv_buf, recv_length);
}

static int pc_spi_backend_recv_nor(int spi_id, char* recv_buf, size_t length) {
    pc_vnor_init_if_needed(spi_id);
    if (!g_vnors[spi_id].enabled) {
        return -1;
    }
    if (recv_buf && length) {
        memset(recv_buf, 0xFF, length);
        // Apply read delay for NOR
        uint32_t read_delay = g_vnors[spi_id].speed_profile.read_delay_us_per_byte * length;
        pc_spi_apply_delay_us(read_delay);
    }
    return (int)length;
}

static int pc_spi_backend_send_nor(int spi_id, const char* send_buf, size_t length) {
    (void)send_buf;
    pc_vnor_init_if_needed(spi_id);
    if (!g_vnors[spi_id].enabled) {
        return -1;
    }
    return (int)length;
}

static int pc_spi_route_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length, uint8_t cs) {
    pc_spi_backend_t backend = pc_spi_route_backend(spi_id, cs);
    switch (backend) {
        case PC_SPI_BACKEND_NAND:
            return pc_spi_backend_transfer_nand(spi_id, send_buf, send_length, recv_buf, recv_length);
        case PC_SPI_BACKEND_NOR:
            return pc_spi_backend_transfer_nor(spi_id, send_buf, send_length, recv_buf, recv_length);
        case PC_SPI_BACKEND_SD:
            return pc_spi_backend_transfer_sd(spi_id, cs, send_buf, send_length, recv_buf, recv_length);
        default:
            break;
    }
    return -1;
}

static int pc_spi_route_recv(int spi_id, char* recv_buf, size_t length, uint8_t cs) {
    pc_spi_backend_t backend = pc_spi_route_backend(spi_id, cs);
    switch (backend) {
        case PC_SPI_BACKEND_NAND:
            if (recv_buf && length) memset(recv_buf, 0xFF, length);
            return (int)length;
        case PC_SPI_BACKEND_NOR:
            return pc_spi_backend_recv_nor(spi_id, recv_buf, length);
        case PC_SPI_BACKEND_SD:
            return pc_spi_backend_transfer_sd(spi_id, cs, NULL, 0, recv_buf, length);
        default:
            break;
    }
    return -1;
}

static int pc_spi_route_send(int spi_id, const char* send_buf, size_t length, uint8_t cs) {
    pc_spi_backend_t backend = pc_spi_route_backend(spi_id, cs);
    switch (backend) {
        case PC_SPI_BACKEND_NAND:
            return pc_spi_backend_transfer_nand(spi_id, send_buf, length, NULL, 0);
        case PC_SPI_BACKEND_NOR:
            return pc_spi_backend_send_nor(spi_id, send_buf, length);
        case PC_SPI_BACKEND_SD:
            return pc_spi_backend_transfer_sd(spi_id, cs, send_buf, length, NULL, 0);
        default:
            break;
    }
    return -1;
}

int luat_spi_device_config(luat_spi_device_t* spi_dev){
    if (!spi_dev) {
        return -1;
    }
    pc_spi_route_set_active_cs(spi_dev->bus_id, spi_dev->spi_config.cs);
    return 0;
}

int luat_spi_bus_setup(luat_spi_device_t* spi_dev){
    if (!spi_dev) {
        return -1;
    }
    int bus_id = spi_dev->bus_id;
    if (!pc_spi_bus_is_valid(bus_id)) {
        return -1;
    }
    spi_dev->spi_config.id = bus_id;
    luat_spi_t spi_cfg = spi_dev->spi_config;
    spi_cfg.id = bus_id;
    memcpy(&win32spis[bus_id].spi, &spi_cfg, sizeof(luat_spi_t));
    win32spis[bus_id].open = 1;
    pc_spi_route_set_active_cs(bus_id, spi_cfg.cs);
    luat_spi_setup(&spi_cfg);
    return 0;
}

int luat_spi_setup(luat_spi_t* spi) {
    if (!spi || !pc_spi_bus_is_valid(spi->id)) {
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
    pc_spi_route_set_active_cs(spi->id, spi->cs);
    pc_spi_backend_t backend = pc_spi_route_backend(spi->id, pc_spi_route_get_active_cs(spi->id));
    if (backend == PC_SPI_BACKEND_NAND) {
        pc_vnand_init_if_needed(spi->id);
    } else if (backend == PC_SPI_BACKEND_NOR) {
        pc_vnor_init_if_needed(spi->id);
    } else if (backend == PC_SPI_BACKEND_SD) {
        pc_vsd_init_if_needed(spi->id);
    }
    return 0;
}
//关闭SPI，成功返回0
int luat_spi_close(int spi_id) {
    if (!pc_spi_bus_is_valid(spi_id)) {
        return -1;
    }
    win32spis[spi_id].open = 0;
    pc_spi_route_set_active_cs(spi_id, -1);
    return 0;
}
//收发SPI数据，返回接收字节数
int luat_spi_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    if (!pc_spi_bus_is_valid(spi_id)) {
        return -1;
    }
    if (win32spis[spi_id].open == 0) {
        return -1;
    }
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened) {
        return luat_ch347_spi_transfer(spi_id, send_buf, send_length, recv_buf, recv_length);
    }
    #endif
    uint8_t cs = pc_spi_route_get_active_cs(spi_id);
    int routed = pc_spi_route_transfer(spi_id, send_buf, send_length, recv_buf, recv_length, cs);
    if (routed >= 0) {
        return routed;
    }
    if (recv_buf && recv_length) memset(recv_buf, 0, recv_length);
    return recv_length;
}
//收SPI数据，返回接收字节数
int luat_spi_recv(int spi_id, char* recv_buf, size_t length) {
    if (!pc_spi_bus_is_valid(spi_id)) {
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
    uint8_t cs = pc_spi_route_get_active_cs(spi_id);
    int routed = pc_spi_route_recv(spi_id, recv_buf, length, cs);
    if (routed >= 0) {
        return routed;
    }
    if (recv_buf && length) memset(recv_buf, 0, length);
    return length;
}
//发SPI数据，返回发送字节数
int luat_spi_send(int spi_id, const char* send_buf, size_t length) {
    if (!pc_spi_bus_is_valid(spi_id)) {
        return -1;
    }
    if (win32spis[spi_id].open == 0)
        return -1;
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened) {
        return luat_ch347_spi_transfer(spi_id, send_buf, length, NULL, 0);
    }
    #endif
    uint8_t cs = pc_spi_route_get_active_cs(spi_id);
    int routed = pc_spi_route_send(spi_id, send_buf, length, cs);
    if (routed >= 0) {
        return routed;
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
