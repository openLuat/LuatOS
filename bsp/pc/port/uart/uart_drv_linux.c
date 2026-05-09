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

#include "luat_posix_compat.h"
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

struct serial_handle {
    int fd;
};

static int _serial_error(serial_t *serial, int code, int c_errno, const char *fmt, ...) {
    (void)serial; (void)c_errno; (void)fmt;
    return code;
}

serial_t *serial_new(void) {
    serial_t *s = calloc(1, sizeof(serial_t));
    if (s == NULL) return NULL;
    s->fd = -1;
    return s;
}

void serial_free(serial_t *s) {
    free(s);
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

static int serial_open_advanced(serial_t *s, const char *path, uint32_t baudrate,
                                unsigned int databits, serial_parity_t parity,
                                unsigned int stopbits, bool xonxoff, bool rtscts) {
    struct termios termios_settings;

    if (databits != 5 && databits != 6 && databits != 7 && databits != 8)
        return _serial_error(s, SERIAL_ERROR_ARG, 0, "Invalid data bits");
    if (parity != PARITY_NONE && parity != PARITY_ODD && parity != PARITY_EVEN)
        return _serial_error(s, SERIAL_ERROR_ARG, 0, "Invalid parity");
    if (stopbits != 1 && stopbits != 2)
        return _serial_error(s, SERIAL_ERROR_ARG, 0, "Invalid stop bits");

    memset(s, 0, sizeof(serial_t));

    if ((s->fd = open(path, O_RDWR | O_NOCTTY)) < 0)
        return _serial_error(s, SERIAL_ERROR_OPEN, errno, "Opening serial port \"%s\"", path);

    memset(&termios_settings, 0, sizeof(termios_settings));

    termios_settings.c_iflag = IGNBRK;
    if (parity != PARITY_NONE) termios_settings.c_iflag |= INPCK;
    if (parity != PARITY_NONE && databits != 8) termios_settings.c_iflag |= ISTRIP;
    if (xonxoff) termios_settings.c_iflag |= (IXON | IXOFF);

    termios_settings.c_oflag = 0;
    termios_settings.c_lflag = 0;
    termios_settings.c_cflag = CREAD | CLOCAL;

    if (databits == 5)      termios_settings.c_cflag |= CS5;
    else if (databits == 6) termios_settings.c_cflag |= CS6;
    else if (databits == 7) termios_settings.c_cflag |= CS7;
    else if (databits == 8) termios_settings.c_cflag |= CS8;

    if (parity == PARITY_EVEN) termios_settings.c_cflag |= PARENB;
    else if (parity == PARITY_ODD) termios_settings.c_cflag |= (PARENB | PARODD);

    if (stopbits == 2) termios_settings.c_cflag |= CSTOPB;
    if (rtscts) termios_settings.c_cflag |= CRTSCTS;

    cfsetispeed(&termios_settings, _serial_baudrate_to_bits(baudrate));
    cfsetospeed(&termios_settings, _serial_baudrate_to_bits(baudrate));

    if (tcsetattr(s->fd, TCSANOW, &termios_settings) < 0) {
        int errsv = errno;
        close(s->fd);
        s->fd = -1;
        return _serial_error(s, SERIAL_ERROR_CONFIGURE, errsv, "Setting serial port attributes");
    }
    return 0;
}

static int serial_write_fd(serial_t *s, const uint8_t *buf, size_t len) {
    ssize_t ret;
    if ((ret = write(s->fd, buf, len)) < 0)
        return _serial_error(s, SERIAL_ERROR_IO, errno, "Writing serial port");
    return (int)ret;
}

static int serial_close_fd(serial_t *s) {
    if (s->fd < 0) return 0;
    if (close(s->fd) < 0)
        return _serial_error(s, SERIAL_ERROR_CLOSE, errno, "Closing serial port");
    s->fd = -1;
    return 0;
}

/* ---------- UART driver ---------- */

typedef struct {
    pthread_t       read_thread;
    volatile int    stop_flag;
    serial_t        serial;
    char           *recv_buff;
    size_t          recv_len;
    bool            initialized;
    char            devPath[32];
} SerialPort;

static SerialPort serial[8] = {0};

static int l_uart_handler(lua_State *L, void *arg);

static void *serial_read_thread(void *arg)
{
    int uart_id = (int)(intptr_t)arg;
    SerialPort *sp = &serial[uart_id];

    while (!sp->stop_flag) {
        struct pollfd pfd = { sp->serial.fd, POLLIN, 0 };
        int ret = poll(&pfd, 1, 100);
        if (ret <= 0) continue;
        if (pfd.revents & (POLLERR | POLLNVAL)) break;

        char buf[512];
        ssize_t nread = read(sp->serial.fd, buf, sizeof(buf));
        if (nread > 0) {
            size_t newsize = sp->recv_len + (size_t)nread;
            if (sp->recv_buff == NULL) {
                sp->recv_buff = luat_heap_malloc((size_t)nread);
                sp->recv_len  = (size_t)nread;
                memcpy(sp->recv_buff, buf, (size_t)nread);
            } else {
                void *p = luat_heap_realloc(sp->recv_buff, newsize);
                if (p == NULL) { LLOGE("overflow when uart recv"); continue; }
                memcpy((char *)p + sp->recv_len, buf, (size_t)nread);
                sp->recv_buff = p;
                sp->recv_len  = newsize;
            }
            rtos_msg_t msg = { .handler = l_uart_handler, .arg1 = uart_id, .arg2 = (int)nread };
            luat_msgbus_put(&msg, 0);
        } else if (nread == 0) {
            break;
        }
    }
    return NULL;
}

static int uart_setup_nop(void *userdata, luat_uart_t *uart)
{
    (void)userdata;
    if (uart->id < 0 || uart->id >= 8) {
        LLOGD("Invalid UART ID: %d", uart->id);
        return -1;
    }
    SerialPort *sp = &serial[uart->id];
    if (sp->initialized) {
        LLOGD("UART %d already initialized", uart->id);
        return -1;
    }

    serial_parity_t parity = PARITY_NONE;
    if (uart->parity == 1)      parity = PARITY_ODD;
    else if (uart->parity == 2) parity = PARITY_EVEN;

    if (serial_open_advanced(&sp->serial, sp->devPath, uart->baud_rate,
                             uart->data_bits, parity, uart->stop_bits,
                             false, false) < 0) {
        return -1;
    }

    const char *parity_str[] = {"NONE", "ODD", "EVEN"};
    printf("init uart %d fd:%d path:%s baud:%d parity:%s\n",
           uart->id, sp->serial.fd, sp->devPath,
           uart->baud_rate, parity_str[parity]);

    sp->stop_flag = 0;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&sp->read_thread, &attr, serial_read_thread,
                       (void *)(intptr_t)uart->id) != 0) {
        LLOGE("Failed to create serial read thread for uart %d", uart->id);
        pthread_attr_destroy(&attr);
        serial_close_fd(&sp->serial);
        return -1;
    }
    pthread_attr_destroy(&attr);

    sp->initialized = true;
    return 0;
}

