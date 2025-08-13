#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"

#include "luat_rtos.h"
#include "luat_mobile.h"
#include "luat_network_adapter.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"

#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "airlink.slave"
#include "luat_log.h"

#define TEST_BUFF_SIZE (1600)
#define SLAVE_SPI_ID g_airlink_spi_conf.spi_id
#define AIRLINK_SPI_CS_PIN g_airlink_spi_conf.cs_pin
#define AIRLINK_SPI_RDY_PIN g_airlink_spi_conf.rdy_pin
#define AIRLINK_SPI_IRQ_PIN g_airlink_spi_conf.irq_pin

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

// static uint8_t thread_rdy;
static luat_rtos_task_handle spi_task_handle;
static luat_rtos_queue_t evt_queue;
extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_pause;

static uint8_t *s_txbuff;
static uint8_t *s_rxbuff;
static int self_ready;
static int pin_rdy_state;
// static uint8_t g_sys_need_reboot;
static int is_irq_mode;
static uint32_t irq_counter; // 中断计数

static uint8_t basic_info[sizeof(luat_airlink_dev_info_t) + 64];
static inline luat_airlink_dev_info_t * self_devinfo(void) {
    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    return (luat_airlink_dev_info_t *)(cmd->data);
}

static void print_tm(const char* tag) {
    uint32_t tm = (uint32_t)luat_mcu_tick64_ms();
    LLOGD("TM[%s] %8ld", tag, tm);
}

// 更新link的链路状态
// extern uint32_t g_fota_busy;
static int link_data_cb(airlink_link_data_t* link) {
    link->flags.irq_ready = is_irq_mode;
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;
    luat_meminfo_opt_sys(LUAT_HEAP_PSRAM, &total, &used, &max_used);

    if (total - used < 8 * 1024) {
        link->flags.mem_is_high = 1; // 链路繁忙!!!
        return 0;
    }

    size_t len = 0;
    len = luat_airlink_queue_get_cnt(LUAT_AIRLINK_QUEUE_CMD);
    if (len > 0) {
        link->flags.queue_cmd = 1;
        // LLOGD("剩余CMD数据队列长度 %d", len);
    }
    len = luat_airlink_queue_get_cnt(LUAT_AIRLINK_QUEUE_IPPKG);
    if (len > 0) {
        link->flags.queue_ip = 1;
        // LLOGD("剩余IP数据队列长度 %d", len);
    }
    return 0;
}

__USER_FUNC_IN_RAM__ static void on_newdata_notify(void) {
    if (is_irq_mode) {
        // LLOGD("is_irq_mode %d pin %d count %ld", is_irq_mode, s_irq_pin, irq_counter);
        luat_gpio_set(AIRLINK_SPI_IRQ_PIN, 0);
        luat_gpio_set(AIRLINK_SPI_IRQ_PIN, 1);
        irq_counter ++;
    }
}

static void send_devinfo_update_evt(void) {
    airlink_queue_item_t item = {0};
    // 发送空消息, 会自动转为devinfo消息
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item); 
}

__USER_FUNC_IN_RAM__ static int spi_slave_irq(void* param) {
    if (self_ready == 0) {
        return 0;
    }
    // 立即拉高RDY脚, 阻止主机的发送
    pin_rdy_state = 1;
    luat_gpio_set(AIRLINK_SPI_RDY_PIN, 1);

    luat_event_t evt = {.id = 1};
    luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
    return 0;
}

static void slave_irq_mode_startup(airlink_link_data_t* link) {
    luat_gpio_cfg_t gpio  = {0};
    int ret = 0;
    gpio.pin = AIRLINK_SPI_IRQ_PIN;
    gpio.mode = LUAT_GPIO_OUTPUT;
    gpio.pull = LUAT_GPIO_PULLUP;
    gpio.output_level = 1;
    ret = luat_gpio_open(&gpio);
    if (ret != 0) {
        LLOGE("IRQ模式开启失败, GPIO %d %d", gpio.pin, ret);
    }
    // LLOGD("IRQ模式开启, GPIO %d %d", gpio.pin, ret);
    // s_irq_pin = gpio.pin;
    // is_irq_mode = 1;
}

