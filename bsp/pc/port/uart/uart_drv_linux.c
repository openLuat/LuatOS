#include <stdlib.h>
#include <string.h>//add for memset
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_uart_drv.h"
#include "luat_msgbus.h"

#ifdef LUA_USE_LINUX

#define LUAT_LOG_TAG "uart.nop"
#include "luat_log.h"

#include "uv.h"
#include "luat_pcconf.h"


#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>

#include <sys/select.h>
#include <sys/ioctl.h>
#include <termios.h>

enum serial_error_code {
    SERIAL_ERROR_ARG            = -1, /* Invalid arguments */
    SERIAL_ERROR_OPEN           = -2, /* Opening serial port */
    SERIAL_ERROR_QUERY          = -3, /* Querying serial port attributes */
    SERIAL_ERROR_CONFIGURE      = -4, /* Configuring serial port attributes */
    SERIAL_ERROR_IO             = -5, /* Reading/writing serial port */
    SERIAL_ERROR_CLOSE          = -6, /* Closing serial port */
};

typedef enum serial_parity {
    PARITY_NONE,
    PARITY_ODD,
    PARITY_EVEN,
} serial_parity_t;

typedef struct serial_handle serial_t;

/* Primary Functions */
serial_t *serial_new(void);
static int serial_open_advanced(serial_t *serial, const char *path,
                         uint32_t baudrate, unsigned int databits,
                         serial_parity_t parity, unsigned int stopbits,
                         bool xonxoff, bool rtscts);
int serial_read(serial_t *serial, uint8_t *buf, size_t len, int timeout_ms);
int serial_write(serial_t *serial, const uint8_t *buf, size_t len);
int serial_close(serial_t *serial);
void serial_free(serial_t *serial);


struct serial_handle {
    int fd;
};

static int _serial_error(serial_t *serial, int code, int c_errno, const char *fmt, ...) {

    return code;
}

serial_t *serial_new(void) {
    serial_t *serial = calloc(1, sizeof(serial_t));
    if (serial == NULL)
        return NULL;

    serial->fd = -1;

    return serial;
}

void serial_free(serial_t *serial) {
    free(serial);
}

static int _serial_baudrate_to_bits(uint32_t baudrate) {
    switch (baudrate) {
        case 50: return B50;
        case 75: return B75;
        case 110: return B110;
        case 134: return B134;
        case 150: return B150;
        case 200: return B200;
        case 300: return B300;
        case 600: return B600;
        case 1200: return B1200;
        case 1800: return B1800;
        case 2400: return B2400;
        case 4800: return B4800;
        case 9600: return B9600;
        case 19200: return B19200;
        case 38400: return B38400;
        case 57600: return B57600;
        case 115200: return B115200;
        case 230400: return B230400;
        case 460800: return B460800;
        case 500000: return B500000;
        case 576000: return B576000;
        case 921600: return B921600;
        case 1000000: return B1000000;
        case 1152000: return B1152000;
        case 1500000: return B1500000;
        case 2000000: return B2000000;
#ifdef B2500000
        case 2500000: return B2500000;
#endif
#ifdef B3000000
        case 3000000: return B3000000;
#endif
#ifdef B3500000
        case 3500000: return B3500000;
#endif
#ifdef B4000000
        case 4000000: return B4000000;
#endif
        default: return -1;
    }
}

