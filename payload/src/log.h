#pragma once

#include <signal.h>

#ifdef __cplusplus
extern "C" {
#endif

void nijuyon_log(const char* format, ...) __attribute__((format(printf, 1, 2)));
void njyn_install_crash_handler(void);

#ifdef __cplusplus
}
#endif
