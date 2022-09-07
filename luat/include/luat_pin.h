
#ifndef LUAT_PIN_H
#define LUAT_PIN_H

int luat_pin_to_gpio(const char* pin_name);

int luat_pin_parse(const char* pin_name, size_t* zone, size_t* index);

#endif