static void spi_gpio_setup(void) {
    // LLOGD("spi_gpio_setup");
    // LLOGD("g_airlink_spi_conf %p", &g_airlink_spi_conf);
    // int ret = 0;
    if (g_airlink_spi_conf.cs_pin == 0)
    {
        // if (g_airlink_spi_conf.spi_id == 0) {
        g_airlink_spi_conf.cs_pin = 8;
        // }
        // else {
        //     g_airlink_spi_conf.cs_pin = 8;
        // }
    }
    if (g_airlink_spi_conf.rdy_pin == 0)
    {
        // if (g_airlink_spi_conf.spi_id == 0) {
        g_airlink_spi_conf.rdy_pin = 22;
        // }
    }
    if (g_airlink_spi_conf.irq_pin == 0)
    {
        g_airlink_spi_conf.irq_pin = 255; // 默认禁用irq脚
    }

    LLOGI("spi slave id %d cs %d rdy %d irq %d", SLAVE_SPI_ID, g_airlink_spi_conf.cs_pin, g_airlink_spi_conf.rdy_pin, g_airlink_spi_conf.irq_pin);

    luat_pm_iovolt_ctrl(0, 3300);

    // 从机准备好脚
    luat_spi_t spi_conf = {
        .id = SLAVE_SPI_ID,
        .CPOL = 1,
        .CPHA = 1,
        .dataw = 8,
        .bit_dict = 0,
        .master = 0,    // 1 主模式; 0 从模式
        .mode = 1, // mode设置为1，全双工
        .bandrate = 31000000,
        .cs = 255};
    
    luat_spi_setup(&spi_conf);

    luat_gpio_cfg_t gpio_cfg = {0};

    // CS片选脚
    luat_gpio_set_default_cfg(&gpio_cfg);
    gpio_cfg.pin = AIRLINK_SPI_CS_PIN;
    gpio_cfg.mode = LUAT_GPIO_IRQ;
    gpio_cfg.irq_type = LUAT_GPIO_RISING_IRQ;
    gpio_cfg.pull = LUAT_GPIO_PULLUP;
    gpio_cfg.irq_cb = spi_slave_irq;
    luat_gpio_open(&gpio_cfg);

    if (AIRLINK_SPI_RDY_PIN != 255)
    {
        luat_gpio_set_default_cfg(&gpio_cfg);
        gpio_cfg.pin = AIRLINK_SPI_RDY_PIN;
        gpio_cfg.mode = LUAT_GPIO_OUTPUT;
        gpio_cfg.pull = LUAT_GPIO_PULLUP;
        gpio_cfg.output_level = 1;
        luat_gpio_open(&gpio_cfg);
        pin_rdy_state = 1;
    }
}

