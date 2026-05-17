#pragma once

#import <Foundation/Foundation.h>
#include <objc/runtime.h>

// Per-(class, selector) swizzle bookkeeping. The first call replaces the IMP
// and records the original; subsequent calls for the same key are no-ops.
void njyn_swizzle(Class cls, SEL sel, IMP new_imp);

// Fetch the original IMP recorded for (object's class, sel). Returns NULL if
// none was recorded.
IMP njyn_orig(id obj, SEL sel);

// Must be called once before any njyn_swizzle / njyn_orig calls.
void njyn_swizzle_init(void);
