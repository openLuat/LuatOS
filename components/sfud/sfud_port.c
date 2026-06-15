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
#include "luat_rtos.h"
#define LUAT_LOG_TAG "sfud"
#include "luat_log.h"
// static char log_buf[256];

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
    if ( type == LUAT_TYPE_SPI ) {
        luat_spi_t* spi_flash = (luat_spi_t*) ((*(luat_sfud_flash_t*)(spi->user_data)).user_data);
        luat_spi_lock(spi_flash -> id);
        if (write_size && read_size) {
            /* msg-only 路径：[SEND, RECV] 半双工事务 */
            luat_spi_msg_t msgs[2] = {
                { .mode = LUAT_SPI_MSG_SEND, .buff = (uint8_t*)write_buf, .recv_buff = NULL, .len = write_size },
                { .mode = LUAT_SPI_MSG_RECV, .buff = (uint8_t*)read_buf,  .recv_buff = NULL, .len = read_size  },
            };
            LLOGD("sfud[bus=%d] trans_msgs SEND+RECV w=%u r=%u", spi_flash->id, (unsigned)write_size, (unsigned)read_size);
            int r = luat_spi_trans_msgs(spi_flash -> id, msgs, 2);
            if (r < 0) {
                LLOGE("sfud[bus=%d] trans_msgs SEND+RECV failed rc=%d", spi_flash->id, r);
                result = SFUD_ERR_TIMEOUT;
            }
        } else if (write_size) {
            luat_spi_msg_t msgs[1] = {
                { .mode = LUAT_SPI_MSG_SEND, .buff = (uint8_t*)write_buf, .recv_buff = NULL, .len = write_size },
            };
            LLOGD("sfud[bus=%d] trans_msgs SEND w=%u", spi_flash->id, (unsigned)write_size);
            int r = luat_spi_trans_msgs(spi_flash -> id, msgs, 1);
            if (r < 0) {
                LLOGE("sfud[bus=%d] trans_msgs SEND failed rc=%d", spi_flash->id, r);
                result = SFUD_ERR_WRITE;
            }
        } else {
            luat_spi_msg_t msgs[1] = {
                { .mode = LUAT_SPI_MSG_RECV, .buff = (uint8_t*)read_buf, .recv_buff = NULL, .len = read_size },
            };
            LLOGD("sfud[bus=%d] trans_msgs RECV r=%u", spi_flash->id, (unsigned)read_size);
            int r = luat_spi_trans_msgs(spi_flash -> id, msgs, 1);
            if (r < 0) {
                LLOGE("sfud[bus=%d] trans_msgs RECV failed rc=%d", spi_flash->id, r);
                result = SFUD_ERR_READ;
            }
        }
        luat_spi_unlock(spi_flash -> id);
    }
    else if ( type == LUAT_TYPE_SPI_DEVICE ) {
        luat_spi_device_t* spi_dev = (luat_spi_device_t*) ((*(luat_sfud_flash_t*)(spi->user_data)).user_data);
        if (write_size && read_size) {
            luat_spi_msg_t msgs[2] = {
                { .mode = LUAT_SPI_MSG_SEND, .buff = (uint8_t*)write_buf, .recv_buff = NULL, .len = write_size },
                { .mode = LUAT_SPI_MSG_RECV, .buff = (uint8_t*)read_buf,  .recv_buff = NULL, .len = read_size  },
            };
            LLOGD("sfud[dev] device_trans_msgs SEND+RECV w=%u r=%u", (unsigned)write_size, (unsigned)read_size);
            int r = luat_spi_device_trans_msgs(spi_dev, msgs, 2);
            if (r < 0) {
                LLOGE("sfud[dev] device_trans_msgs SEND+RECV failed rc=%d", r);
                result = SFUD_ERR_TIMEOUT;
            }
        } else if (write_size) {
            luat_spi_msg_t msgs[1] = {
                { .mode = LUAT_SPI_MSG_SEND, .buff = (uint8_t*)write_buf, .recv_buff = NULL, .len = write_size },
            };
            LLOGD("sfud[dev] device_trans_msgs SEND w=%u", (unsigned)write_size);
            int r = luat_spi_device_trans_msgs(spi_dev, msgs, 1);
            if (r < 0) {
                LLOGE("sfud[dev] device_trans_msgs SEND failed rc=%d", r);
                result = SFUD_ERR_WRITE;
            }
        } else {
            luat_spi_msg_t msgs[1] = {
                { .mode = LUAT_SPI_MSG_RECV, .buff = (uint8_t*)read_buf, .recv_buff = NULL, .len = read_size },
            };
            LLOGD("sfud[dev] device_trans_msgs RECV r=%u", (unsigned)read_size);
            int r = luat_spi_device_trans_msgs(spi_dev, msgs, 1);
            if (r < 0) {
                LLOGE("sfud[dev] device_trans_msgs RECV failed rc=%d", r);
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
static void retry_delay_1ms(void) {
    luat_rtos_task_sleep(1);
}
static void retry_delay_10ms(void) {
    luat_rtos_task_sleep(10);
}

static void luat_sfud_lock(const sfud_spi *spi)
{
    luat_sfud_flash_t *sfud_flash = (luat_sfud_flash_t*)(spi->user_data);
    luat_mutex_lock(sfud_flash->sem);
}

static void luat_sfud_unlock(const sfud_spi *spi)
{
    luat_sfud_flash_t *sfud_flash = (luat_sfud_flash_t*)(spi->user_data);
    luat_mutex_unlock(sfud_flash->sem);
}
sfud_err sfud_spi_port_init(sfud_flash *flash) {
    sfud_err result = SFUD_SUCCESS;

    /* port SPI device interface */
    flash->spi.wr = spi_write_read;
    flash->spi.user_data = &(flash->luat_sfud);
    flash->luat_sfud.sem = luat_mutex_create();
    flash->spi.lock = luat_sfud_lock;
    flash->spi.unlock = luat_sfud_unlock;
    flash->retry.delay = retry_delay_1ms;
    flash->retry.long_delay = retry_delay_10ms;
    flash->retry.times = 20;     /* write操作 20ms足够了 */
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
//     va_list args;

//     /* args point to the first variable parameter */
//     va_start(args, format);
//     printf("[SFUD](%s:%ld) ", file, line);
//     /* must use vprintf to print */
//     vsnprintf(log_buf, sizeof(log_buf), format, args);
//     printf("%s\n", log_buf);
//     va_end(args);
// }

// /**
//  * This function is print routine info.
//  *
//  * @param format output format
//  * @param ... args
//  */
// void sfud_log_info(const char *format, ...) {
//     va_list args;

//     /* args point to the first variable parameter */
//     va_start(args, format);
//     printf("[SFUD]");
//     /* must use vprintf to print */
//     vsnprintf(log_buf, sizeof(log_buf), format, args);
//     printf("%s\n", log_buf);
//     va_end(args);
// }
