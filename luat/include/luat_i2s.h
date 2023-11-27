#ifndef LUAT_I2S_H
#define LUAT_I2S_H 

typedef struct luat_i2s_conf
{
    uint8_t id;
    uint8_t mode;
    uint32_t sample_rate;
    uint8_t bits_per_sample;
    uint8_t channel_format;
    uint8_t communication_format;
    uint32_t mclk;
    //uint8_t intr_alloc_flags;
    // uint8_t dma_buf_count;
    // uint8_t dma_buf_len;
    // uint8_t use_apll;
    // uint8_t tx_desc_auto_clear;
}luat_i2s_conf_t;

int luat_i2s_setup(luat_i2s_conf_t *conf);
int luat_i2s_send(uint8_t id, char* buff, size_t len);
int luat_i2s_recv(uint8_t id, char* buff, size_t len);
int luat_i2s_close(uint8_t id);
int32_t luat_i2s_rx_cb(void *pdata, void *param);

int luat_i2s_tx_stat(uint8_t id, size_t *buffsize, size_t* remain);

//csdk专用
void luat_i2s_init(void);
void luat_i2s_base_setup(uint8_t bus_id, uint8_t mode,  uint8_t frame_size);
void luat_i2s_set_lr_channel(uint8_t bus_id, uint8_t lr_channel);
int luat_i2s_start(uint8_t bus_id, uint8_t is_play, uint32_t sample, uint8_t channel_num);
int luat_i2s_transfer_start(uint8_t bus_id, uint32_t sample, uint8_t channel_num, uint32_t byte_len, void *cb, void *param);
void luat_i2s_no_block_tx(uint8_t bus_id, uint8_t* address, uint32_t byte_len, void * cb, void *param);
void luat_i2s_no_block_rx(uint8_t bus_id, uint32_t byte_len, void *cb, void *param);
void luat_i2s_tx_stop(uint8_t bus_id);
void luat_i2s_rx_stop(uint8_t bus_id);
void luat_i2s_deinit(uint8_t bus_id);
void luat_i2s_pause(uint8_t bus_id);
void luat_i2s_transfer(uint8_t bus_id, uint8_t* address, uint32_t byte_len);
void luat_i2s_transfer_stop(uint8_t bus_id);
#endif
