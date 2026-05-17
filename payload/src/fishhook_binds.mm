#import "fishhook_binds.h"
#import "metal_hooks.h"
#import "log.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

#include "fishhook.h"

typedef id<MTLDevice> (*MTLCreateSystemDefaultDeviceFn)(void);
typedef NSArray<id<MTLDevice>>* (*MTLCopyAllDevicesFn)(void);
typedef FILE* (*fopen_fn)(const char*, const char*);

static MTLCreateSystemDefaultDeviceFn orig_MTLCreateSystemDefaultDevice = NULL;
static MTLCopyAllDevicesFn             orig_MTLCopyAllDevices             = NULL;
static fopen_fn                        orig_fopen                         = NULL;

static id<MTLDevice> hook_MTLCreateSystemDefaultDevice(void) {
    id<MTLDevice> dev = orig_MTLCreateSystemDefaultDevice
                            ? orig_MTLCreateSystemDefaultDevice()
                            : MTLCreateSystemDefaultDevice();
    if (dev) njyn_install_device_swizzle(object_getClass(dev));
    return dev;
}

static NSArray<id<MTLDevice>>* hook_MTLCopyAllDevices(void) {
    NSArray<id<MTLDevice>>* devs = orig_MTLCopyAllDevices ? orig_MTLCopyAllDevices() : nil;
    for (id<MTLDevice> d in devs) njyn_install_device_swizzle(object_getClass(d));
    return devs;
}

static FILE* hook_fopen(const char* filename, const char* mode) {
    if (filename) {
        if (strstr(filename, "assets") || strstr(filename, "paks") ||
            strstr(filename, "Data") || strstr(filename, ".bundle")) {
            nijuyon_log("[nijuyon][FILE] fopen called for: %s (mode: %s)", filename, mode);
        }
    }
    return orig_fopen ? orig_fopen(filename, mode) : fopen(filename, mode);
}

void njyn_install_fishhook_binds(void) {
    struct rebinding rb[] = {
        {"MTLCreateSystemDefaultDevice",
         (void*)hook_MTLCreateSystemDefaultDevice,
         (void**)&orig_MTLCreateSystemDefaultDevice},
        {"MTLCopyAllDevices",
         (void*)hook_MTLCopyAllDevices,
         (void**)&orig_MTLCopyAllDevices},
        {"fopen",
         (void*)hook_fopen,
         (void**)&orig_fopen},
    };
    rebind_symbols(rb, sizeof(rb) / sizeof(rb[0]));
}
