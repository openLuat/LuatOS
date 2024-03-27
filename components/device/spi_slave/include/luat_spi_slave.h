#ifndef LUAT_SPI_SLAVE_H
#define LUAT_SPI_SLAVE_H

typedef struct luat_spi_slave_conf {
    uint8_t id;
}luat_spi_slave_conf_t;

int luat_spi_slave_open(luat_spi_slave_conf_t *conf);
int luat_spi_slave_close(luat_spi_slave_conf_t *conf);
int luat_spi_slave_read(luat_spi_slave_conf_t *conf, uint8_t* src, uint8_t* buf, size_t len);
int luat_spi_slave_write(luat_spi_slave_conf_t *conf, uint8_t* buf, size_t len);

int l_spi_slave_event(int id, int event, void* buff, size_t max_size);
int luat_spi_slave_writable(luat_spi_slave_conf_t *conf);

#endif