extern luat_airlink_mobile_evt_cb g_airlink_mobile_evt_cb;
static int mobile_evt_handler(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr) {
    // luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    luat_airlink_dev_info_t *devinfo = self_devinfo();
	// LLOGD("mobile_evt_handler event:%d, index:%d, status:%d", event, index, status);
	switch(event)
	{
	case LUAT_MOBILE_EVENT_CFUN:
		break;
	case LUAT_MOBILE_EVENT_SIM:
/*
@sys_pub mobile
sim卡状态变化
SIM_IND
@usage
sys.subscribe("SIM_IND", function(status, value)
    -- status的取值有:
    -- RDY SIM卡就绪, value为nil
    -- NORDY 无SIM卡, value为nil
    -- SIM_PIN 需要输入PIN, value为nil
    -- GET_NUMBER 获取到电话号码(不一定有值), value为nil
    -- SIM_WC SIM卡的写入次数统计,掉电归0, value为统计值
    log.info("sim status", status, value)
end)
*/
        LLOGD("SIM_IND -> status %d", status);
        devinfo->cat1.sim_state = status;
        switch (status)
        {
        case LUAT_MOBILE_SIM_READY:
            luat_mobile_get_iccid(0, (char*)devinfo->cat1.iccid, 20);
            luat_mobile_get_imsi(0, (char*)devinfo->cat1.imsi, 16);
            LLOGD("SIM_READY -> ICCID %s", devinfo->cat1.iccid);
            LLOGD("SIM_READY -> IMSI %s", devinfo->cat1.imsi);
            send_devinfo_update_evt();
            break;
        case LUAT_MOBILE_NO_SIM:
            memset(devinfo->cat1.iccid, 0, 20);
            memset(devinfo->cat1.imsi, 0, 16);
            send_devinfo_update_evt();
            break;
        case LUAT_MOBILE_SIM_NEED_PIN:
            break;
        case LUAT_MOBILE_SIM_NUMBER:
            break;
        case LUAT_MOBILE_SIM_WC:
            break;
        default:
            break;
        }
		break;
	case LUAT_MOBILE_EVENT_REGISTER_STATUS:
		break;
	case LUAT_MOBILE_EVENT_CELL_INFO:
        switch (status)
        {
        case LUAT_MOBILE_CELL_INFO_UPDATE:
/*
@sys_pub mobile
基站数据已更新
CELL_INFO_UPDATE
@usage
-- 订阅式
sys.subscribe("CELL_INFO_UPDATE", function()
    log.info("cell", json.encode(mobile.getCellInfo()))
end)
*/

		    break;
        case LUAT_MOBILE_SERVICE_CELL_UPDATE:
/*
@sys_pub mobile
服务小区额外信息更新
SCELL_INFO
@usage
-- 订阅式
sys.subscribe("SCELL_INFO", function()
    log.info("service cell", mobile.scell()))
end)
*/

        default:
            break;
        }
		break;
	case LUAT_MOBILE_EVENT_PDP:
		LLOGD("cid%d, state%d", index, status);
		break;
	case LUAT_MOBILE_EVENT_NETIF:
		switch (status)
		{
		case LUAT_MOBILE_NETIF_LINK_ON: {
        devinfo->cat1.cat_state = 1;
        send_devinfo_update_evt();
        LLOGD("NETIF_LINK_ON -> IP_READY cat1.cat_state %d ipv4 %d.%d.%d.%d", devinfo->cat1.cat_state, devinfo->cat1.ipv4[0], devinfo->cat1.ipv4[1], devinfo->cat1.ipv4[2], devinfo->cat1.ipv4[3]);
/*
@sys_pub mobile
已联网
IP_READY
@usage
-- 联网后会发一次这个消息
sys.subscribe("IP_READY", function(ip, adapter)
    log.info("mobile", "IP_READY", ip, (adapter or -1) == socket.LWIP_GP)
end)
*/
			break;
        }
        case LUAT_MOBILE_NETIF_LINK_OFF:
        devinfo->cat1.cat_state = 0;
        send_devinfo_update_evt();
        LLOGD("NETIF_LINK_OFF -> IP_LOSE cat1.cat_state %d", devinfo->cat1.cat_state); 
/*
@sys_pub mobile
已断网
IP_LOSE
@usage
-- 断网后会发一次这个消息
sys.subscribe("IP_LOSE", function(adapter)
    log.info("mobile", "IP_LOSE", (adapter or -1) == socket.LWIP_GP)
end)
*/
            break;
		default:
			break;
		}
		break;
	case LUAT_MOBILE_EVENT_TIME_SYNC:
/*
@sys_pub mobile
时间已经同步
NTP_UPDATE
@usage
-- 对于电信/移动的卡, 联网后,基站会下发时间,但联通卡不会,务必留意
sys.subscribe("NTP_UPDATE", function()
    log.info("mobile", "time", os.date())
end)
*/

		break;
	case LUAT_MOBILE_EVENT_CSCON:
//		LLOGD("CSCON %d", status);
/*
@sys_pub mobile
RRC状态
CSCON
@usage
-- state 1 CONNECT 0 IDLE
sys.subscribe("CSCON", function(state)
	log.info("mobile", "CSCON", state)
end)
*/

		break;
	case LUAT_MOBILE_EVENT_BEARER:
		LLOGD("bearer act %d, result %d",status, index);
		break;
	case LUAT_MOBILE_EVENT_SMS:
		switch(status)
		{
		case LUAT_MOBILE_SMS_READY:
			LLOGI("sim%d sms ready", index);
			break;
		case LUAT_MOBILE_NEW_SMS:
			break;
		case LUAT_MOBILE_SMS_SEND_DONE:
			break;
		case LUAT_MOBILE_SMS_ACK:
			break;
		}
		break;
	case LUAT_MOBILE_EVENT_IMS_REGISTER_STATUS:
        LLOGD("ims reg state %d", status);
		break;
    case LUAT_MOBILE_EVENT_CC:
        LLOGD("LUAT_MOBILE_EVENT_CC status %d",status);
/*
@sys_pub mobile
通话状态变化
CC_IND
@usage
sys.subscribe("CC_IND", function(status, value)
    log.info("cc status", status, value)
end)
*/
        switch(status){
        case LUAT_MOBILE_CC_READY:
            LLOGD("LUAT_MOBILE_CC_READY");
            break;
        case LUAT_MOBILE_CC_INCOMINGCALL:
            break;
        case LUAT_MOBILE_CC_CALL_NUMBER:
            // lua_pushstring(L, "CC_IND");
            // lua_pushstring(L, "CALL_NUMBER");
            // lua_call(L, 2, 0);
            break;
        case LUAT_MOBILE_CC_CONNECTED_NUMBER:
            // lua_pushstring(L, "CC_IND");
            // lua_pushstring(L, "CONNECTED_NUMBER");
            // lua_call(L, 2, 0);
            break;
        case LUAT_MOBILE_CC_CONNECTED:
            break;
        case LUAT_MOBILE_CC_DISCONNECTED:
            break;
        case LUAT_MOBILE_CC_SPEECH_START:
            break;
        case LUAT_MOBILE_CC_MAKE_CALL_OK:
            break;
        case LUAT_MOBILE_CC_MAKE_CALL_FAILED:
            break;
        case LUAT_MOBILE_CC_ANSWER_CALL_DONE:
            break;
        case LUAT_MOBILE_CC_HANGUP_CALL_DONE:
            break;
        case LUAT_MOBILE_CC_LIST_CALL_RESULT:
            break;
        case LUAT_MOBILE_CC_PLAY:// 最先
            break;
        }
        break;
	default:
		break;
	}
    send_devinfo_update_evt();
    return 0;
}

