#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_airlink_fota.h"

#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#define TEST_BUFF_SIZE (4096)

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

#ifndef __USER_FUNC_IN_RAM__
#define __USER_FUNC_IN_RAM__
#endif

extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_pause;

static luat_rtos_task_handle g_uart_task;
static luat_rtos_queue_t evt_queue;
extern luat_airlink_irq_ctx_t g_airlink_irq_ctx;


__USER_FUNC_IN_RAM__ static void on_newdata_notify(void)
{
    luat_event_t evt = {.id = 3};
    luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
}

static void uart_cb(int uart_id, uint32_t data_len) {
    luat_event_t evt = {.id = 2};
    luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
}

static void uart_gpio_setup(void)
{
    int ret = 0;
    if (g_airlink_spi_conf.uart_id == 0) {
        g_airlink_spi_conf.uart_id = 1;
    }
    ret = luat_uart_ctrl(g_airlink_spi_conf.uart_id, LUAT_UART_SET_RECV_CALLBACK, uart_cb);
    if (ret) {
        LLOGW("luat_uart_ctrl ret:%d", ret);
    }
}

__USER_FUNC_IN_RAM__ static void record_statistic(luat_event_t event)
{
    switch (event.id)
    {
    case 0:
        g_airlink_statistic.event_timeout.total++;
        break;
    case 2:
        g_airlink_statistic.event_rdy_irq.total++;
        break;
    case 3:
        g_airlink_statistic.event_new_data.total++;
        break;
    default:
        break;
    }
}

static uint8_t *s_txbuff;
static uint8_t *s_rxbuff;
static airlink_link_data_t s_link;

__USER_FUNC_IN_RAM__ static void on_link_data_notify(airlink_link_data_t* link) {
    memset(&link->flags, 0, sizeof(uint32_t));
    if (g_airlink_irq_ctx.enable) {
        link->flags.irq_ready = 1;
        link->flags.irq_pin = g_airlink_irq_ctx.slave_pin - 140;
    }
}

size_t get_real_len(uint8_t hex_low,uint8_t hex_high)
{
    size_t len = 0;
    len = (hex_high << 8) + hex_low;
    // LLOGD("len = %d",len);
    return len;

}

static void parse_data(uint8_t* buff, size_t len)
{
    luat_airlink_print_buff("反转义前的数据", buff,  len);
    // 收到数据后去除帧头帧尾和魔数，遇到0x7E/0x7D 要转义
    uint8_t* parse_buff = buff;
    size_t parse_len = len - 2;
    memcpy(parse_buff, buff+1, parse_len);//去帧头帧尾
    // //反转义
    for(int i = 0; i < parse_len; i++)
    {
        if(parse_buff[i] == 0x7D && parse_buff[i + 1] == 0x02) {
            parse_buff[i] = 0x7E;
            parse_len--;
        }
        else if(parse_buff[i] == 0x7D && parse_buff[i + 1] == 0x01) {
            parse_buff[i] = 0x7D;
            parse_len--;
        }
    }
    airlink_link_data_t *link = luat_airlink_data_unpack(parse_buff, parse_len);
    if (link == NULL) 
    {
        LLOGE("luat_airlink_data_unpack failed len %d", parse_len);
        return;
    }
    // LLOGD("luat_airlink data unpacked, len: %d, data: %p", link->len, link->data);
    luat_airlink_on_data_recv(link->data, link->len);
}

