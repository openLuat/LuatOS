#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#ifdef CHIP_EC718

#define TEST_SPI_ID   0
#define TEST_BUFF_SIZE (1600)
#define TEST_CS_PIN 8
#define TEST_RDY_PIN 22
#define TEST_BTN_PIN 0

#else

#define TEST_SPI_ID   0
#define TEST_BUFF_SIZE (1600)
#define TEST_CS_PIN 15
#define TEST_RDY_PIN 22
#define TEST_BTN_PIN 2

#endif

static uint8_t start;
static uint8_t slave_rdy;
static uint8_t thread_rdy;
static luat_rtos_task_handle spi_task_handle;

static uint8_t basic_info[256];

static int gpio_boot_irq(void *data, void* args)
{
	if (thread_rdy) {
        luat_rtos_event_send(spi_task_handle, 1, 2, 3, 4, 100);
    }
	return 0;
}

static int slave_rdy_irq(void *data, void* args) {
    slave_rdy = 1;
    // luat_rtos_event_send(gpio_task_handle, 1, 2, 3, 4, 100);
    return 0;
}

static void test_gpio(void) {
    
	luat_gpio_cfg_t gpio_cfg;

    // 触发脚, BOOT脚, 只是为了测试
	luat_gpio_set_default_cfg(&gpio_cfg);
	gpio_cfg.pin = TEST_BTN_PIN;
	gpio_cfg.mode = LUAT_GPIO_IRQ;
	gpio_cfg.irq_type = LUAT_GPIO_RISING_IRQ;
	gpio_cfg.pull = LUAT_GPIO_PULLDOWN;
	gpio_cfg.irq_cb = gpio_boot_irq;
	luat_gpio_open(&gpio_cfg);
}

static void spi_gpio_setup(void) {
    luat_spi_t spi_conf = {
        .id = TEST_SPI_ID,
        .CPHA = 1,
        .CPOL = 1,
        .dataw = 8,
        .bit_dict = 0,
        .master = 1,
        .mode = 1,             // mode设置为1，全双工
		.bandrate = 31000000,
        .cs = 255
    };
    luat_pm_iovolt_ctrl(0, 3300);
    luat_spi_setup(&spi_conf);
	luat_gpio_cfg_t gpio_cfg;

    // 测试用途的管脚, 只是为了方便测试, 正式环境就去掉
    test_gpio();

    // 从机准备好脚
    luat_gpio_set_default_cfg(&gpio_cfg);
    gpio_cfg.pin = TEST_RDY_PIN;
    gpio_cfg.mode = LUAT_GPIO_IRQ;
    gpio_cfg.irq_type = LUAT_GPIO_FALLING_IRQ;
    gpio_cfg.pull = LUAT_GPIO_PULLUP;
    gpio_cfg.irq_cb = slave_rdy_irq;
    luat_gpio_open(&gpio_cfg);
    LLOGD(" gpio rdy setup done %d", TEST_RDY_PIN);

    // CS片选脚
	luat_gpio_set_default_cfg(&gpio_cfg);
	gpio_cfg.pin = TEST_CS_PIN;
	gpio_cfg.mode = LUAT_GPIO_OUTPUT;
	gpio_cfg.pull = LUAT_GPIO_PULLUP;
    gpio_cfg.output_level = 1;
	luat_gpio_open(&gpio_cfg);
}


static void spi_master_task(void *param)
{
    int i;
    size_t pkg_offset = 0;
    size_t pkg_size = 0;
    int tmpval = 0;
    luat_event_t event = {0};
    airlink_queue_item_t item = {0};
	static uint8_t txbuff[TEST_BUFF_SIZE] = {0x90,0x80,0x70,0x60};
    static uint8_t rxbuff[TEST_BUFF_SIZE] = {0};

    luat_rtos_task_sleep(5); // 等5ms
    spi_gpio_setup();
    thread_rdy = 1;

    const char* test_data = "123456789";
    luat_airlink_data_pack((uint8_t*)test_data, strlen(test_data), basic_info);
    // luat_airlink_print_buff("TX", txbuff, 16);

    while (1)
    {
        // 等到消息
        event.id = 0;
        item.len = 0;
        luat_rtos_event_recv(spi_task_handle, 0, &event, NULL, 5000);
        luat_airlink_cmd_recv_simple(&item);
        if (item.len == 0 && event.id == 0) {
            // LLOGD("啥都没等到, 继续等");
            continue; // 无事发生,继续等下一个事件.
        }
        if (item.len > 0 && item.cmd != NULL) {
            LLOGD("发送待传输的数据, 塞入SPI的FIFO %d", item.len);
            luat_airlink_data_pack(item.cmd, item.len, txbuff);
            luat_heap_free(item.cmd);
        }
        else {
            LLOGD("填充PING数据");
            luat_airlink_data_pack(basic_info, sizeof(basic_info), txbuff);
        }
        slave_rdy = 0;
        luat_gpio_set(TEST_CS_PIN, 0);
        for (size_t i = 0; i < 5; i++)
        {
            tmpval = luat_gpio_get(TEST_RDY_PIN);
            if (tmpval == 1) {
                LLOGD("从机未就绪,等1ms");
                luat_rtos_task_sleep(1);
                continue;
            }
            LLOGD("从机已就绪!! %s %s", __DATE__, __TIME__);
            break;
        }
        
        luat_spi_transfer(TEST_SPI_ID, (const char*)txbuff, TEST_BUFF_SIZE, (char*)rxbuff, TEST_BUFF_SIZE);
        luat_gpio_set(TEST_CS_PIN, 1);
        // luat_airlink_print_buff("RX", rxbuff, 32);
        // 对接收到的数据进行解析
        pkg_offset = 0;
        pkg_size = 0;
        luat_airlink_data_unpack(rxbuff, TEST_BUFF_SIZE, &pkg_offset, &pkg_size);
        if (pkg_size) {
            luat_airlink_on_data_recv(rxbuff + pkg_offset, pkg_size);
        }
        
        memset(rxbuff, 0, TEST_BUFF_SIZE);
        // luat_rtos_task_sleep(300);
        start = 0;
    }
}


void luat_airlink_start_master(void)
{
    if (spi_task_handle != NULL) {
        LLOGE("SPI主机任务已经启动过了!!!");
        return;
    }
    luat_rtos_task_create(&spi_task_handle, 4 * 1024, 95, "spi", spi_master_task, NULL, 0);
}
