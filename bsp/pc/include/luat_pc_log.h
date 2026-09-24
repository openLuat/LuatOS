#ifndef LUAT_PC_LOG_H
#define LUAT_PC_LOG_H

#ifdef __cplusplus
extern "C" {
#endif

/* 在打开 pclogs 文件之前调用。空路径或过长返回 -1。 */
int luat_log_set_dir(const char *dir);
const char *luat_log_get_dir(void);
int luat_log_ensure_dir(void);
/* 扫描 argv 中的 --log-dir=<path>，须在 luat_pcconf_init / luat_log_init_win32 之前。 */
int luat_log_parse_cli(int argc, char **argv);

void luat_log_init_win32(void);
void luat_log_deinit_win32(void);

#ifdef __cplusplus
}
#endif

#endif