static int serial_open_advanced(serial_t *serial, const char *path, uint32_t baudrate, unsigned int databits, serial_parity_t parity, unsigned int stopbits, bool xonxoff, bool rtscts) {
    struct termios termios_settings;

    /* Validate args */
    if (databits != 5 && databits != 6 && databits != 7 && databits != 8)
        return _serial_error(serial, SERIAL_ERROR_ARG, 0, "Invalid data bits (can be 5,6,7,8)");
    if (parity != PARITY_NONE && parity != PARITY_ODD && parity != PARITY_EVEN)
        return _serial_error(serial, SERIAL_ERROR_ARG, 0, "Invalid parity (can be PARITY_NONE,PARITY_ODD,PARITY_EVEN)");
    if (stopbits != 1 && stopbits != 2)
        return _serial_error(serial, SERIAL_ERROR_ARG, 0, "Invalid stop bits (can be 1,2)");

    memset(serial, 0, sizeof(serial_t));

    /* Open serial port */
    if ((serial->fd = open(path, O_RDWR | O_NOCTTY)) < 0)
        return _serial_error(serial, SERIAL_ERROR_OPEN, errno, "Opening serial port \"%s\"", path);

    memset(&termios_settings, 0, sizeof(termios_settings));

    /* c_iflag */

    /* Ignore break characters */
    termios_settings.c_iflag = IGNBRK;
    if (parity != PARITY_NONE)
        termios_settings.c_iflag |= INPCK;
    /* Only use ISTRIP when less than 8 bits as it strips the 8th bit */
    if (parity != PARITY_NONE && databits != 8)
        termios_settings.c_iflag |= ISTRIP;
    if (xonxoff)
        termios_settings.c_iflag |= (IXON | IXOFF);

    /* c_oflag */
    termios_settings.c_oflag = 0;

    /* c_lflag */
    termios_settings.c_lflag = 0;

    /* c_cflag */
    /* Enable receiver, ignore modem control lines */
    termios_settings.c_cflag = CREAD | CLOCAL;

    /* Databits */
    if (databits == 5)
        termios_settings.c_cflag |= CS5;
    else if (databits == 6)
        termios_settings.c_cflag |= CS6;
    else if (databits == 7)
        termios_settings.c_cflag |= CS7;
    else if (databits == 8)
        termios_settings.c_cflag |= CS8;

    /* Parity */
    if (parity == PARITY_EVEN)
        termios_settings.c_cflag |= PARENB;
    else if (parity == PARITY_ODD)
        termios_settings.c_cflag |= (PARENB | PARODD);

    /* Stopbits */
    if (stopbits == 2)
        termios_settings.c_cflag |= CSTOPB;

    /* RTS/CTS */
    if (rtscts)
        termios_settings.c_cflag |= CRTSCTS;

    /* Baudrate */
    cfsetispeed(&termios_settings, _serial_baudrate_to_bits(baudrate));
    cfsetospeed(&termios_settings, _serial_baudrate_to_bits(baudrate));

    /* Set termios attributes */
    if (tcsetattr(serial->fd, TCSANOW, &termios_settings) < 0) {
        int errsv = errno;
        close(serial->fd);
        serial->fd = -1;
        return _serial_error(serial, SERIAL_ERROR_CONFIGURE, errsv, "Setting serial port attributes");
    }
    return 0;
}

int serial_write(serial_t *serial, const uint8_t *buf, size_t len) {
    ssize_t ret;

    if ((ret = write(serial->fd, buf, len)) < 0)
        return _serial_error(serial, SERIAL_ERROR_IO, errno, "Writing serial port");

    return ret;
}
int serial_close(serial_t *serial) {
    if (serial->fd < 0)
        return 0;

    if (close(serial->fd) < 0)
        return _serial_error(serial, SERIAL_ERROR_CLOSE, errno, "Closing serial port");

    serial->fd = -1;

    return 0;
}

extern uv_loop_t *main_loop;

typedef struct {
    uv_poll_t poll_handle;
    //uv_write_t write_req;
    serial_t serial;
    char* recv_buff;
    size_t recv_len;
    //uv_pipe_t stream;
    bool initialized;
    char devPath[32];

} SerialPort;

static SerialPort serial[8]={0}; //最多8个串口


static void read_callback(uv_poll_t* handle, int status, int events) {
    if (status < 0) {
        // 监听出错（如 fd 关闭），处理错误
        return;
    }
    // 检查是否是“可读”事件（与启动监听时的类型对应）
    if (events & UV_READABLE) {
        char buf[512];
        ssize_t nread = read(handle->io_watcher.fd, buf, sizeof(buf)); 
        if (nread > 0) {
            int uart_id = (int)handle->data;  // 转换回整数

            size_t newsize = serial[uart_id].recv_len + nread;
            if (serial[uart_id].recv_buff == NULL) {
                serial[uart_id].recv_buff = luat_heap_malloc(nread);
                serial[uart_id].recv_len = nread;
                memcpy(serial[uart_id].recv_buff, buf, nread);
            }
            else {
                void* ptr = luat_heap_realloc(serial[uart_id].recv_buff, newsize);
                if (ptr == NULL) {
                    LLOGE("overflow when uart recv");
                    return;
                }
                serial[uart_id].recv_buff = ptr;
                memcpy(serial[uart_id].recv_buff + serial[uart_id].recv_len, buf, nread);
            }
            rtos_msg_t msg = {
                .handler = l_uart_handler,
                .arg1 = uart_id,
                .arg2 = nread
            };
            luat_msgbus_put(&msg, 0);
        } else if (nread == 0) {
            // 串口关闭（如设备断开），可停止监听
            uv_poll_stop(handle);
        }
    }
}

