#import "metal_hooks.h"
#import "state.h"
#import "swizzle.h"
#import "hud.h"
#import "log.h"

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <objc/message.h>

// Forward declarations for the installer chain.
static void njyn_install_encoder_swizzle(Class cls);
static void njyn_install_queue_swizzle(Class cls);
static void njyn_install_present_swizzle(Class cls);
static void njyn_install_drawable_swizzle(Class cls);

static dispatch_once_t g_first_present_log;
static void njyn_log_first_present(const char* path) {
    dispatch_once(&g_first_present_log, ^{
        nijuyon_log("[nijuyon] first present via %s\n", path);
    });
}

// ---------------------------------------------------------------------------
// Render-command-encoder hooks
// ---------------------------------------------------------------------------
static void njyn_hook_setRenderPipelineState(id self, SEL _cmd, id<MTLRenderPipelineState> pipelineState) {
    NSString* label = pipelineState.label;
    if (!g_in_imgui_draw) {
        g_frame_stats.pipeline_changes++;
        if (label && njyn_first_seen(g_seen_pipelines, label)) {
            nijuyon_log("[nijuyon][pipeline NEW] '%s'", label.UTF8String);
        }
        if (g_enable_capture_log) {
            nijuyon_log("[nijuyon]   [Pipeline] %s", label.UTF8String ?: "unlabeled");
        }
    }
    objc_setAssociatedObject(self, &njyn_pipeline_assoc_key, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    typedef void (*Fn)(id, SEL, id<MTLRenderPipelineState>);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, pipelineState);
}

static void njyn_hook_drawPrimitives(id self, SEL _cmd, MTLPrimitiveType type, NSUInteger start, NSUInteger count, NSUInteger instances) {
    if (!g_in_imgui_draw) {
        NSString* pipeline_label = objc_getAssociatedObject(self, &njyn_pipeline_assoc_key);
        if (pipeline_label && njyn_is_blocked(pipeline_label)) return;
        if (njyn_encoder_has_hidden_texture(self)) return;
        g_frame_stats.draw_calls++;
        if (g_enable_capture_log) {
            nijuyon_log("[nijuyon]   draw type=%lu start=%lu count=%lu inst=%lu pipeline='%s'",
                        (unsigned long)type, (unsigned long)start, (unsigned long)count, (unsigned long)instances,
                        pipeline_label.UTF8String ?: "?");
        }
    }
    typedef void (*Fn)(id, SEL, MTLPrimitiveType, NSUInteger, NSUInteger, NSUInteger);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, type, start, count, instances);
}

static void njyn_hook_drawIndexedPrimitives(id self, SEL _cmd, MTLPrimitiveType type, NSUInteger count, MTLIndexType idxType, id<MTLBuffer> idxBuf, NSUInteger idxBufOffset, NSUInteger instances) {
    if (!g_in_imgui_draw) {
        NSString* pipeline_label = objc_getAssociatedObject(self, &njyn_pipeline_assoc_key);
        if (pipeline_label && njyn_is_blocked(pipeline_label)) return;
        if (njyn_encoder_has_hidden_texture(self)) return;
        g_frame_stats.indexed_draws++;
        if (g_enable_capture_log) {
            nijuyon_log("[nijuyon]   drawIdx type=%lu count=%lu idxBuf=%s inst=%lu pipeline='%s'",
                        (unsigned long)type, (unsigned long)count, idxBuf.label.UTF8String ?: "unlabeled", (unsigned long)instances,
                        pipeline_label.UTF8String ?: "?");
        }
    }
    typedef void (*Fn)(id, SEL, MTLPrimitiveType, NSUInteger, MTLIndexType, id<MTLBuffer>, NSUInteger, NSUInteger);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, type, count, idxType, idxBuf, idxBufOffset, instances);
}

static void njyn_hook_setFragmentTexture(id self, SEL _cmd, id<MTLTexture> texture, NSUInteger index) {
    if (!g_in_imgui_draw) {
        NSMutableDictionary<NSNumber*, NSString*>* slots = njyn_encoder_textures(self);
        if (!texture) {
            [slots removeObjectForKey:@(index)];
        } else {
            NSString* label = texture.label;
            if (!label) {
                label = [NSString stringWithFormat:@"(unlabeled %lux%lu fmt%lu)",
                         (unsigned long)texture.width, (unsigned long)texture.height,
                         (unsigned long)texture.pixelFormat];
            }
            if (njyn_first_seen(g_seen_textures, label)) {
                uint32_t id_num;
                os_unfair_lock_lock(&g_seen_lock);
                id_num = g_next_texture_id++;
                g_texture_ids[label] = @(id_num);
                os_unfair_lock_unlock(&g_seen_lock);
                nijuyon_log("[nijuyon][texture NEW #%u] '%s' %lux%lu fmt=%lu",
                            id_num,
                            label.UTF8String,
                            (unsigned long)texture.width,
                            (unsigned long)texture.height,
                            (unsigned long)texture.pixelFormat);
            }
            slots[@(index)] = label;

            os_unfair_lock_lock(&g_seen_lock);
            NSNumber* tint = g_tinted_textures[label];
            os_unfair_lock_unlock(&g_seen_lock);
            if (tint) {
                id<MTLTexture> replacement = njyn_solid_color_texture((uint32_t)tint.unsignedIntValue);
                if (replacement) texture = replacement;
            }
        }
    }
    typedef void (*Fn)(id, SEL, id<MTLTexture>, NSUInteger);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, texture, index);
}