#if 0
static void on_uart_data_in(uint8_t* buff, size_t len) 
{
    // TODO 要处理分包, 连包的情况
    // TODO 不能假设开头和结尾就一定是0x7E, 要查找, 要缓存
    // 收到数据后去除帧头帧尾和魔数，遇到0x7E/0x7D 要转义
    uint8_t* receive_data = buff;
    uint32_t pos = 0;
    uint32_t frame_start = 0;
    uint32_t frame_end = 0,temp_frame_end = 0;
    size_t receive_len = len;// - 2;
    size_t data_len = 0;
    static size_t half_data_len = 0;
    static size_t temp_half_data_len = 0;
    static uint8_t parse_state = 0;
    uint8_t count = 0;
    uint8_t parse_data_buff[TEST_BUFF_SIZE];
    // LLOGD("receive_len:%d,len=%d",receive_len,len);
    // for(uint8_t i = 0; i < receive_len; i++)
    // {
    //     LLOGD("receive_data[%d]: %02x", i, receive_data[i]);
    // }
    //先查找完整的一组数据包，然后再解析
    //7E A1 B1 CA 66 0C 00 6B 62 00 00 00 00 00 00 00 00 20 00 08 00 7B 69 68 64 6C 6B 73 7D 7E
    while(pos < receive_len)
    {
        if(receive_data[pos] == 0x7E && receive_data[pos + 1] == 0xA1 && receive_data[pos + 2] == 0xB1 && receive_data[pos + 3] == 0xCA && receive_data[pos + 4] == 0x66) 
        {
            frame_start = pos;//找到帧头
            parse_state = 1;//
            // LLOGD("状态机parse_state = %d", parse_state);
            // LLOGD("找到帧头，frame_start = %d", frame_start);
            data_len = get_real_len(receive_data[frame_start + 5],receive_data[frame_start + 6]);//根据帧中数据获取长度,7E,7D
            // LLOGD("接收到的长度转换为十进制：%d", data_len);
            for(uint32_t i = pos + 17; i < receive_len ; i++) //帧头+魔数+数据长度+crc+id+flag（1+4+2+2+4+4=17）在剩余数据中查找帧尾
            {
                // LLOGD("正在寻找帧尾0x7E...");
                // LLOGD("receive_data[%d]: %02x", i, receive_data[i]);
                if(receive_data[i] == 0x7E) 
                {
                    uint32_t count = 0;
                    for(uint32_t i = frame_start; i < data_len + 18; i++)//遍历寻找转义次数
                    {
                        if(receive_data[i] == 0x7D && receive_data[i + 1] == 0x02) {
                            count++;
                        }
                        else if(receive_data[i] == 0x7D && receive_data[i + 1] == 0x01) {
                            count++;
                        }
                    }
                    temp_frame_end = i;//找到帧尾                    
                    // LLOGD("parse_state = 2,count = %d",count);
                    // LLOGD("找到帧头，frame_start = %d", frame_start);
                    // LLOGD("临时帧尾 = %d", temp_frame_end);
                    // LLOGD("接收到的长度转换为十进制：%d", data_len);
                    for(uint32_t j = 0; j < (data_len + count + 18 + 1); j++)
                        parse_data_buff[j] = receive_data[j + frame_start];
                    parse_data(parse_data_buff, (data_len + count + 18));
                    if((temp_frame_end - frame_start + 1 - count - 18) == data_len) //帧长度正确29-0+1-17=12
                    {
                        frame_end = temp_frame_end;
                        LLOGD("完整数据包");
                        LLOGD("count=%d",count);
                        pos = frame_end + 1;
                        break;  
                    }
                    else
                    {
                        parse_state = 6;//有帧头帧尾，长度不对，舍弃
                        // LLOGD("找到帧头,frame_start = %d", frame_start);
                        // LLOGD("count=%d", count);
                        // LLOGD("临时帧尾 = %d", temp_frame_end);
                        // LLOGD("接收到的长度转换为：%d", data_len);
                        LLOGD("有帧头帧尾，长度不对，舍弃");
                        pos = temp_frame_end + count + 1;//重新判断帧头
                        break;
                    }
                }
                else//找到帧头，但是没有帧尾，数据不完整，先缓存
                {
                    if(i == receive_len - 1)//直到最后一个字节都没有找到帧尾，数据不完整，先缓存
                    {
                        uint32_t count = 0;
                        for(uint32_t j = frame_start; j < receive_len; j++)//遍历寻找转义次数
                        {
                            if(receive_data[j] == 0x7D && receive_data[j + 1] == 0x02) {
                                count++;
                            }
                            else if(receive_data[j] == 0x7D && receive_data[j + 1] == 0x01) {
                                count++;
                            }
                        }
                        parse_state = 5;//帧残缺
                        half_data_len = data_len + 17 + 1;//缓存了半帧，记录应有总长度
                        temp_half_data_len = receive_len - frame_start - count;//缓存了半帧，记录现有长度
                        for(uint32_t j = 0; j < temp_half_data_len + count; j++)
                            parse_data_buff[j] = receive_data[j + frame_start];//[0,receive_len-1]
                        LLOGD("parse_state = 5,前半帧count = %d",count);
                        LLOGD("半帧数据应有长度=%d", half_data_len);
                        LLOGD("半帧数据现有长度=%d", temp_half_data_len);
                        LLOGD("有帧头没有帧尾，数据不完整，先缓存");
                        pos = receive_len;
                        // LLOGD("状态机parse_state = %d", parse_state);
                        break;
                    }
                }
            }//for
        }
        else//pos未找到帧头，继续查找
        {
            if(parse_state == 5)
            {
                //缓存了半帧
                // LLOGD("状态机parse_state = %d", parse_state);
                for(uint32_t i = 0; i < receive_len; i++) //帧头+魔数+数据长度+crc+id+flag（1+4+2+2+4+4=17）
                {
                    if(receive_data[i] == 0x7E) 
                    {
                        temp_frame_end = i;//找到帧尾
                        uint8_t count = 0;
                        for(uint32_t j = 0; j < temp_frame_end + 1; j++)
                        {
                            if(receive_data[j] == 0x7D && receive_data[j + 1] == 0x02) {
                                count++;
                            }
                            else if(receive_data[j] == 0x7D && receive_data[j + 1] == 0x01) {
                                count++;
                            }
                        }
                        LLOGD("parse_state = 5,后半帧count = %d",count);
                        LLOGD("后半帧数据,找到0x7e,位置 = %d", temp_frame_end);
                        LLOGD("前半帧长度 = %d", temp_half_data_len);
                        LLOGD("组合后的帧长度 = %d", half_data_len);
                        if((temp_frame_end + 1 + temp_half_data_len - count) == half_data_len) //帧长度正确，减掉转义多出来的数据长度
                        {
                            frame_end = temp_frame_end;
                            LLOGD("半包数据整合成功");
                            pos = temp_frame_end + count + 1;
                            for(uint32_t j = 0; j < frame_end + 1; j++)
                                parse_data_buff[j + temp_half_data_len] = receive_data[j];
                            parse_data(parse_data_buff, (half_data_len));
                        }
                        else
                        {
                            LLOGD("半包数据整合失败");
                            for(uint32_t j = 0; j < (temp_half_data_len + receive_len); j++)
                                parse_data_buff[j] = 0;
                            pos = receive_len;
                        }
                        parse_state = 0;
                        half_data_len = 0;
                        temp_half_data_len = 0;
                        break;//无论整合成功与失败都要跳出for循环，因为已经找到帧尾
                    }
                    else//parse_state=5且既没有帧头又没有帧尾
                    {
                        parse_state = 5;//帧依旧残缺
                        pos = receive_len;
                        uint8_t count = 0;
                        for(uint32_t j = 0; j < receive_len; j++)
                        {
                            if(receive_data[j] == 0x7D && receive_data[j + 1] == 0x02) {
                                count++;
                            }
                            else if(receive_data[j] == 0x7D && receive_data[j + 1] == 0x01) {
                                count++;
                            }
                        }
                        for(uint32_t j = 0; j < receive_len; j++)
                            parse_data_buff[temp_half_data_len + j] = receive_data[j];
                        temp_half_data_len = temp_half_data_len - count + receive_len;//实际长度要减去转义多出来的数据长度
                    }
                }
            }
            else
            {
                if(pos < receive_len - 1) pos++;
                else
                {
                    LLOGD("未找到帧头");
                    pos++;
                    // break;
                }
            }
        }//pos未找到帧头，继续查找
        // LLOGD("状态机parse_state = %d", parse_state);
        // LLOGD("pos = %d", pos);
        // luat_heap_free(pbuff);
    }//while

}
#endif