static int uart_write_nop(void *userdata, int uart_id, void *data, size_t length)
{
    (void)userdata;
    if (uart_id < 0 || uart_id >= 8) return -1;
    SerialPort *sp = &serial[uart_id];
    if (!sp->initialized) {
        memset(sp, 0, sizeof(SerialPort));
        memcpy(sp->devPath, data, length < sizeof(sp->devPath) - 1 ? length : sizeof(sp->devPath) - 1);
        printf("UART %d set dev path: %s\n", uart_id, sp->devPath);
        return -1;
    }
    if (serial_write_fd(&sp->serial, (const uint8_t *)data, length) < 0)
        return -1;
    return 0;
}

static int uart_read_nop(void *userdata, int uart_id, void *buffer, size_t length)
{
    (void)userdata;
    if (uart_id < 0 || uart_id >= 8) return -1;
    SerialPort *sp = &serial[uart_id];
    if (!sp->initialized || sp->recv_len == 0) return -1;

    if (length > sp->recv_len) length = sp->recv_len;
    memcpy(buffer, sp->recv_buff, length);

    if (sp->recv_len > length) {
        size_t newsize = sp->recv_len - length;
        memmove(sp->recv_buff, sp->recv_buff + length, newsize);
        void *p = luat_heap_realloc(sp->recv_buff, newsize);
        sp->recv_buff = p;
        sp->recv_len  = newsize;
    } else {
        luat_heap_free(sp->recv_buff);
        sp->recv_buff = NULL;
        sp->recv_len  = 0;
    }
    return (int)length;
}

static int uart_close_nop(void *userdata, int uart_id)
{
    (void)userdata;
    if (uart_id < 0 || uart_id >= 8) return -1;
    SerialPort *sp = &serial[uart_id];
    if (!sp->initialized) return -1;

    sp->stop_flag = 1;
    serial_close_fd(&sp->serial);
    memset(sp, 0, sizeof(SerialPort));
    return 0;
}

const luat_uart_drv_opts_t uart_linux = {
    .setup = uart_setup_nop,
    .write = uart_write_nop,
    .read  = uart_read_nop,
    .close = uart_close_nop,
};

#endif
