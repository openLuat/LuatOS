#include "luat_web_gnss_uart32.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <ctype.h>

#include "luat_base.h"
#include "luat_uart.h"
#include "cJSON.h"

#if defined(_WIN32) || defined(_WIN64)
#include <windows.h>
typedef CRITICAL_SECTION gnss_mutex_t;
static void gnss_mutex_init(gnss_mutex_t* m) { InitializeCriticalSection(m); }
static void gnss_mutex_lock(gnss_mutex_t* m) { EnterCriticalSection(m); }
static void gnss_mutex_unlock(gnss_mutex_t* m) { LeaveCriticalSection(m); }
static void gnss_mutex_deinit(gnss_mutex_t* m) { DeleteCriticalSection(m); }
#else
#include <pthread.h>
typedef pthread_mutex_t gnss_mutex_t;
static void gnss_mutex_init(gnss_mutex_t* m) { pthread_mutex_init(m, NULL); }
static void gnss_mutex_lock(gnss_mutex_t* m) { pthread_mutex_lock(m); }
static void gnss_mutex_unlock(gnss_mutex_t* m) { pthread_mutex_unlock(m); }
static void gnss_mutex_deinit(gnss_mutex_t* m) { pthread_mutex_destroy(m); }
#endif

#define GNSS_REPLAY_MAX 512

typedef enum {
    GNSS_MODE_FIXED = 0,
    GNSS_MODE_KML = 1,
    GNSS_MODE_FILE = 2,
} gnss_mode_t;

typedef enum {
    GNSS_ENTRY_POINT = 0,
    GNSS_ENTRY_RAW = 1,
} gnss_entry_type_t;

typedef struct {
    gnss_entry_type_t type;
    double lat;
    double lon;
    char raw[160];
} gnss_entry_t;

typedef struct {
    gnss_mutex_t lock;
    int inited;
    int running;
    gnss_mode_t mode;
    double fixed_lat;
    double fixed_lon;
    double speed_knots;
    double course;
    gnss_entry_t replay[GNSS_REPLAY_MAX];
    int replay_count;
    int replay_index;
    uint64_t last_emit_ms;
    uint32_t emit_count;
    char last_nmea[192];
} gnss_uart32_ctx_t;

static gnss_uart32_ctx_t g_gnss = {0};

static const char* gnss_mode_name(gnss_mode_t mode) {
    switch (mode) {
        case GNSS_MODE_FIXED: return "fixed";
        case GNSS_MODE_KML: return "kml";
        case GNSS_MODE_FILE: return "file";
        default: return "fixed";
    }
}

static int gnss_parse_mode(const char* name, gnss_mode_t* out) {
    if (!name || !out) return -1;
    if (!strcmp(name, "fixed")) *out = GNSS_MODE_FIXED;
    else if (!strcmp(name, "kml")) *out = GNSS_MODE_KML;
    else if (!strcmp(name, "file")) *out = GNSS_MODE_FILE;
    else return -1;
    return 0;
}

static void gnss_format_lat(double lat, char* out, size_t out_sz, char* hemi) {
    double abs_lat = lat >= 0 ? lat : -lat;
    int deg = (int)abs_lat;
    double minutes = (abs_lat - deg) * 60.0;
    snprintf(out, out_sz, "%02d%07.4f", deg, minutes);
    *hemi = lat >= 0 ? 'N' : 'S';
}

static void gnss_format_lon(double lon, char* out, size_t out_sz, char* hemi) {
    double abs_lon = lon >= 0 ? lon : -lon;
    int deg = (int)abs_lon;
    double minutes = (abs_lon - deg) * 60.0;
    snprintf(out, out_sz, "%03d%07.4f", deg, minutes);
    *hemi = lon >= 0 ? 'E' : 'W';
}

static unsigned char gnss_nmea_checksum(const char* s) {
    unsigned char sum = 0;
    while (*s) {
        sum ^= (unsigned char)(*s++);
    }
    return sum;
}