static void njyn_install_encoder_swizzle(Class cls) {
    njyn_swizzle(cls, @selector(setRenderPipelineState:), (IMP)njyn_hook_setRenderPipelineState);
    njyn_swizzle(cls, @selector(drawPrimitives:vertexStart:vertexCount:instanceCount:), (IMP)njyn_hook_drawPrimitives);
    njyn_swizzle(cls, @selector(drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:), (IMP)njyn_hook_drawIndexedPrimitives);
    njyn_swizzle(cls, @selector(setFragmentTexture:atIndex:), (IMP)njyn_hook_setFragmentTexture);
}

// ---------------------------------------------------------------------------
// Command-buffer present hooks
// ---------------------------------------------------------------------------
static void njyn_hook_presentDrawable(id self, SEL _cmd, id<CAMetalDrawable> drawable) {
    njyn_log_first_present("cb presentDrawable:");
    njyn_draw_imgui((id<MTLCommandBuffer>)self, drawable);
    typedef void (*Fn)(id, SEL, id<CAMetalDrawable>);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, drawable);
}

static void njyn_hook_presentDrawableAtTime(id self, SEL _cmd,
                                            id<CAMetalDrawable> drawable, CFTimeInterval t) {
    njyn_log_first_present("cb presentDrawable:atTime:");
    njyn_draw_imgui((id<MTLCommandBuffer>)self, drawable);
    typedef void (*Fn)(id, SEL, id<CAMetalDrawable>, CFTimeInterval);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, drawable, t);
}

static void njyn_hook_presentDrawableAfterMinDuration(id self, SEL _cmd,
                                                      id<CAMetalDrawable> drawable,
                                                      CFTimeInterval duration) {
    njyn_log_first_present("cb presentDrawable:afterMinimumDuration:");
    njyn_draw_imgui((id<MTLCommandBuffer>)self, drawable);
    typedef void (*Fn)(id, SEL, id<CAMetalDrawable>, CFTimeInterval);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, drawable, duration);
}

// Drawable-side present (host calls [drawable present] directly). Allocate
// a command buffer on the host's queue and commit it before forwarding.
static void njyn_drawable_inject(id<CAMetalDrawable> drawable) {
    id<MTLCommandQueue> q = g_host_queue;
    if (!q || !g_imgui_ready) return;
    @autoreleasepool {
        id<MTLCommandBuffer> cb = [q commandBuffer];
        njyn_draw_imgui(cb, drawable);
        [cb commit];
    }
}

static void njyn_hook_drawable_present(id self, SEL _cmd) {
    njyn_log_first_present("drawable present");
    njyn_drawable_inject((id<CAMetalDrawable>)self);
    typedef void (*Fn)(id, SEL);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd);
}

static void njyn_hook_drawable_presentAtTime(id self, SEL _cmd, CFTimeInterval t) {
    njyn_log_first_present("drawable presentAtTime:");
    njyn_drawable_inject((id<CAMetalDrawable>)self);
    typedef void (*Fn)(id, SEL, CFTimeInterval);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, t);
}

static void njyn_hook_drawable_presentAfterMinDuration(id self, SEL _cmd, CFTimeInterval d) {
    njyn_log_first_present("drawable presentAfterMinimumDuration:");
    njyn_drawable_inject((id<CAMetalDrawable>)self);
    typedef void (*Fn)(id, SEL, CFTimeInterval);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, d);
}

// Hook encoder creation so we can cascade encoder-side swizzles onto the
// concrete class the host actually uses.
static id njyn_hook_renderCommandEncoderWithDescriptor(id self, SEL _cmd, MTLRenderPassDescriptor* desc) {
    typedef id (*Fn)(id, SEL, MTLRenderPassDescriptor*);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    id enc = orig ? orig(self, _cmd, desc) : nil;
    if (enc) njyn_install_encoder_swizzle(object_getClass(enc));
    return enc;
}

static void njyn_install_present_swizzle(Class cls) {
    njyn_swizzle(cls, @selector(presentDrawable:), (IMP)njyn_hook_presentDrawable);
    njyn_swizzle(cls, @selector(presentDrawable:atTime:), (IMP)njyn_hook_presentDrawableAtTime);
    njyn_swizzle(cls, @selector(presentDrawable:afterMinimumDuration:),
                 (IMP)njyn_hook_presentDrawableAfterMinDuration);
    njyn_swizzle(cls, @selector(renderCommandEncoderWithDescriptor:),
                 (IMP)njyn_hook_renderCommandEncoderWithDescriptor);
}

