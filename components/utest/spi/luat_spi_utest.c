/**
 * Soft SPI CPHA/CPOL 时序单元测试
 *
 * 通过 PC 模拟器的 GPIO 驱动钩子，实现一个虚拟 SPI 从机，
 * 验证 spi_soft_send_byte / spi_soft_recv_byte / spi_soft_xfer_byte
 * 在 CPHA=0 和 CPHA=1 下的采样时序是否正确。
 */
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_gpio_drv.h"
#include <string.h>

/* luat_gpio_pc.c 中的全局数组 */
extern luat_gpio_drv_opts_t *gpio_drvs[128];
extern uint8_t gpio_levels[128];

/* ---------- 虚拟 SPI 从机 ---------- */

#define VSLAVE_MAX_BYTES 16

typedef struct {
    int active;         /* 是否已激活 */
    int cpol;
    int cpha;
    int clk_pin;
    int mosi_pin;
    int miso_pin;
    int cs_pin;         /* -1 表示不使用 CS 检测 */

    int clk_prev;       /* 上一次 CLK 电平 */
    int cs_active;      /* CS 是否有效(低) */

    int bit_count;      /* 当前 bit 计数 */
    int byte_count;     /* 已完成字节计数 */

    uint8_t rx_data[VSLAVE_MAX_BYTES];  /* 从机接收到的数据 */
    uint8_t tx_data[VSLAVE_MAX_BYTES];  /* 从机要发送的数据 */
    int tx_len;
    uint8_t tx_shift;   /* 当前发送移位寄存器 */
    uint8_t rx_shift;   /* 当前接收移位寄存器 */
    int miso_level;     /* 当前 MISO 输出电平 */
} vslave_t;

static vslave_t g_vslave;

static void vslave_load_tx_byte(vslave_t *s) {
    if (s->byte_count < s->tx_len)
        s->tx_shift = s->tx_data[s->byte_count];
    else
        s->tx_shift = 0xFF; /* 无数据时发 0xFF */
}

/* 从机在 CPHA=0 时需要预加载第一个 bit 到 MISO */
static void vslave_preload_miso(vslave_t *s) {
    vslave_load_tx_byte(s);
    s->miso_level = (s->tx_shift & 0x80) ? 1 : 0;
}

/* 检测是否为 leading edge */
static int is_leading_edge(vslave_t *s, int old_level, int new_level) {
    if (s->cpol == 0)
        return (old_level == 0 && new_level == 1); /* rising */
    else
        return (old_level == 1 && new_level == 0); /* falling */
}

/* 检测是否为 trailing edge */
static int is_trailing_edge(vslave_t *s, int old_level, int new_level) {
    if (s->cpol == 0)
        return (old_level == 1 && new_level == 0); /* falling */
    else
        return (old_level == 0 && new_level == 1); /* rising */
}

static void vslave_on_leading_edge(vslave_t *s, int mosi_level) {
    if (s->cpha == 0) {
        /* CPHA=0: 从机在 leading edge 采样 MOSI */
        s->rx_shift = (s->rx_shift << 1) | (mosi_level ? 1 : 0);
        s->bit_count++;
    } else {
        /* CPHA=1: 从机在 leading edge 输出 MISO */
        if (s->bit_count == 0) {
            /* 每个字节的第一个 leading edge: 加载字节 */
            vslave_load_tx_byte(s);
        }
        s->miso_level = (s->tx_shift & 0x80) ? 1 : 0;
    }
}

static void vslave_on_trailing_edge(vslave_t *s, int mosi_level) {
    if (s->cpha == 0) {
        /* CPHA=0: 从机在 trailing edge 移位输出下一 bit */
        if (s->bit_count >= 8) {
            /* 一个字节接收完成 */
            if (s->byte_count < VSLAVE_MAX_BYTES)
                s->rx_data[s->byte_count] = s->rx_shift;
            s->byte_count++;
            s->bit_count = 0;
            s->rx_shift = 0;
            /* 加载下一字节并输出 MSB */
            vslave_load_tx_byte(s);
            s->miso_level = (s->tx_shift & 0x80) ? 1 : 0;
        } else {
            s->tx_shift <<= 1;
            s->miso_level = (s->tx_shift & 0x80) ? 1 : 0;
        }
    } else {
        /* CPHA=1: 从机在 trailing edge 采样 MOSI, 并移位准备下一 bit */
        s->rx_shift = (s->rx_shift << 1) | (mosi_level ? 1 : 0);
        s->bit_count++;
        if (s->bit_count >= 8) {
            if (s->byte_count < VSLAVE_MAX_BYTES)
                s->rx_data[s->byte_count] = s->rx_shift;
            s->byte_count++;
            s->bit_count = 0;
            s->rx_shift = 0;
        } else {
            /* 移位 TX, 下一个 leading edge 将输出新的 MSB */
            s->tx_shift <<= 1;
        }
    }
}