static void unpack_data(uint8_t* buff, size_t len)
{
    LLOGD("unpack_data: src len = %d", len);
    if (len < 2) {
        LLOGE("unpack_data: data too short");
        return; // 数据太短, 无法解析
    }
    // 存储最终数据到s_rxbuff
    uint8_t* unpacked_data = s_rxbuff;
    size_t unpacked_len = 0;
    for (size_t i = 0; i < len; i++) {
        if (buff[i] == 0x7D) {
            // 转义字符, 下一个字节是转义码
            if (i + 1 < len) {
                if (buff[i + 1] == 0x02) {
                    unpacked_data[unpacked_len++] = 0x7E; // 转义为0x7E
                } else if (buff[i + 1] == 0x01) {
                    unpacked_data[unpacked_len++] = 0x7D; // 转义为0x7D
                }
                i++; // 跳过下一个字节
            }
        } else {
            unpacked_data[unpacked_len++] = buff[i]; // 普通数据直接复制
        }
    }
    if (unpacked_len < sizeof(airlink_link_data_t)) {
        LLOGE("unpack_data: unpacked data too short, len %d", unpacked_len);
        return; // 解包后的数据太短, 无法解析
    }
    airlink_link_data_t *link = NULL;
    link = luat_airlink_data_unpack(unpacked_data, unpacked_len);
    if (link == NULL) {
        LLOGE("luat_airlink_data_unpack failed, unpacked_len %d", unpacked_len);
        return; // 解析失败
    }
    LLOGD("luat_airlink data unpacked, len: %d, data: %p", link->len, link->data);
    luat_airlink_on_data_recv(link->data, link->len);
}