static void gnss_make_gprmc(double lat, double lon, double speed_knots, double course, char* out, size_t out_sz) {
    char lat_txt[16] = {0};
    char lon_txt[16] = {0};
    char ns = 'N';
    char ew = 'E';
    char payload[128] = {0};
    time_t t = time(NULL);
    struct tm tmv;
#if defined(_WIN32) || defined(_WIN64)
    gmtime_s(&tmv, &t);
#else
    gmtime_r(&t, &tmv);
#endif
    gnss_format_lat(lat, lat_txt, sizeof(lat_txt), &ns);
    gnss_format_lon(lon, lon_txt, sizeof(lon_txt), &ew);
    snprintf(payload, sizeof(payload),
             "GPRMC,%02d%02d%02d.00,A,%s,%c,%s,%c,%.1f,%.1f,%02d%02d%02d,,,A",
             tmv.tm_hour, tmv.tm_min, tmv.tm_sec,
             lat_txt, ns, lon_txt, ew, speed_knots, course,
             tmv.tm_mday, tmv.tm_mon + 1, (tmv.tm_year + 1900) % 100);
    snprintf(out, out_sz, "$%s*%02X", payload, gnss_nmea_checksum(payload));
}

static void gnss_emit_sentence_locked(const char* line, uint64_t now_ms) {
    char wire[220];
    size_t n = 0;
    if (!line || !line[0]) return;
    strncpy(g_gnss.last_nmea, line, sizeof(g_gnss.last_nmea) - 1);
    g_gnss.last_nmea[sizeof(g_gnss.last_nmea) - 1] = 0;
    n = (size_t)snprintf(wire, sizeof(wire), "%s\r\n", line);
    if (n > 0) {
        luat_uart_write(32, wire, n);
    }
    g_gnss.last_emit_ms = now_ms;
    g_gnss.emit_count++;
}

static int gnss_add_point(gnss_entry_t* list, int* count, double lat, double lon) {
    if (!list || !count || *count >= GNSS_REPLAY_MAX) return -1;
    list[*count].type = GNSS_ENTRY_POINT;
    list[*count].lat = lat;
    list[*count].lon = lon;
    list[*count].raw[0] = 0;
    (*count)++;
    return 0;
}

static void gnss_trim(char* s) {
    size_t len;
    char* start = s;
    while (*start && isspace((unsigned char)*start)) start++;
    if (start != s) memmove(s, start, strlen(start) + 1);
    len = strlen(s);
    while (len > 0 && isspace((unsigned char)s[len - 1])) {
        s[len - 1] = 0;
        len--;
    }
}

static int gnss_parse_kml_linestring(const char* src, gnss_entry_t* list, int* out_count) {
    const char* line_start;
    const char* coord_open;
    const char* coord_close;
    char* temp;
    char* tok;
    int count = 0;
    if (!src || !list || !out_count) return -1;
    line_start = strstr(src, "<LineString");
    if (!line_start) return -1;
    coord_open = strstr(line_start, "<coordinates>");
    if (!coord_open) return -1;
    coord_open += strlen("<coordinates>");
    coord_close = strstr(coord_open, "</coordinates>");
    if (!coord_close || coord_close <= coord_open) return -1;
    temp = (char*)malloc((size_t)(coord_close - coord_open) + 1);
    if (!temp) return -1;
    memcpy(temp, coord_open, (size_t)(coord_close - coord_open));
    temp[coord_close - coord_open] = 0;
    tok = strtok(temp, " \r\n\t");
    while (tok) {
        double lon = 0.0;
        double lat = 0.0;
        if (sscanf(tok, "%lf,%lf", &lon, &lat) == 2) {
            if (gnss_add_point(list, &count, lat, lon)) {
                free(temp);
                return -1;
            }
        }
        tok = strtok(NULL, " \r\n\t");
    }
    free(temp);
    *out_count = count;
    return count > 0 ? 0 : -1;
}

