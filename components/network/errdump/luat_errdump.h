#ifndef LUAT_ERRDUMP_H
#define LUAT_ERRDUMP_H 

void luat_errdump_save_file(const uint8_t *data, uint32_t len);
void luat_errdump_record_init(uint8_t enable, uint32_t upload_period);

#endif