#define UNPACK_BUFF_SIZE (8*1024)
static uint8_t* rxbuf;
static uint32_t rxoffset = 0;
void on_airlink_uart_data_in(uint8_t* buff, size_t len) 
{
    int ret = 0;
    size_t offset = 0;
    size_t end_offset = 0;
    // 首先, 输入的数据是否为0, 也可能是太长的数据
    if (len == 0) {
        return; // 不需要处理
    }
    if (rxbuf == NULL) {
        // 分配内存
        rxbuf = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);
        if (rxbuf == NULL) {
            LLOGE("无法分配内存给rxbuf");
            return; // 内存分配失败
        }
    }
    if (s_rxbuff == NULL) {
        // 分配内存给s_rxbuff
        s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);
        if (s_rxbuff == NULL) {
            LLOGE("无法分配内存给s_rxbuff");
            return; // 内存分配失败
        }
    }
    // 按协议要求, 单个包的最大长度, 应该是 2 + 1600*2 + 2 = 3206 字节
    // 所以, 8k完全可以放入2个包
    memcpy(rxbuf + rxoffset, buff, len);
    rxoffset += len;

    // 首先, 检查首个字节是不是0x7E, 如果不是, 那么就需要查找包头, 直至找到0x7E
    if (rxbuf[0] != 0x7E) {
        offset = 1;
        // 如果不是, 那么就需要查找包头, 直至找到0x7E
        while (offset < rxoffset && rxbuf[offset] != 0x7E) {
            offset++;
        }
        if (offset >= rxoffset) {
            LLOGW("没有找到包头, 清空当前数据, 等待下次数据 %d", rxoffset);
            rxoffset = 0;
            return;
        }
        // 找到包头, 移动数据到前面
        if (offset > 1) {
            memmove(rxbuf, rxbuf + offset, rxoffset - offset);
            rxoffset -= offset;
        }
    }

    offset = 0;
    while (rxoffset - offset >= 2) {
        // 搜索包头
        if (rxbuf[offset] == 0x7E) {
            // 找到包头, 继续查找包尾
            end_offset = offset + 1;
            while (end_offset < rxoffset && rxbuf[end_offset] != 0x7E) {
                end_offset++;
            }
            if (end_offset >= rxoffset) {
                // 没有找到包尾, 等待下次数据
                break;
            }
            // 找到包尾, 解析数据
            size_t data_len = end_offset - offset - 1; // 包头和包尾不算在内
            // 反转义数据
            if (data_len > 1) {
                unpack_data(rxbuf + offset + 1, data_len); // 包头和包尾不算在内
            }
            // 移动剩余数据到前面
            memmove(rxbuf, rxbuf + end_offset + 1, rxoffset - end_offset - 1);
            rxoffset -= (end_offset + 1 - offset);
        } else {
            // 没有找到包头, 移动一个字节
            offset++;
        }
    }
}