static int uart_setup_nop(void* userdata, luat_uart_t* uart) {

    if (uart->id < 0 || uart->id >= 8) {
        LLOGD("Invalid UART ID: %d", uart->id);
        return -1;
    }
    SerialPort* sp = &serial[uart->id];
    // 避免重复初始化  
    if (sp->initialized) {
        LLOGD("UART %d already initialized", uart->id);
        return -1;
    }
    // if (strlen(sp->devPath)==0) {
    //     LLOGD("UART %d not initialized", uart->id);
    //     return -1;
    // }
    uint16_t parity=PARITY_NONE;
    if(uart->parity==1){
        parity=PARITY_ODD;
    }else if(uart->parity==2){
        parity=PARITY_EVEN;
    }else if(uart->parity==0){
        parity=PARITY_NONE;//"/dev/ttyAMA0"
    }
    // 初始化串口
   
    if (serial_open_advanced(&sp->serial,sp->devPath ,uart->baud_rate, uart->data_bits, parity, uart->stop_bits, false, false) < 0) {
        return -1;
    }
    const char *parity_[3] = {"ODD", "EVEN", "NONE"};
    printf("初始化 uart %d,fd:%d,path:%s,%d,%s\r\n", uart->id,sp->serial.fd,sp->devPath,uart->baud_rate,parity_[parity]); 
    // 初始化UV轮询
    int r = uv_poll_init(main_loop, &sp->poll_handle, sp->serial.fd);
    if (r != 0) {
        LLOGD("uv_poll_init failed: %s", uv_strerror(r));
        serial_close(&sp->serial);
        return -1;
    } 
    r = uv_poll_start(&sp->poll_handle, UV_READABLE, read_callback);
    if (r != 0) {
        LLOGD("uv_poll_start failed: %s", uv_strerror(r));
        uv_poll_stop(&sp->poll_handle);
        serial_close(&sp->serial);
        return -1;
    }
    sp->poll_handle.data = (void*)uart->id;;
    // // 初始化uv_pipe_t
    // r = uv_pipe_init(main_loop, &sp->stream, 1);
    // if (r) {
    //     LLOGD("uv_pipe_init failed: %s", uv_strerror(r));
    //     uv_poll_stop(&sp->poll_handle);
    //     serial_close(&sp->serial);
    //     return -1;
    // }
    // // 将串口文件描述符附加到uv_pipe_t
    // r = uv_pipe_open(&sp->stream, sp->serial.fd);
    // if (r) {
    //     LLOGD("uv_pipe_open failed: %s", uv_strerror(r));
    //     uv_poll_stop(&sp->poll_handle);
    //     serial_close(&sp->serial);
    //     return -1;
    // }
    
    sp->initialized = true;
    return 0;

}

static int uart_write_nop(void* userdata, int uart_id, void* data, size_t length) {
    if (uart_id < 0 || uart_id >= 8) {
        return -1;
    }
    SerialPort* sp = &serial[uart_id];
    if (!sp->initialized) {
        memset(sp, 0, sizeof(SerialPort));
        memcpy(sp->devPath,data,length);
        printf("UART %d get fd: %s\r\n", uart_id,sp->devPath);
        return -1;
    }
    if (serial_write(&sp->serial, data, length) < 0) {
        return -1;
    }
    return 0;
}

static int uart_read_nop(void* userdata, int uart_id, void* buffer, size_t length) {

    if (uart_id < 0 || uart_id >= 8) {
        return -1;
    }
    SerialPort* sp = &serial[uart_id];
    if (sp->initialized == false) {
        return -1;
    }
    if (sp->recv_len == 0) {
        return -1;
    }
    if (length > sp->recv_len) {
        length = sp->recv_len;
    }
    memcpy(buffer,sp->recv_buff, length);
    if (sp->recv_len > length) {
        size_t newsize = sp->recv_len - length;
        memmove(sp->recv_buff, sp->recv_buff + sp->recv_len, newsize);
        void* ptr = luat_heap_realloc(sp->recv_buff, newsize);
        sp->recv_buff = ptr;
        sp->recv_len = newsize;
    }
    else {
        luat_heap_free(sp->recv_buff);
        sp->recv_buff = NULL;
        sp->recv_len = 0;
    }
    return length;
}

static int uart_close_nop(void* userdata, int uart_id) {
    if (uart_id < 0 || uart_id >= 8) {
        return -1;
    }
    SerialPort* sp = &serial[uart_id];
    if (sp->initialized==false) {
        return -1;
    }
    serial_close(&sp->serial);
    serial_free(&sp->serial);
    uv_poll_stop(&sp->poll_handle); 
    memset(sp, 0, sizeof(SerialPort));
    return 0;
}


const luat_uart_drv_opts_t uart_linux = {
    .setup = uart_setup_nop,
    .write = uart_write_nop,
    .read = uart_read_nop,
    .close = uart_close_nop,
};

#endif
