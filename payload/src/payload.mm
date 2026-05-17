#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdarg.h>
#include <time.h>


void nijuyon_log(const char* format, ...) {

    time_t now = time(NULL);
    struct tm* t = localtime(&now);
    char time_str[32];
    strftime(time_str, sizeof(time_str), "[%Y-%m-%d %H:%M:%S] ", t);

    char message[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);

    printf("%s%s", time_str, message);
    fflush(stdout); 


    FILE* file = fopen("nijuyon.log", "a");
    if (file) {
        fprintf(file, "%s%s", time_str, message);
        fclose(file);
    } else {
        fprintf(stderr, "%s[nijuyon error] Failed to write log to disk.\n", time_str);
    }
}

__attribute__((constructor))
static void payload_init(void) {
    nijuyon_log("[nijuyon] ==========================================\n");
    nijuyon_log("[nijuyon] TARGET: Injected successfully via dyld!\n");
    nijuyon_log("[nijuyon] ==========================================\n");


}
