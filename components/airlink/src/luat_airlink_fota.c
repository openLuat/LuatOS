#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_fota.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "airlink.fota"
#include "luat_log.h"

luat_airlink_fota_t* g_airlink_fota;

int luat_airlink_fota_init(luat_airlink_fota_t* ctx) {
    if (g_airlink_fota || g_airlink_fota->state != 0) {
        return -1;
    }
    if (!g_airlink_fota) {
        g_airlink_fota = luat_heap_malloc(sizeof(luat_airlink_fota_t));
    }
    if (g_airlink_fota == NULL) {
        LLOGE("airlink fota malloc failed");
        return -2;
    }
    memcpy(g_airlink_fota, ctx, sizeof(luat_airlink_fota_t));
    g_airlink_fota->state = 1;
    return 0;
}

int luat_airlink_fota_stop(void) {
    if (g_airlink_fota == NULL) {
        return 0;
    }
    g_airlink_fota->state = 0;
    return 0;
}

#define AIRLINK_SFOTA_BUFF_SIZE (1600)
static uint8_t* s_airlink_fota_txbuff;
static uint8_t* s_airlink_fota_rxbuff;
static uint8_t* s_airlink_fota_cmdbuff;

static void pack_and_send(uint16_t cmd_id, uint8_t* data, size_t len) {
    // 首先, 打包到txbuff中
    luat_airlink_cmd_t* cmd = s_airlink_fota_cmdbuff;
    cmd->cmd = cmd_id;
    cmd->len = len;
    if (len) {
        memcpy(cmd->data, data, len);
    }

    luat_airlink_data_pack(data, sizeof(luat_airlink_cmd_t) + len, s_airlink_fota_txbuff);

    airlink_wait_for_slave_ready(1000);
    airlink_transfer_and_exec(s_airlink_fota_txbuff, s_airlink_fota_rxbuff);

    memset(s_airlink_fota_txbuff, 0, AIRLINK_SFOTA_BUFF_SIZE);
}

void airlink_sfota_exec(void) {
    size_t wait_timeout = 0;
    int ret = 0;
    LLOGI("开始执行sFOTA");
    FILE* fd = luat_fs_fopen(g_airlink_fota->path, "rb");
    if (fd == NULL) {
        LLOGE("打开sFOTA文件失败 %s", g_airlink_fota->path);
        goto clean;
    }
    if (s_airlink_fota_txbuff == NULL) {
        s_airlink_fota_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, AIRLINK_SFOTA_BUFF_SIZE);
        s_airlink_fota_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, AIRLINK_SFOTA_BUFF_SIZE);
        s_airlink_fota_cmdbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, AIRLINK_SFOTA_BUFF_SIZE);
        if (s_airlink_fota_txbuff == NULL || s_airlink_fota_rxbuff == NULL || s_airlink_fota_cmdbuff == NULL) {
            LLOGE("申请sFOTA内存失败");
            goto clean;
        }
        memset(s_airlink_fota_txbuff, 0, AIRLINK_SFOTA_BUFF_SIZE);
        memset(s_airlink_fota_rxbuff, 0, AIRLINK_SFOTA_BUFF_SIZE);
        memset(s_airlink_fota_cmdbuff, 0, AIRLINK_SFOTA_BUFF_SIZE);
    }
    // 首先, 发送fota_init指令
    // luat_airlink_send_cmd_simple_nodata(0x04);
    pack_and_send(0x04, NULL, 0);

    wait_timeout = 500;
    if (g_airlink_fota->wait_init > 0) {
        wait_timeout = g_airlink_fota->wait_init;
    }
    LLOGI("等待sFOTA初始化 %dms", wait_timeout);
    luat_rtos_task_sleep(wait_timeout);
    
    // 开始发送数据
    ret = luat_fs_fread(s_airlink_fota_rxbuff, 1, 1400, fd);
    if (ret != 1400) {
        LLOGE("读取sFOTA文件失败 %d", ret);
        goto clean;
    }
    // 第一个包要等很久的
    // luat_airlink_send_cmd_simple(0x05, s_airlink_fota_rxbuff, 1400);
    pack_and_send(0x05, s_airlink_fota_rxbuff, 1400);
    wait_timeout = 5000;
    if (g_airlink_fota->wait_first_data) {
        wait_timeout = g_airlink_fota->wait_first_data;
    }
    LLOGI("等待sFOTA第一个包执行完成 %dms", wait_timeout);
    luat_rtos_task_sleep(wait_timeout);

    // 发送剩余的数据
    wait_timeout = 10;
    if (g_airlink_fota->wait_data) {
        wait_timeout = g_airlink_fota->wait_data;
    }
    while (g_airlink_fota->state) {
        ret = luat_fs_fread(s_airlink_fota_rxbuff, 1, 1400, fd);
        if (ret < 1) {
            break;
        }
        if (wait_timeout > 0) {
            luat_rtos_task_sleep(wait_timeout);
        }
        // luat_airlink_send_cmd_simple(0x05, s_airlink_fota_rxbuff, ret);
        pack_and_send(0x05, s_airlink_fota_rxbuff, ret);
    }
    LLOGI("文件数据发送结束, 等待100ms,执行done操作");
    luat_rtos_task_sleep(100);
    luat_fs_fclose(fd);

    // 发送done命令
    // luat_airlink_send_cmd_simple_nodata(0x06);
    pack_and_send(0x06, NULL, 0);
    luat_rtos_task_sleep(500);
    LLOGI("done发送结束, 等待100ms, 执行end操作");
    luat_rtos_task_sleep(100);
    // luat_airlink_send_cmd_simple_nodata(0x07);
    pack_and_send(0x07, NULL, 0);

    LLOGI("end发送结束, 等待3000ms, 执行重启操作");
    luat_rtos_task_sleep(3000);
    // luat_airlink_send_cmd_simple_nodata(0x03);
    if (g_airlink_fota->pwr_gpio) {
        LLOGI("使用GPIO复位 %d", g_airlink_fota->pwr_gpio);
        luat_gpio_set(g_airlink_fota->pwr_gpio, 0);
        luat_rtos_task_sleep(50);
        luat_gpio_set(g_airlink_fota->pwr_gpio, 1);
    }
    else {
        LLOGI("使用命令复位");
        pack_and_send(0x03, NULL, 0);
    }

    wait_timeout = 30*1000;
    if (g_airlink_fota->wait_reboot) {
        wait_timeout = g_airlink_fota->wait_reboot;
    }
    luat_rtos_task_sleep(wait_timeout);
    LLOGI("FOTA执行完毕");

clean:
    g_airlink_fota->state = 0;
    if (fd) {
        luat_fs_fclose(fd);
    }
    if (s_airlink_fota_rxbuff) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, s_airlink_fota_rxbuff);
        s_airlink_fota_rxbuff = NULL;
    }
    if (s_airlink_fota_txbuff) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, s_airlink_fota_txbuff);
        s_airlink_fota_txbuff = NULL;
    }
    if (s_airlink_fota_cmdbuff) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, s_airlink_fota_cmdbuff);
        s_airlink_fota_cmdbuff = NULL;
    }
    return;
}
