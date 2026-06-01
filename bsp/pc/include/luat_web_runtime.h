#ifndef LUAT_WEB_RUNTIME_H
#define LUAT_WEB_RUNTIME_H

int luat_web_runtime_start(int port, int cadence_sec);
void luat_web_runtime_stop(void);
int luat_web_runtime_set_cadence(int cadence_sec);

#endif
