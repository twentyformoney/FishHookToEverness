#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#import "log.h"
#import "state.h"
#import "swizzle.h"
#import "metal_hooks.h"
#import "fishhook_binds.h"

__attribute__((constructor))
static void payload_init(void) {
    nijuyon_log("[nijuyon] ==========================================\n");
    nijuyon_log("[nijuyon] TARGET: Injected successfully via dyld!\n");
    nijuyon_log("[nijuyon] ==========================================\n");

    njyn_swizzle_init();
    njyn_state_init();

    njyn_install_fishhook_binds();

    njyn_swizzle(NSClassFromString(@"MTKView"), @selector(setDevice:), njyn_hook_setDevice_imp());
    njyn_swizzle([CAMetalLayer class], @selector(setDevice:), njyn_hook_setDevice_imp());
    njyn_swizzle([CAMetalLayer class], @selector(nextDrawable), njyn_hook_nextDrawable_imp());
    njyn_swizzle([CAMetalLayer class], @selector(nextDrawableWithError:), njyn_hook_nextDrawableWithError_imp());

    nijuyon_log("[nijuyon] hooks installed; awaiting first frame\n");

    njyn_install_crash_handler();
}