__USER_FUNC_IN_RAM__ static void start_spi_trans(void) {
    // 首先, 把rxbuff填0, 不要收到老数据的干扰
    // LLOGD("执行start_spi_trans");
    memset(s_rxbuff, 0, TEST_BUFF_SIZE);
    airlink_queue_item_t item = {0};
    // print_tm("准备执行luat_airlink_cmd_recv_simple");
    luat_airlink_cmd_recv_simple(&item);
    // LLOGD("执行完luat_airlink_cmd_recv_simple cmd %p len %d", item.cmd, item.len);
    if (item.len > 0 && item.cmd != NULL) {
        // LLOGD("发送待传输的数据, 塞入SPI的FIFO %d", item.len);
        luat_airlink_data_pack(item.cmd, item.len, s_txbuff);
        // LLOGD("执行完luat_airlink_cmd_recv_simplecmd %p len %d --- ", item.cmd, item.len);
        luat_airlink_cmd_free(item.cmd);
    }
    else {
        // LLOGD("填充PING数据");
        luat_airlink_data_pack(basic_info, sizeof(basic_info), s_txbuff);
    }

    luat_spi_slave_transfer(SLAVE_SPI_ID, (const char*)s_txbuff, (char*)s_rxbuff, TEST_BUFF_SIZE);

    // 通知主机已经准备好了
    luat_gpio_set(AIRLINK_SPI_RDY_PIN, 0);
    pin_rdy_state = 0;
}

