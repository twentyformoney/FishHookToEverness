#pragma once

#import <Foundation/Foundation.h>
#include <objc/runtime.h>

// Entry-point swizzle targets. The payload constructor swizzles these onto
// CAMetalLayer / MTKView; everything else cascades from there as the host
// creates the device, queue, command buffer, and encoders.
IMP njyn_hook_setDevice_imp(void);
IMP njyn_hook_nextDrawable_imp(void);
IMP njyn_hook_nextDrawableWithError_imp(void);

// Installs the device-level swizzles (newCommandQueue, ...). Invoked both by
// the cascading object-side hooks and by the C-function rebinds.
void njyn_install_device_swizzle(Class cls);
