
#include "luat_base.h"
#include "luat_log.h"
#include "luat_uart.h"
#include "luat_malloc.h"
#include "printf.h"
#include "luat_mcu.h"

#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>

#ifdef LUAT_USE_WINDOWS
#include <direct.h>
#endif

#include "uv.h"

typedef struct log_msg {
    char* buff;
}log_msg_t;

static uint8_t luat_log_uart_port = 0;
static uint8_t luat_log_level_cur = LUAT_LOG_DEBUG;

extern int32_t luatos_pc_climode;
extern int cmdline_argc;
extern char** cmdline_argv;

#define LOGLOG_SIZE 4096
#define LUAT_PC_LOG_DIR "pclogs"
#define LUAT_PC_LOG_PATH_MAX 256
#define LUAT_PC_LOG_CWD_MAX 512

static FILE* luat_log_file_fd = NULL;
static time_t luat_log_startup_time = 0;
static uint16_t luat_log_startup_ms = 0;
static uint8_t luat_log_startup_ready = 0;
static uint8_t luat_log_atexit_registered = 0;
static uint8_t luat_log_header_written = 0;
static uint8_t luat_log_file_disabled = 0;
static uint8_t luat_log_file_warning_reported = 0;
static char luat_log_file_path[LUAT_PC_LOG_PATH_MAX] = {0};

void luat_log_deinit_win32(void);
static void luat_log_write_startup_header(void);

static int luat_log_host_dir_exists(const char* path) {
    struct stat st;

    if (path == NULL) {
        return 0;
    }
    if (stat(path, &st) != 0) {
        return 0;
    }
    return (st.st_mode & S_IFDIR) != 0;
}

