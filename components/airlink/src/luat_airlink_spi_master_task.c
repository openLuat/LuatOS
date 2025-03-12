#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#ifdef CHIP_EC718

#define TEST_SPI_ID   0
#define TEST_BUFF_SIZE (1600)
#define TEST_CS_PIN 8
#define TEST_RDY_PIN 26
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
static luat_rtos_task_handle spi_task_handle;
static luat_rtos_task_handle gpio_task_handle;

static int gpio_level_irq(void *data, void* args)
{
	start = 1;
	return 0;
}

static int slave_rdy_irq(void *data, void* args) {
    slave_rdy = 1;
    luat_rtos_event_send(gpio_task_handle, 1, 2, 3, 4, 100);
    return 0;
}


static void task_test_spi(void *param)
{
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

    // 触发脚
	luat_gpio_set_default_cfg(&gpio_cfg);
	gpio_cfg.pin = TEST_BTN_PIN;
	gpio_cfg.mode = LUAT_GPIO_IRQ;
	gpio_cfg.irq_type = LUAT_GPIO_RISING_IRQ;
	gpio_cfg.pull = LUAT_GPIO_PULLDOWN;
	gpio_cfg.irq_cb = gpio_level_irq;
	luat_gpio_open(&gpio_cfg);

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

    int i;
    size_t pkg_offset = 0;
    size_t pkg_size = 0;
    int tmpval = 0;
	static uint8_t send_buf[TEST_BUFF_SIZE] = {0x90,0x80,0x70,0x60};
    static uint8_t recv_buf[TEST_BUFF_SIZE] = {0};
    const char* test_data = "123456789";
    luat_airlink_data_pack((uint8_t*)test_data, strlen(test_data), send_buf);
    luat_airlink_print_buff("TX", send_buf, 16);

    while (1)
    {
        // TODO 从队列读取数据, 然后打包, 发送给从机
        while(!start){luat_rtos_task_sleep(100);}
        slave_rdy = 0;
        luat_gpio_set(TEST_CS_PIN, 0);
        for (size_t i = 0; i < 5; i++)
        {
            tmpval = luat_gpio_get(TEST_RDY_PIN);
            if (tmpval == 0) {
                LLOGD("从机未就绪,等1ms");
                luat_rtos_task_sleep(1);
                continue;
            }
            LLOGD("从机已就绪!!");
            break;
        }
        
        luat_spi_transfer(TEST_SPI_ID, (const char*)send_buf, TEST_BUFF_SIZE, (char*)recv_buf, TEST_BUFF_SIZE);
        luat_gpio_set(TEST_CS_PIN, 1);
        luat_airlink_print_buff("RX", recv_buf, 32);
        // 对接收到的数据进行解析
        pkg_offset = 0;
        pkg_size = 0;
        luat_airlink_data_unpack(recv_buf, TEST_BUFF_SIZE, &pkg_offset, &pkg_size);
        if (pkg_size) {
            luat_airlink_on_data_recv(recv_buf + pkg_offset, pkg_size);
        }
        
        memset(recv_buf, 0, TEST_BUFF_SIZE);
        luat_rtos_task_sleep(300);
        start = 0;
    }
}

// static  void task_gpio_why(void *param) {
//     luat_event_t event;
//     while (1) {
//         luat_rtos_event_recv(gpio_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
//         LLOGD("GPIO IRQ %d", event.id);
//     }
// }


void luat_airlink_start_master(void)
{
    luat_rtos_task_create(&spi_task_handle, 4 * 1024, 95, "spi", task_test_spi, NULL, 0);
    // luat_rtos_task_create(&gpio_task_handle, 4 * 1024, 20, "gpio", task_gpio_why, NULL, 128);
}
