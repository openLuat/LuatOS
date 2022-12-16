/*
 * This file is part of the Serial Flash Universal Driver Library.
 *
 * Copyright (c) 2016-2018, Armink, <armink.ztl@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * 'Software'), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * Function: Portable interface for each platform.
 * Created on: 2016-04-23
 */

#include <sfud.h>
#include <stdarg.h>

#include "luat_spi.h"

#define LUAT_LOG_TAG "sfud"
#include "luat_log.h"



// void sfud_log_debug(const char *file, const long line, const char *format, ...);

/**
 * SPI write data then read data
 */
static sfud_err spi_write_read(const sfud_spi *spi, const uint8_t *write_buf, size_t write_size, uint8_t *read_buf,
        size_t read_size) {
    sfud_err result = SFUD_SUCCESS;
    if (write_size) {
        SFUD_ASSERT(write_buf);
    }
    if (read_size) {
        SFUD_ASSERT(read_buf);
    }
    int type = (*(luat_sfud_flash_t*)(spi->user_data)).luat_spi;
    if ( type == 0 ) {
        luat_spi_t* spi_flash = (luat_spi_t*) ((*(luat_sfud_flash_t*)(spi->user_data)).user_data);
        if (write_size && read_size) {
            if (luat_spi_transfer(spi_flash -> id, (const char*)write_buf, write_size, (char*)read_buf, read_size) <= 0) {
                result = SFUD_ERR_TIMEOUT;
            }
        } else if (write_size) {
            if (luat_spi_send(spi_flash -> id,  (const char*)write_buf, write_size) <= 0) {
                result = SFUD_ERR_WRITE;
            }
        } else {
            if (luat_spi_recv(spi_flash -> id, (char*)read_buf, read_size) <= 0) {
                result = SFUD_ERR_READ;
            }
        }
    }
    else if ( type == 1 ) {
        luat_spi_device_t* spi_dev = (luat_spi_device_t*) ((*(luat_sfud_flash_t*)(spi->user_data)).user_data);
        if (write_size && read_size) {
            if (luat_spi_device_transfer(spi_dev , (const char*)write_buf, write_size, (char*)read_buf, read_size) <= 0) {
                result = SFUD_ERR_TIMEOUT;
            }
        } else if (write_size) {
            if (luat_spi_device_send(spi_dev ,  (const char*)write_buf, write_size) <= 0) {
                result = SFUD_ERR_WRITE;
            }
        } else {
            if (luat_spi_device_recv(spi_dev , (char*)read_buf, read_size) <= 0) {
                result = SFUD_ERR_READ;
            }
        }
    }
    return result;
}

#ifdef SFUD_USING_QSPI
/**
 * read flash data by QSPI
 */
static sfud_err qspi_read(const struct __sfud_spi *spi, uint32_t addr, sfud_qspi_read_cmd_format *qspi_read_cmd_format,
        uint8_t *read_buf, size_t read_size) {
    sfud_err result = SFUD_SUCCESS;

    /**
     * add your qspi read flash data code
     */

    return result;
}
#endif /* SFUD_USING_QSPI */

/* about 100 microsecond delay */
static void retry_delay_100us(void) {
    uint32_t delay = 120;
    while(delay--);
}

sfud_err sfud_spi_port_init(sfud_flash *flash) {
    sfud_err result = SFUD_SUCCESS;

    extern luat_sfud_flash_t luat_sfud;
    /* port SPI device interface */
    flash->spi.wr = spi_write_read;
    // flash->spi.user_data = flash;
    flash->spi.user_data = &luat_sfud;
    /* 100 microsecond delay */
    flash->retry.delay = retry_delay_100us;
    /* 60 seconds timeout */
    flash->retry.times = 60 * 10000;

    flash->name = "LuatOS-sfud";

    return result;
}

// /**
//  * This function is print debug info.
//  *
//  * @param file the file which has call this function
//  * @param line the line number which has call this function
//  * @param format output format
//  * @param ... args
//  */
// void sfud_log_debug(const char *file, const long line, const char *format, ...) {
//     char log_buf[256] = {0};
//     va_list args;

//     /* args point to the first variable parameter */
//     va_start(args, format);
//     // printf("[SFUD](%s:%ld) ", file, line);
//     /* must use vprintf to print */
//     vsnprintf(log_buf, sizeof(log_buf), format, args);
//     // printf("%s\n", log_buf);
//     LLOGD("%s ", log_buf);
//     va_end(args);
// }

// /**
//  * This function is print routine info.
//  *
//  * @param format output format
//  * @param ... args
//  */
// void sfud_log_info(const char *format, ...) {
//     char log_buf[256] = {0};
//     va_list args;

//     /* args point to the first variable parameter */
//     va_start(args, format);
//     // printf("[SFUD]");
//     /* must use vprintf to print */
//     vsnprintf(log_buf, sizeof(log_buf), format, args);
//     // printf("%s\n", log_buf);
//     LLOGD("%s ", log_buf);
//     va_end(args);
// }