__USER_FUNC_IN_RAM__ static void uart_task(void *param)
{
    int ret;
    luat_event_t event = {0};
    airlink_queue_item_t item = {0};
    uint8_t* ptr = NULL;
    size_t offset = 0;
    int uart_id;
    luat_rtos_task_sleep(5); // 等5ms
    uart_gpio_setup();
    g_airlink_newdata_notify_cb = on_newdata_notify;
    g_airlink_link_data_cb = on_link_data_notify;
    // 单个link data的长度最大是1600字节,极端情况下所有数据都要转义,那就是3200字节,所以这里预留4K
    uint8_t *pbuff = luat_heap_malloc(4*1024);
    while (1)
    {
        uart_id = g_airlink_spi_conf.uart_id;
        // LLOGD("uart_task:uart_id:%d", uart_id);
        while (1) {
            ret = luat_uart_read(uart_id, (char *)s_rxbuff, 1024);
            // LLOGD("uart_task:uart read buff len:%d", ret);
            if (ret <= 0) 
            {
                break;
            }
            else 
            {
                LLOGD("收到uart数据长度 %d", ret);
                // luat_airlink_print_buff("uart_task:uart read buff", s_rxbuff, ret);
                // 推送数据, 并解析处理
                on_airlink_uart_data_in(s_rxbuff, ret);
                // for(uint8_t j = 0; j < ret; j++)
                // {
                //     LLOGD("收到数据:%02x", s_rxbuff[j]);
                // }
            }
        }
        event.id = 0;
        ret = luat_rtos_queue_recv(evt_queue, &event, sizeof(luat_event_t), 15*1000);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        //LLOGD("收到airlink数据事件 ret:%d, id:%d", ret, event.id);
        record_statistic(event);
        while (1) {
            // 有数据, 要处理了
            item.len = 0;
            luat_airlink_cmd_recv_simple(&item);//从（发送）队列里取出数据存在item中
            // LLOGD("队列数据长度:%d, cmd:%p", item.len, item.cmd);
            if (item.len > 0 && item.cmd != NULL)
            {
                // 0x7E 开始, 0x7D 结束, 遇到 0x7E/0x7D 要转义
                luat_airlink_data_pack((uint8_t*)item.cmd, item.len, pbuff);
                // int temp_len = sizeof(pbuff)/sizeof(pbuff[0]);
                s_txbuff[0] = 0x7E;
                offset = 1;
                ptr = (uint8_t*)pbuff;
                for (size_t i = 0; i < item.len + sizeof(airlink_link_data_t); i++)
                {
                    if (ptr[i] == 0x7E) {
                        s_txbuff[offset++] = 0x7D;
                        s_txbuff[offset++] = 0x02;
                    }
                    else if (ptr[i] == 0x7D) {
                        s_txbuff[offset++] = 0x7D;
                        s_txbuff[offset++] = 0x01;
                    }
                    else
                    {
                        s_txbuff[offset++] = ptr[i];
                    }
                }
                s_txbuff[offset++] = 0x7E;
                //LLOGD("发送数据长度:%d, cmd:%p", offset, item.cmd);
                luat_uart_write(uart_id, (const char *)s_txbuff, offset);
                LLOGD ("发送数据长度:%d", offset);
                // for(uint8_t i = 0; i < offset; i++)
                // {
                //     LLOGD("发送数据:%02x", s_txbuff[i]);
                // }
                // luat_airlink_print_buff("uart_task:uart transfer buff", s_txbuff, offset);
            }
            else {
                break; // 没有数据了, 退出循环
            }
        }
    }
}

void luat_airlink_start_uart(void)
{
    int ret = 0;
    if (g_uart_task != NULL)
    {
        // TODO 支持多个UART?
        LLOGE("UART任务已经启动过了!!! uart %d", g_airlink_spi_conf.uart_id);
        return;
    }

    s_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    rxbuf = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);

    ret = luat_rtos_queue_create(&evt_queue, 4 * 1024, sizeof(luat_event_t));
    if (ret) {
        LLOGW("创建evt_queue ret:%d", ret);
    }
    ret = luat_rtos_task_create(&g_uart_task, 8 * 1024, 50, "uart", uart_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_task ret:%d", ret);
    }
}