static int gnss_parse_generic_file(const char* src, gnss_entry_t* list, int* out_count) {
    char* temp;
    char* line;
    int count = 0;
    if (!src || !list || !out_count) return -1;
    temp = (char*)malloc(strlen(src) + 1);
    if (!temp) return -1;
    strcpy(temp, src);
    line = strtok(temp, "\n");
    while (line) {
        double lat = 0.0;
        double lon = 0.0;
        gnss_trim(line);
        if (line[0]) {
            if (line[0] == '$') {
                if (count >= GNSS_REPLAY_MAX) {
                    free(temp);
                    return -1;
                }
                list[count].type = GNSS_ENTRY_RAW;
                list[count].lat = 0;
                list[count].lon = 0;
                strncpy(list[count].raw, line, sizeof(list[count].raw) - 1);
                list[count].raw[sizeof(list[count].raw) - 1] = 0;
                count++;
            }
            else if (sscanf(line, "%lf,%lf", &lat, &lon) == 2) {
                if (gnss_add_point(list, &count, lat, lon)) {
                    free(temp);
                    return -1;
                }
            }
        }
        line = strtok(NULL, "\n");
    }
    free(temp);
    *out_count = count;
    return count > 0 ? 0 : -1;
}

void luat_web_gnss_uart32_init(void) {
    if (g_gnss.inited) return;
    memset(&g_gnss, 0, sizeof(g_gnss));
    gnss_mutex_init(&g_gnss.lock);
    g_gnss.inited = 1;
    g_gnss.mode = GNSS_MODE_FIXED;
    g_gnss.fixed_lat = 39.9070;
    g_gnss.fixed_lon = 116.3910;
    g_gnss.speed_knots = 0.5;
    g_gnss.course = 0.0;
}

void luat_web_gnss_uart32_deinit(void) {
    if (!g_gnss.inited) return;
    gnss_mutex_deinit(&g_gnss.lock);
    memset(&g_gnss, 0, sizeof(g_gnss));
}

void luat_web_gnss_uart32_tick(uint64_t now_ms) {
    char sentence[192] = {0};
    if (!g_gnss.inited) return;
    gnss_mutex_lock(&g_gnss.lock);
    if (!g_gnss.running) {
        gnss_mutex_unlock(&g_gnss.lock);
        return;
    }
    if (g_gnss.last_emit_ms != 0 && now_ms - g_gnss.last_emit_ms < 1000ULL) {
        gnss_mutex_unlock(&g_gnss.lock);
        return;
    }
    if (g_gnss.mode == GNSS_MODE_FIXED) {
        gnss_make_gprmc(g_gnss.fixed_lat, g_gnss.fixed_lon, g_gnss.speed_knots, g_gnss.course, sentence, sizeof(sentence));
    }
    else if (g_gnss.replay_count > 0) {
        gnss_entry_t* e = &g_gnss.replay[g_gnss.replay_index];
        if (e->type == GNSS_ENTRY_RAW) {
            strncpy(sentence, e->raw, sizeof(sentence) - 1);
        }
        else {
            gnss_make_gprmc(e->lat, e->lon, g_gnss.speed_knots, g_gnss.course, sentence, sizeof(sentence));
        }
        g_gnss.replay_index = (g_gnss.replay_index + 1) % g_gnss.replay_count;
    }
    if (sentence[0]) {
        gnss_emit_sentence_locked(sentence, now_ms);
    }
    gnss_mutex_unlock(&g_gnss.lock);
}