static void njyn_install_drawable_swizzle(Class cls) {
    njyn_swizzle(cls, @selector(present), (IMP)njyn_hook_drawable_present);
    njyn_swizzle(cls, @selector(presentAtTime:), (IMP)njyn_hook_drawable_presentAtTime);
    njyn_swizzle(cls, @selector(presentAfterMinimumDuration:),
                 (IMP)njyn_hook_drawable_presentAfterMinDuration);
}

// ---------------------------------------------------------------------------
// Queue / device cascading
// ---------------------------------------------------------------------------
static id<MTLCommandBuffer> njyn_hook_commandBuffer(id self, SEL _cmd) {
    typedef id<MTLCommandBuffer> (*Fn)(id, SEL);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    id<MTLCommandBuffer> cb = orig ? orig(self, _cmd) : nil;
    if (cb) njyn_install_present_swizzle(object_getClass(cb));
    return cb;
}

static id<MTLCommandBuffer> njyn_hook_commandBufferUnretained(id self, SEL _cmd) {
    typedef id<MTLCommandBuffer> (*Fn)(id, SEL);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    id<MTLCommandBuffer> cb = orig ? orig(self, _cmd) : nil;
    if (cb) njyn_install_present_swizzle(object_getClass(cb));
    return cb;
}

static void njyn_install_queue_swizzle(Class cls) {
    njyn_swizzle(cls, @selector(commandBuffer), (IMP)njyn_hook_commandBuffer);
    njyn_swizzle(cls, @selector(commandBufferWithUnretainedReferences),
                 (IMP)njyn_hook_commandBufferUnretained);
}

static id<MTLCommandQueue> njyn_hook_newCommandQueue(id self, SEL _cmd) {
    typedef id<MTLCommandQueue> (*Fn)(id, SEL);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    id<MTLCommandQueue> q = orig ? orig(self, _cmd) : nil;
    if (q) {
        if (!g_host_queue) g_host_queue = q;
        njyn_install_queue_swizzle(object_getClass(q));
    }
    return q;
}

static id<MTLCommandQueue> njyn_hook_newCommandQueueWithCount(id self, SEL _cmd, NSUInteger n) {
    typedef id<MTLCommandQueue> (*Fn)(id, SEL, NSUInteger);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    id<MTLCommandQueue> q = orig ? orig(self, _cmd, n) : nil;
    if (q) {
        if (!g_host_queue) g_host_queue = q;
        njyn_install_queue_swizzle(object_getClass(q));
    }
    return q;
}

void njyn_install_device_swizzle(Class cls) {
    njyn_swizzle(cls, @selector(newCommandQueue), (IMP)njyn_hook_newCommandQueue);
    njyn_swizzle(cls, @selector(newCommandQueueWithMaxCommandBufferCount:),
                 (IMP)njyn_hook_newCommandQueueWithCount);
}

// ---------------------------------------------------------------------------
// CAMetalLayer / MTKView entry-point hooks
// ---------------------------------------------------------------------------
static id<CAMetalDrawable> njyn_hook_nextDrawableWithError(id self, SEL _cmd, NSError** error) {
    typedef id<CAMetalDrawable> (*Fn)(id, SEL, NSError**);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    id<CAMetalDrawable> d = orig ? orig(self, _cmd, error) : nil;

    if (d && [self isKindOfClass:[CAMetalLayer class]]) {
        CAMetalLayer* layer = (CAMetalLayer*)self;
        if (layer.device) njyn_install_device_swizzle(object_getClass(layer.device));
        njyn_install_drawable_swizzle(object_getClass(d));
        njyn_imgui_setup(layer);
    }
    return d;
}

static void njyn_hook_setDevice(id self, SEL _cmd, id<MTLDevice> device) {
    if (device) {
        NSString *deviceName = [device name];
        nijuyon_log("[nijuyon] CAMetalLayer setDevice: called with device=%p (%s)\n",
                    (__bridge void*)device, deviceName.UTF8String ?: "unknown");
        njyn_install_device_swizzle(object_getClass(device));
    }
    typedef void (*Fn)(id, SEL, id<MTLDevice>);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    if (orig) orig(self, _cmd, device);
}

static id<CAMetalDrawable> njyn_hook_nextDrawable(id self, SEL _cmd) {
    typedef id<CAMetalDrawable> (*Fn)(id, SEL);
    Fn orig = (Fn)njyn_orig(self, _cmd);
    id<CAMetalDrawable> d = orig ? orig(self, _cmd) : nil;

    if (d && [self isKindOfClass:[CAMetalLayer class]]) {
        CAMetalLayer* layer = (CAMetalLayer*)self;
        if (layer.device) njyn_install_device_swizzle(object_getClass(layer.device));
        njyn_install_drawable_swizzle(object_getClass(d));
        njyn_imgui_setup(layer);
    }
    return d;
}

IMP njyn_hook_setDevice_imp(void)            { return (IMP)njyn_hook_setDevice; }
IMP njyn_hook_nextDrawable_imp(void)         { return (IMP)njyn_hook_nextDrawable; }
IMP njyn_hook_nextDrawableWithError_imp(void){ return (IMP)njyn_hook_nextDrawableWithError; }