/* GPIO write 回调: 监控 CLK 和 MOSI */
static int vslave_gpio_write(void *userdata, int pin, int level) {
    vslave_t *s = &g_vslave;
    if (!s->active)
        return 0;

    if (pin == s->cs_pin && s->cs_pin >= 0) {
        if (level == 0 && !s->cs_active) {
            /* CS 拉低: 激活从机 */
            s->cs_active = 1;
            s->bit_count = 0;
            s->byte_count = 0;
            s->rx_shift = 0;
            memset(s->rx_data, 0, sizeof(s->rx_data));
            if (s->cpha == 0) {
                vslave_preload_miso(s);
            } else {
                s->miso_level = 1; /* 空闲高 */
            }
        } else if (level != 0 && s->cs_active) {
            s->cs_active = 0;
        }
        return 0;
    }

    /* 如果没有 CS 引脚,始终认为激活 */
    if (s->cs_pin < 0)
        s->cs_active = 1;

    if (!s->cs_active)
        return 0;

    if (pin == s->clk_pin) {
        int old = s->clk_prev;
        s->clk_prev = level;
        if (old == level)
            return 0; /* 无变化 */

        int mosi_level = gpio_levels[s->mosi_pin];
        if (is_leading_edge(s, old, level)) {
            vslave_on_leading_edge(s, mosi_level);
        } else if (is_trailing_edge(s, old, level)) {
            vslave_on_trailing_edge(s, mosi_level);
        }
    }
    return 0;
}

/* GPIO read 回调: 提供 MISO 电平 */
static int vslave_gpio_read(void *userdata, int pin) {
    vslave_t *s = &g_vslave;
    if (!s->active)
        return gpio_levels[pin];
    if (pin == s->miso_pin) {
        return s->miso_level;
    }
    return gpio_levels[pin];
}

static int vslave_gpio_setup(void *userdata, luat_gpio_t *gpio) {
    return 0;
}

static int vslave_gpio_close(void *userdata, int pin) {
    return 0;
}

static luat_gpio_drv_opts_t vslave_drv = {
    .setup = vslave_gpio_setup,
    .write = vslave_gpio_write,
    .read  = vslave_gpio_read,
    .close = vslave_gpio_close,
};

/* ---------- 测试辅助 ---------- */

/* 初始化虚拟从机并注册 GPIO 驱动 */
static void vslave_init(int cs, int mosi, int miso, int clk, int cpol, int cpha,
                        const uint8_t *tx, int tx_len) {
    memset(&g_vslave, 0, sizeof(g_vslave));
    g_vslave.active = 1;
    g_vslave.cpol = cpol;
    g_vslave.cpha = cpha;
    g_vslave.clk_pin = clk;
    g_vslave.mosi_pin = mosi;
    g_vslave.miso_pin = miso;
    g_vslave.cs_pin = cs;
    g_vslave.clk_prev = cpol; /* 空闲电平 = CPOL */
    g_vslave.cs_active = 0;
    g_vslave.miso_level = 1;
    if (tx && tx_len > 0) {
        memcpy(g_vslave.tx_data, tx, tx_len > VSLAVE_MAX_BYTES ? VSLAVE_MAX_BYTES : tx_len);
        g_vslave.tx_len = tx_len;
    }

    /* 注册驱动到相关引脚 */
    gpio_drvs[clk] = &vslave_drv;
    gpio_drvs[mosi] = &vslave_drv;
    gpio_drvs[miso] = &vslave_drv;
    if (cs >= 0 && cs < 128)
        gpio_drvs[cs] = &vslave_drv;
}

static void vslave_deinit(void) {
    int pins[] = {g_vslave.clk_pin, g_vslave.mosi_pin, g_vslave.miso_pin, g_vslave.cs_pin};
    for (int i = 0; i < 4; i++) {
        if (pins[i] >= 0 && pins[i] < 128)
            gpio_drvs[pins[i]] = NULL;
    }
    g_vslave.active = 0;
}

