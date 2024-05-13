#ifndef LUAT_I2S_H
#define LUAT_I2S_H 

enum {
    LUAT_I2S_MODE_MASTER = 0,   // 主机模式
    LUAT_I2S_MODE_SLAVE,        // 从机模式

    LUAT_I2S_MODE_I2S = 0,      // I2S 标准
    LUAT_I2S_MODE_LSB,          // LSB 标准
    LUAT_I2S_MODE_MSB,          // MSB 标准
    LUAT_I2S_MODE_PCMS,         // PCM 短帧标准
    LUAT_I2S_MODE_PCML,         // PCM 长帧标准

    LUAT_I2S_CHANNEL_LEFT = 0,  // 左声道
    LUAT_I2S_CHANNEL_RIGHT,     // 右声道
    LUAT_I2S_CHANNEL_STEREO,    // 立体声

    LUAT_I2S_BITS_16 = 16,      // 16位数据
    LUAT_I2S_BITS_24 = 24,      // 24位数据
    LUAT_I2S_BITS_32 = 32,      // 32位数据

    LUAT_I2S_HZ_8k  = 8000,     // i2s 8kHz采样率
    LUAT_I2S_HZ_11k = 11000,    // i2s 11kHz采样率
    LUAT_I2S_HZ_16k = 16000,    // i2s 16kHz采样率
    LUAT_I2S_HZ_22k = 22050,    // i2s 22.05kHz采样率
    LUAT_I2S_HZ_32k = 32000,    // i2s 32kHz采样率
    LUAT_I2S_HZ_44k = 44100,    // i2s 44.1kHz采样率
    LUAT_I2S_HZ_48k = 48000,    // i2s 48kHz采样率
    LUAT_I2S_HZ_96k = 96000,    // i2s 96kHz采样率

    LUAT_I2S_STATE_STOP = 0,    // i2s停止状态
    LUAT_I2S_STATE_RUNING,      // i2s传输状态
};

typedef enum {
    LUAT_I2S_EVENT_TX_DONE,
    LUAT_I2S_EVENT_TX_ERR,
    LUAT_I2S_EVENT_RX_DONE,
    LUAT_I2S_EVENT_RX_ERR,
    LUAT_I2S_EVENT_TRANSFER_DONE,
    LUAT_I2S_EVENT_TRANSFER_ERR,
} luat_i2s_event_t;

typedef struct luat_i2s_conf{
    uint8_t id;                                             // i2s id
    uint8_t mode;                                           // i2s模式
    uint8_t standard;                                       // i2s数据标准
    uint8_t channel_format;                                 // i2s声道格式
    uint8_t data_bits;                                      // i2s有效数据位数
    uint8_t channel_bits;                                   // i2s通道数据位数
    volatile uint8_t state;                                 // i2s状态
    uint8_t is_full_duplex;		                            // 是否全双工
    uint32_t sample_rate;                                   // i2s采样率  
    uint32_t cb_rx_len;                                     // 接收触发回调数据长度
    int (*luat_i2s_event_callback)(uint8_t id ,luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param); //  i2s回调函数
    void *userdata;                                         // 用户数据
}luat_i2s_conf_t;

// 配置
int luat_i2s_setup(const luat_i2s_conf_t *conf);                  // 初始化i2s
int luat_i2s_modify(uint8_t id,uint8_t channel_format,uint8_t data_bits,uint32_t sample_rate);      // 修改i2s配置(不会进行初始化操作,动态修改配置)
// 传输(异步接口)
int luat_i2s_send(uint8_t id, uint8_t* buff, size_t len);                                   //  i2s发送数据
int luat_i2s_recv(uint8_t id, uint8_t* buff, size_t len);                                   //  i2s接收数据
int luat_i2s_transfer(uint8_t id, uint8_t* txbuff, size_t len);                             //  i2s传输数据(全双工)
int luat_i2s_transfer_loop(uint8_t id, uint8_t* buff, uint32_t one_truck_byte_len, uint32_t total_trunk_cnt, uint8_t need_callback);   //  i2s循环传输数据(全双工)
// 控制
int luat_i2s_pause(uint8_t id);                 // i2s传输暂停
int luat_i2s_resume(uint8_t id);                // i2s传输恢复
int luat_i2s_close(uint8_t id);                 // i2s关闭

// 获取配置
luat_i2s_conf_t *luat_i2s_get_config(uint8_t id);

int luat_i2s_txbuff_info(uint8_t id, size_t *buffsize, size_t* remain);
int luat_i2s_rxbuff_info(uint8_t id, size_t *buffsize, size_t* remain);

int luat_i2s_set_user_data(uint8_t id, void *user_data);
#endif
