#import "swizzle.h"
#import "log.h"

static NSMutableDictionary<NSString*, NSValue*>* g_orig_imps = nil;

void njyn_swizzle_init(void) {
    g_orig_imps = [NSMutableDictionary dictionary];
}

static NSString* njyn_key(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%s:%s", class_getName(cls), sel_getName(sel)];
}

void njyn_swizzle(Class cls, SEL sel, IMP new_imp) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    NSString* key = njyn_key(cls, sel);
    @synchronized (g_orig_imps) {
        if (g_orig_imps[key]) return;
        IMP orig = method_setImplementation(m, new_imp);
        g_orig_imps[key] = [NSValue valueWithPointer:(const void*)orig];
    }
    nijuyon_log("[nijuyon] swizzled -[%s %s]\n", class_getName(cls), sel_getName(sel));
}

IMP njyn_orig(id obj, SEL sel) {
    NSString* key = njyn_key(object_getClass(obj), sel);
    NSValue* v;
    @synchronized (g_orig_imps) { v = g_orig_imps[key]; }
    return (IMP)[v pointerValue];
}
