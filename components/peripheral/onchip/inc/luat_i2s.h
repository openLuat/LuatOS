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
    uint8_t mclk;
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

#endif