/* 通过 Lua API 执行 soft SPI transfer 并返回接收数据 */
static int run_lua_expr(lua_State *L, const char *code) {
    int top = lua_gettop(L);
    int ok = 0;
    int status = luaL_loadstring(L, code);
    if (status == LUA_OK) {
        status = lua_pcall(L, 0, 1, 0);
        if (status == LUA_OK) {
            ok = lua_toboolean(L, -1) ? 1 : 0;
        } else {
            printf("[spi_utest] lua_pcall error: %s\n", lua_tostring(L, -1));
        }
    } else {
        printf("[spi_utest] loadstring error: %s\n", lua_tostring(L, -1));
    }
    lua_settop(L, top);
    return ok;
}

/*
 * 通用测试: 创建 soft SPI, 发送 send_byte, 验证:
 * 1. 主机收到的数据 == slave_tx
 * 2. 从机收到的数据 == send_byte
 */
static int test_xfer_mode(lua_State *L, int cpol, int cpha) {
    /* 引脚分配: CS=10, MOSI=11, MISO=12, CLK=13 */
    const int cs = 10, mosi = 11, miso = 12, clk = 13;
    uint8_t slave_tx[] = {0xA5};
    uint8_t master_tx = 0x3C;

    vslave_init(cs, mosi, miso, clk, cpol, cpha, slave_tx, 1);

    /* 设置初始 GPIO 电平 */
    gpio_levels[clk] = cpol;
    gpio_levels[cs] = 1;
    gpio_levels[mosi] = 1;
    gpio_levels[miso] = 1;

    char code[512];
    snprintf(code, sizeof(code),
        "local s = spi.createSoft(%d, %d, %d, %d, %d, %d, 8, spi.MSB, spi.master, spi.full) "
        "local r = spi.transfer(s, string.char(0x%02X), 1, 1) "
        "if not r then print('[spi_utest] transfer returned nil') return false end "
        "if #r ~= 1 then print('[spi_utest] recv len=' .. #r) return false end "
        "local got = string.byte(r, 1) "
        "if got ~= 0x%02X then print(string.format('[spi_utest] cpol=%d cpha=%d got=0x%%02X expect=0x%02X', got)) return false end "
        "return true",
        cs, mosi, miso, clk, cpha, cpol,
        master_tx, slave_tx[0], cpol, cpha, slave_tx[0]);

    int lua_ok = run_lua_expr(L, code);

    /* 验证从机收到的数据 */
    int slave_rx_ok = (g_vslave.byte_count >= 1 && g_vslave.rx_data[0] == master_tx);
    if (!slave_rx_ok) {
        printf("[spi_utest] cpol=%d cpha=%d slave_rx: byte_count=%d data[0]=0x%02X expect=0x%02X\n",
               cpol, cpha, g_vslave.byte_count,
               g_vslave.byte_count > 0 ? g_vslave.rx_data[0] : 0, master_tx);
    }

    vslave_deinit();

    return (lua_ok && slave_rx_ok) ? 0 : -1;
}

/* 多字节 transfer 测试 */
static int test_xfer_multibyte(lua_State *L, int cpol, int cpha) {
    const int cs = 10, mosi = 11, miso = 12, clk = 13;
    uint8_t slave_tx[] = {0xDE, 0xAD, 0xBE};
    uint8_t master_tx[] = {0x12, 0x34, 0x56};

    vslave_init(cs, mosi, miso, clk, cpol, cpha, slave_tx, 3);

    gpio_levels[clk] = cpol;
    gpio_levels[cs] = 1;
    gpio_levels[mosi] = 1;
    gpio_levels[miso] = 1;

    char code[512];
    snprintf(code, sizeof(code),
        "local s = spi.createSoft(%d, %d, %d, %d, %d, %d, 8, spi.MSB, spi.master, spi.full) "
        "local r = spi.transfer(s, string.char(0x12, 0x34, 0x56), 3, 3) "
        "if not r or #r ~= 3 then return false end "
        "local b1, b2, b3 = string.byte(r, 1, 3) "
        "return b1 == 0xDE and b2 == 0xAD and b3 == 0xBE",
        cs, mosi, miso, clk, cpha, cpol);

    int lua_ok = run_lua_expr(L, code);

    int slave_rx_ok = (g_vslave.byte_count >= 3 &&
                       g_vslave.rx_data[0] == master_tx[0] &&
                       g_vslave.rx_data[1] == master_tx[1] &&
                       g_vslave.rx_data[2] == master_tx[2]);

    vslave_deinit();

    return (lua_ok && slave_rx_ok) ? 0 : -1;
}