__USER_FUNC_IN_RAM__ static void spi_slave_task(void *param)
{
    // LLOGE("spi_slave_task!!!");
    int ret = 0;
    airlink_link_data_t* link = NULL;
    luat_event_t event = {0};

    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    cmd->cmd = 0x10;
    cmd->len = 128;
    
    luat_airlink_dev_info_t *devinfo = self_devinfo();
    devinfo->tp = 0x02;
    uint32_t fw_version = 3;
    memcpy(devinfo->cat1.version, &fw_version, sizeof(uint32_t));   // 版本
    luat_mobile_get_sn(devinfo->cat1.unique_id, 32);                // 唯一ID
    luat_mobile_get_imei(0, devinfo->cat1.imei, 16);                // IMEI


    // // 执行主循环
    g_airlink_link_data_cb = link_data_cb;
    g_airlink_newdata_notify_cb = on_newdata_notify;
    g_airlink_mobile_evt_cb = mobile_evt_handler;

    // 告知已经就绪
    self_ready = 1;
    // // bk_spi_dma_duplex_init(SLAVE_SPI_ID);
    start_spi_trans();
    while (1) {   
        // // 执行主循环
        event.id = 0;
        // print_tm("执行luat_rtos_event_recv");

        ret = luat_rtos_queue_recv(evt_queue, &event, sizeof(luat_event_t), LUAT_WAIT_FOREVER);
        if (ret) {
            // nop
        }
        // luat_rtos_event_recv(spi_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
        // print_tm("执行完luat_rtos_event_recv");
        int cs_level = luat_gpio_get(AIRLINK_SPI_CS_PIN);
        // LLOGD("CS脚状态 %d %s %s event.id %d ret %d %p", cs_level, __DATE__, __TIME__, event.id, ret, spi_task_handle);
        if (cs_level == 1) {
            #if 1
            int len = luat_spi_slave_transfer_pause_and_read_data(SLAVE_SPI_ID);
            g_airlink_statistic.tx_pkg.total++;
            if (len > 0 && len < 2024) {
                // LLOGE("数据长度 %d %d", len, SLAVE_SPI_ID);
                link = luat_airlink_data_unpack(s_rxbuff, len);
                if (link) {
                    g_airlink_statistic.tx_pkg.ok++;
                    luat_airlink_on_data_recv(link->data, link->len);
                    g_airlink_last_cmd_timestamp = luat_mcu_tick64_ms();
                }
                else {
                    g_airlink_statistic.tx_pkg.err++;
                    // LLOGW("数据包错误, 重置SPI");
                    luat_spi_close(SLAVE_SPI_ID);
                    spi_gpio_setup();
                }
            //     // print_tm("执行完luat_airlink_data_unpack");
            }
            else {
                // LLOGW("数据长度错误 %d %d", len, SLAVE_SPI_ID);
            }
            // LLOGD("恢复到普通状态, 等待下一轮传输 %d", ret);  
            start_spi_trans();
            // pin_rdy_state = 0;
            #endif
        }
    }
    // LLOGD("退出SPI从机任务!!");
    
    luat_spi_close(SLAVE_SPI_ID);
    luat_spi_slave_transfer_stop(SLAVE_SPI_ID);
    while (1) {
        // 循环执行复位
        luat_rtos_task_sleep(1000);
        // LLOGD("尝试重启系统 %d", g_sys_need_reboot);
        // bk_reboot();
    }
}

#ifndef __BK72XX__
void luat_airlink_start_slave(void)
{
    LLOGD("luat_airlink_start_slave!!!");
    if (spi_task_handle != NULL)
    {
        LLOGE("SPI从机任务已经启动过了!!!");
        return;
    }
    
    if (s_rxbuff == NULL) {
        // 分配内存
        s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    }
    if (s_txbuff == NULL) {
        // 分配内存给s_rxbuff
        s_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    }
    spi_gpio_setup();

    luat_rtos_queue_create(&evt_queue, 2 * 1024, sizeof(luat_event_t));
    luat_rtos_task_create(&spi_task_handle, 16 * 1024, 50, "spi_slave", spi_slave_task, NULL, 0);
}
#endif