static int luat_log_host_mkdir(const char* path) {
#ifdef LUAT_USE_WINDOWS
    return _mkdir(path);
#else
    return mkdir(path, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
#endif
}

static int luat_log_host_file_exists(const char* path) {
    FILE* fd;

    if (path == NULL) {
        return 0;
    }
    fd = fopen(path, "rb");
    if (fd == NULL) {
        return 0;
    }
    fclose(fd);
    return 1;
}

static void luat_log_capture_startup_time(void) {
    uv_timespec64_t tv;

    if (luat_log_startup_ready) {
        return;
    }

    time(&luat_log_startup_time);
    if (uv_clock_gettime(UV_CLOCK_REALTIME, &tv) == 0) {
        luat_log_startup_ms = (uint16_t)(tv.tv_nsec / 1000000);
    }
    else {
        luat_log_startup_ms = 0;
    }
    luat_log_startup_ready = 1;
}

static void luat_log_report_file_warning(const char* reason) {
    if (luat_log_file_warning_reported) {
        return;
    }
    luat_log_file_warning_reported = 1;
    if (luat_log_file_path[0] != 0) {
        fprintf(stderr, "[luat-log] %s: %s\n", reason, luat_log_file_path);
    }
    else {
        fprintf(stderr, "[luat-log] %s\n", reason);
    }
}

static size_t luat_log_format_prefix(char* buff, size_t buff_size) {
    time_t now;
    struct tm *local_time;
    uv_timespec64_t tv;
    uint64_t tick;
    uint32_t sec;
    uint32_t ms;
    int len;

    if (buff == NULL || buff_size == 0) {
        return 0;
    }

    time(&now);
    if (uv_clock_gettime(UV_CLOCK_REALTIME, &tv) != 0) {
        tv.tv_nsec = 0;
    }
    local_time = localtime(&now);
    if (local_time == NULL) {
        buff[0] = 0;
        return 0;
    }

    tick = luat_mcu_tick64_ms();
    sec = (uint32_t)(tick / 1000);
    ms = (uint32_t)(tick % 1000);

    len = snprintf(buff, buff_size,
        "[%d-%02d-%02d %02d:%02d:%02d.%03d][%08lu.%03lu] ",
        local_time->tm_year + 1900, local_time->tm_mon + 1, local_time->tm_mday,
        local_time->tm_hour, local_time->tm_min, local_time->tm_sec,
        (int)(tv.tv_nsec / 1000000),
        (unsigned long)sec, (unsigned long)ms);
    if (len <= 0) {
        buff[0] = 0;
        return 0;
    }
    if ((size_t)len >= buff_size) {
        return buff_size - 1;
    }
    return (size_t)len;
}

static int luat_log_build_file_path(char* buff, size_t buff_size) {
    struct tm *local_time;
    int len;
    int suffix;

    if (buff == NULL || buff_size == 0) {
        return -1;
    }

    luat_log_capture_startup_time();
    local_time = localtime(&luat_log_startup_time);
    if (local_time == NULL) {
        return -1;
    }

    len = snprintf(buff, buff_size,
        LUAT_PC_LOG_DIR "/luatos_pc_%04d%02d%02d_%02d%02d%02d_%03u.log",
        local_time->tm_year + 1900, local_time->tm_mon + 1, local_time->tm_mday,
        local_time->tm_hour, local_time->tm_min, local_time->tm_sec,
        (unsigned int)luat_log_startup_ms);
    if (len <= 0 || (size_t)len >= buff_size) {
        return -1;
    }
    if (!luat_log_host_file_exists(buff)) {
        return 0;
    }

    for (suffix = 1; suffix < 100; suffix++) {
        len = snprintf(buff, buff_size,
            LUAT_PC_LOG_DIR "/luatos_pc_%04d%02d%02d_%02d%02d%02d_%03u_%02d.log",
            local_time->tm_year + 1900, local_time->tm_mon + 1, local_time->tm_mday,
            local_time->tm_hour, local_time->tm_min, local_time->tm_sec,
            (unsigned int)luat_log_startup_ms, suffix);
        if (len <= 0 || (size_t)len >= buff_size) {
            return -1;
        }
        if (!luat_log_host_file_exists(buff)) {
            return 0;
        }
    }

    return -1;
}

static int luat_log_open_file_if_needed(void) {
    if (luat_log_file_fd != NULL) {
        return 0;
    }
    if (luat_log_file_disabled) {
        return -1;
    }
    if (luat_log_host_mkdir(LUAT_PC_LOG_DIR) != 0 && !luat_log_host_dir_exists(LUAT_PC_LOG_DIR)) {
        strncpy(luat_log_file_path, LUAT_PC_LOG_DIR, sizeof(luat_log_file_path) - 1);
        luat_log_file_disabled = 1;
        luat_log_report_file_warning("failed to create pclogs directory");
        return -1;
    }
    if (luat_log_build_file_path(luat_log_file_path, sizeof(luat_log_file_path)) != 0) {
        luat_log_file_disabled = 1;
        luat_log_report_file_warning("failed to build log file path");
        return -1;
    }
    luat_log_file_fd = fopen(luat_log_file_path, "ab+");
    if (luat_log_file_fd == NULL) {
        luat_log_file_disabled = 1;
        luat_log_report_file_warning("failed to open log file");
        return -1;
    }
    luat_log_write_startup_header();
    return 0;
}

static void luat_log_disable_file_output(const char* reason) {
    if (luat_log_file_fd != NULL) {
        fflush(luat_log_file_fd);
        fclose(luat_log_file_fd);
        luat_log_file_fd = NULL;
    }
    luat_log_file_disabled = 1;
    luat_log_report_file_warning(reason);
}

static void luat_log_write_header_line(const char* content) {
    char prefix[129] = {0};
    size_t prefix_len;
    size_t content_len;

    if (luat_log_file_fd == NULL || content == NULL) {
        return;
    }

    prefix_len = luat_log_format_prefix(prefix, sizeof(prefix));
    content_len = strlen(content);
    if (prefix_len > 0 && fwrite(prefix, 1, prefix_len, luat_log_file_fd) != prefix_len) {
        luat_log_disable_file_output("failed to write log header prefix");
        return;
    }
    if (content_len > 0 && fwrite(content, 1, content_len, luat_log_file_fd) != content_len) {
        luat_log_disable_file_output("failed to write log header content");
        return;
    }
    fflush(luat_log_file_fd);
}

static void luat_log_write_startup_header(void) {
    char line[768] = {0};
    char cwd[LUAT_PC_LOG_CWD_MAX] = {0};
    size_t cwd_len = sizeof(cwd);
    int i;

    if (luat_log_header_written || luat_log_file_fd == NULL) {
        return;
    }

    luat_log_header_written = 1;
    luat_log_write_header_line("I/pclog ===== session start =====\n");

    snprintf(line, sizeof(line), "I/pclog logfile: %s\n", luat_log_file_path);
    luat_log_write_header_line(line);

    if (uv_cwd(cwd, &cwd_len) == 0) {
        snprintf(line, sizeof(line), "I/pclog cwd: %s\n", cwd);
    }
    else {
        snprintf(line, sizeof(line), "I/pclog cwd: <unavailable>\n");
    }
    luat_log_write_header_line(line);

    snprintf(line, sizeof(line), "I/pclog argc: %d\n", cmdline_argc);
    luat_log_write_header_line(line);

    for (i = 0; i < cmdline_argc; i++) {
        snprintf(line, sizeof(line), "I/pclog argv[%d]: %s\n", i,
            (cmdline_argv != NULL && cmdline_argv[i] != NULL) ? cmdline_argv[i] : "<null>");
        luat_log_write_header_line(line);
        if (luat_log_file_disabled) {
            return;
        }
    }

    luat_log_write_header_line("I/pclog =========================\n");
}

static void luat_log_write_file_with_prefix(const char* prefix, size_t prefix_len, const char* content, size_t content_len) {
    size_t written;

    if (luat_log_open_file_if_needed() != 0 || luat_log_file_fd == NULL) {
        return;
    }
    if (prefix_len > 0) {
        written = fwrite(prefix, 1, prefix_len, luat_log_file_fd);
        if (written != prefix_len) {
            luat_log_disable_file_output("failed to write log prefix");
            return;
        }
    }
    if (content_len > 0) {
        written = fwrite(content, 1, content_len, luat_log_file_fd);
        if (written != content_len) {
            luat_log_disable_file_output("failed to write log content");
            return;
        }
    }
    fflush(luat_log_file_fd);
}

void luat_log_init_win32(void) {
    luat_log_capture_startup_time();
    if (!luat_log_atexit_registered) {
        atexit(luat_log_deinit_win32);
        luat_log_atexit_registered = 1;
    }
    luat_log_open_file_if_needed();
}

void luat_log_deinit_win32(void) {
    if (luat_log_file_fd != NULL) {
        fflush(luat_log_file_fd);
        fclose(luat_log_file_fd);
        luat_log_file_fd = NULL;
    }
    luat_log_header_written = 0;
}

void luat_log_set_uart_port(int port) {
    luat_log_uart_port = (uint8_t)port;
}

void luat_print(const char* _str) {
    luat_nprint((char*)_str, strlen(_str));
}

void luat_nprint(char *s, size_t l) {
    luat_log_write(s, l);
}
void luat_log_write(char *s, size_t l) {
    char prefix[129] = {0};
    size_t prefix_len = luat_log_format_prefix(prefix, sizeof(prefix));

    if (luatos_pc_climode) {
        printf("%.*s", (int)l, s);
    }
    else {
        printf("%s%.*s", prefix, (int)l, s);
    }
    luat_log_write_file_with_prefix(prefix, prefix_len, s, l);
}

void luat_log_set_level(int level) {
    luat_log_level_cur = (uint8_t)level;
}
int luat_log_get_level() {
    return luat_log_level_cur;
}

void luat_log_log(int level, const char* tag, const char* _fmt, ...) {
    if (luat_log_level_cur > level) return;
    char buff[LOGLOG_SIZE] = {0};
    char *tmp = (char *)buff;
    switch (level)
        {
        case LUAT_LOG_DEBUG:
            tmp[0] = 'D';
            break;
        case LUAT_LOG_INFO:
            tmp[0] = 'I';
            break;
        case LUAT_LOG_WARN:
            tmp[0] = 'W';
            break;
        case LUAT_LOG_ERROR:
            tmp[0] = 'E';
            break;
        default:
            tmp[0] = '?';
            break;
        }
    tmp ++;
    tmp[0] = '/';
    tmp ++;
    size_t taglen = strlen(tag);
    if (taglen > LOGLOG_SIZE / 2)
        taglen = LOGLOG_SIZE / 2;
    memcpy(tmp, tag, taglen);
    tmp += taglen;
    tmp[0] = ' ';
    tmp ++;
    size_t len = 0;
    va_list args;
    va_start(args, _fmt);
    len = vsnprintf_(tmp, LOGLOG_SIZE - strlen(buff), _fmt, args);
    va_end(args);
    if (len > 0) {
        len = strlen(buff);
        if (len > LOGLOG_SIZE - 1)
            len = LOGLOG_SIZE - 1;
        buff[len] = '\n';
        luat_log_write(buff, len+1);
    }
}

void luat_debug_assert(const char *fun_name, unsigned int line_no, const char *fmt, ...) {
    printf("ASSERT: %s:%u: ", fun_name, line_no);
    char buff[256] = {0};
    va_list args;
    va_start(args, fmt);
    vsnprintf_(buff, sizeof(buff) - 1, fmt, args);
    va_end(args);
    printf("%s\n", buff);
    // 这里不做任何处理，直接退出
    exit(16);
}