/* send-only 测试: 验证从机正确接收 */
static int test_send_mode(lua_State *L, int cpol, int cpha) {
    const int cs = 10, mosi = 11, miso = 12, clk = 13;

    vslave_init(cs, mosi, miso, clk, cpol, cpha, NULL, 0);

    gpio_levels[clk] = cpol;
    gpio_levels[cs] = 1;
    gpio_levels[mosi] = 1;
    gpio_levels[miso] = 1;

    char code[512];
    snprintf(code, sizeof(code),
        "local s = spi.createSoft(%d, %d, %d, %d, %d, %d, 8, spi.MSB, spi.master, spi.half) "
        "local r = spi.send(s, string.char(0x7B)) "
        "return true",
        cs, mosi, miso, clk, cpha, cpol);

    run_lua_expr(L, code);

    int slave_rx_ok = (g_vslave.byte_count >= 1 && g_vslave.rx_data[0] == 0x7B);

    vslave_deinit();

    return slave_rx_ok ? 0 : -1;
}

/* recv-only 测试: 验证主机正确接收从机数据 */
static int test_recv_mode(lua_State *L, int cpol, int cpha) {
    const int cs = 10, mosi = 11, miso = 12, clk = 13;
    uint8_t slave_tx[] = {0xC3};

    vslave_init(cs, mosi, miso, clk, cpol, cpha, slave_tx, 1);

    gpio_levels[clk] = cpol;
    gpio_levels[cs] = 1;
    gpio_levels[mosi] = 1;
    gpio_levels[miso] = 1;

    char code[512];
    snprintf(code, sizeof(code),
        "local s = spi.createSoft(%d, %d, %d, %d, %d, %d, 8, spi.MSB, spi.master, spi.half) "
        "local r = spi.recv(s, 1) "
        "return r and #r == 1 and string.byte(r, 1) == 0xC3",
        cs, mosi, miso, clk, cpha, cpol);

    int lua_ok = run_lua_expr(L, code);

    vslave_deinit();

    return lua_ok ? 0 : -1;
}

/* ---------- 入口 ---------- */

int luat_spi_utest(lua_State *L, const char *case_name) {
    if (!case_name)
        return -1;

    /* 全双工 xfer 测试: 4 种 SPI 模式 */
    if (strcmp(case_name, "xfer_mode0") == 0)
        return test_xfer_mode(L, 0, 0);
    if (strcmp(case_name, "xfer_mode1") == 0)
        return test_xfer_mode(L, 0, 1);
    if (strcmp(case_name, "xfer_mode2") == 0)
        return test_xfer_mode(L, 1, 0);
    if (strcmp(case_name, "xfer_mode3") == 0)
        return test_xfer_mode(L, 1, 1);

    /* 多字节 xfer 测试 */
    if (strcmp(case_name, "xfer_multibyte_mode0") == 0)
        return test_xfer_multibyte(L, 0, 0);
    if (strcmp(case_name, "xfer_multibyte_mode1") == 0)
        return test_xfer_multibyte(L, 0, 1);
    if (strcmp(case_name, "xfer_multibyte_mode2") == 0)
        return test_xfer_multibyte(L, 1, 0);
    if (strcmp(case_name, "xfer_multibyte_mode3") == 0)
        return test_xfer_multibyte(L, 1, 1);

    /* send-only 测试 */
    if (strcmp(case_name, "send_mode0") == 0)
        return test_send_mode(L, 0, 0);
    if (strcmp(case_name, "send_mode1") == 0)
        return test_send_mode(L, 0, 1);
    if (strcmp(case_name, "send_mode2") == 0)
        return test_send_mode(L, 1, 0);
    if (strcmp(case_name, "send_mode3") == 0)
        return test_send_mode(L, 1, 1);

    /* recv-only 测试 */
    if (strcmp(case_name, "recv_mode0") == 0)
        return test_recv_mode(L, 0, 0);
    if (strcmp(case_name, "recv_mode1") == 0)
        return test_recv_mode(L, 0, 1);
    if (strcmp(case_name, "recv_mode2") == 0)
        return test_recv_mode(L, 1, 0);
    if (strcmp(case_name, "recv_mode3") == 0)
        return test_recv_mode(L, 1, 1);

    return -1;
}
