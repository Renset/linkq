#ifndef WiFiTurboWatchdog_h
#define WiFiTurboWatchdog_h

#include <stddef.h>

int linkq_set_wifi_turbo_watchdog_enabled(int enabled, char *error_buffer, size_t error_buffer_size);

#endif