int luat_web_gnss_uart32_apply_config(const char* body) {
    cJSON* root = cJSON_Parse(body ? body : "");
    cJSON* mode;
    cJSON* running;
    cJSON* fixed;
    cJSON* source_text;
    cJSON* index;
    gnss_mode_t new_mode = g_gnss.mode;
    gnss_entry_t parsed[GNSS_REPLAY_MAX];
    int parsed_count = -1;
    if (!root) return -1;

    mode = cJSON_GetObjectItemCaseSensitive(root, "mode");
    running = cJSON_GetObjectItemCaseSensitive(root, "running");
    fixed = cJSON_GetObjectItemCaseSensitive(root, "fixed");
    source_text = cJSON_GetObjectItemCaseSensitive(root, "source_text");
    index = cJSON_GetObjectItemCaseSensitive(root, "index");

    if (cJSON_IsString(mode) && gnss_parse_mode(mode->valuestring, &new_mode)) {
        cJSON_Delete(root);
        return -1;
    }
    if (cJSON_IsString(source_text)) {
        memset(parsed, 0, sizeof(parsed));
        if (new_mode == GNSS_MODE_KML) {
            if (gnss_parse_kml_linestring(source_text->valuestring, parsed, &parsed_count)) {
                cJSON_Delete(root);
                return -1;
            }
        }
        else if (new_mode == GNSS_MODE_FILE) {
            if (gnss_parse_generic_file(source_text->valuestring, parsed, &parsed_count)) {
                cJSON_Delete(root);
                return -1;
            }
        }
        else {
            cJSON_Delete(root);
            return -1;
        }
    }

    gnss_mutex_lock(&g_gnss.lock);
    g_gnss.mode = new_mode;
    if (cJSON_IsBool(running) || cJSON_IsNumber(running)) {
        g_gnss.running = cJSON_IsTrue(running) || (cJSON_IsNumber(running) && running->valueint != 0);
    }
    if (fixed && cJSON_IsObject(fixed)) {
        cJSON* lat = cJSON_GetObjectItemCaseSensitive(fixed, "lat");
        cJSON* lon = cJSON_GetObjectItemCaseSensitive(fixed, "lon");
        cJSON* speed_knots = cJSON_GetObjectItemCaseSensitive(fixed, "speed_knots");
        cJSON* course = cJSON_GetObjectItemCaseSensitive(fixed, "course");
        if (!cJSON_IsNumber(lat) || !cJSON_IsNumber(lon)) {
            gnss_mutex_unlock(&g_gnss.lock);
            cJSON_Delete(root);
            return -1;
        }
        g_gnss.fixed_lat = lat->valuedouble;
        g_gnss.fixed_lon = lon->valuedouble;
        if (cJSON_IsNumber(speed_knots)) g_gnss.speed_knots = speed_knots->valuedouble;
        if (cJSON_IsNumber(course)) g_gnss.course = course->valuedouble;
    }
    if (parsed_count >= 0) {
        memcpy(g_gnss.replay, parsed, sizeof(gnss_entry_t) * (size_t)parsed_count);
        g_gnss.replay_count = parsed_count;
        g_gnss.replay_index = 0;
    }
    if (cJSON_IsNumber(index) && g_gnss.replay_count > 0) {
        int i = index->valueint;
        if (i < 0) i = 0;
        if (i >= g_gnss.replay_count) i = g_gnss.replay_count - 1;
        g_gnss.replay_index = i;
    }
    gnss_mutex_unlock(&g_gnss.lock);

    cJSON_Delete(root);
    return 0;
}

cJSON* luat_web_gnss_uart32_make_status_json(void) {
    cJSON* root = cJSON_CreateObject();
    if (!root) return NULL;
    gnss_mutex_lock(&g_gnss.lock);
    cJSON_AddBoolToObject(root, "ok", 1);
    cJSON_AddStringToObject(root, "mode", gnss_mode_name(g_gnss.mode));
    cJSON_AddBoolToObject(root, "running", g_gnss.running ? 1 : 0);
    cJSON_AddNumberToObject(root, "total_points", g_gnss.replay_count);
    cJSON_AddNumberToObject(root, "index", g_gnss.replay_index);
    cJSON_AddNumberToObject(root, "emit_count", g_gnss.emit_count);
    cJSON_AddStringToObject(root, "last_nmea", g_gnss.last_nmea);
    cJSON_AddNumberToObject(root, "fixed_lat", g_gnss.fixed_lat);
    cJSON_AddNumberToObject(root, "fixed_lon", g_gnss.fixed_lon);
    gnss_mutex_unlock(&g_gnss.lock);
    return root;
}
