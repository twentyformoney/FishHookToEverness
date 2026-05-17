#import <Foundation/Foundation.h>
#include <os/lock.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <execinfo.h>
#include <signal.h>
#include <stdlib.h>

#include "log.h"

static os_unfair_lock g_log_lock = OS_UNFAIR_LOCK_INIT;

void nijuyon_log(const char* format, ...) {
    char message[2048];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);

    size_t len = strlen(message);
    while (len > 0 && message[len - 1] == '\n') message[--len] = '\0';

    NSLog(@"%s", message);

    static dispatch_once_t once;
    static FILE* file = NULL;
    dispatch_once(&once, ^{
        NSArray* dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString* base = dirs.firstObject ?: NSTemporaryDirectory();
        NSString* log_path = [base stringByAppendingPathComponent:@"nijuyon.log"];
        file = fopen(log_path.UTF8String, "a");
        if (file) setvbuf(file, NULL, _IOLBF, 0);
        NSLog(@"[nijuyon] log file -> %@", log_path);
    });

    if (file) {
        time_t now = time(NULL);
        struct tm* t = localtime(&now);
        char time_str[32];
        strftime(time_str, sizeof(time_str), "[%Y-%m-%d %H:%M:%S] ", t);
        os_unfair_lock_lock(&g_log_lock);
        fprintf(file, "%s%s\n", time_str, message);
        os_unfair_lock_unlock(&g_log_lock);
    }
}

static void crash_handler(int sig, siginfo_t* info, void* context) {
    nijuyon_log("*** CRASH: signal %d (%s), addr %p\n", sig, strsignal(sig), info->si_addr);
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    char** symbols = backtrace_symbols(callstack, frames);
    for (int i = 0; i < frames; i++) {
        nijuyon_log("  %s\n", symbols[i]);
    }
    free(symbols);
    exit(1);
}

void njyn_install_crash_handler(void) {
    struct sigaction sa = {0};
    sa.sa_flags = SA_SIGINFO;
    sa.sa_sigaction = crash_handler;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);
}
