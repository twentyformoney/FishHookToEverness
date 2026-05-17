#import "state.h"
#include <objc/runtime.h>

id<MTLDevice> g_device = nil;
__weak id<MTLCommandQueue> g_host_queue = nil;
__weak NSView* g_host_view = nil;

bool g_imgui_ready = false;
bool g_show_demo = false;
bool g_enable_capture_log = false;

__thread int g_in_imgui_draw = 0;

struct njyn_frame_stats g_frame_stats = {0, 0, 0, 0};

NSMutableSet<NSString*>* g_seen_pipelines = nil;
NSMutableSet<NSString*>* g_seen_textures = nil;
NSMutableSet<NSString*>* g_blocked_pipelines = nil;
NSMutableDictionary<NSString*, NSNumber*>* g_texture_ids = nil;
NSMutableDictionary<NSString*, NSNumber*>* g_tinted_textures = nil;
NSMutableSet<NSString*>* g_hidden_textures = nil;
uint32_t g_next_texture_id = 1;
os_unfair_lock g_seen_lock = OS_UNFAIR_LOCK_INIT;

char njyn_pipeline_assoc_key;
char njyn_enc_textures_assoc_key;

static NSMutableDictionary<NSNumber*, id<MTLTexture>>* g_tint_tex_cache = nil;
static os_unfair_lock g_tint_cache_lock = OS_UNFAIR_LOCK_INIT;

void njyn_state_init(void) {
    g_seen_pipelines    = [NSMutableSet set];
    g_seen_textures     = [NSMutableSet set];
    g_blocked_pipelines = [NSMutableSet set];
    g_texture_ids       = [NSMutableDictionary dictionary];
    g_tinted_textures   = [NSMutableDictionary dictionary];
    g_hidden_textures   = [NSMutableSet set];
    g_tint_tex_cache    = [NSMutableDictionary dictionary];
}

bool njyn_first_seen(NSMutableSet<NSString*>* set, NSString* key) {
    if (!key || !set) return false;
    bool first = false;
    os_unfair_lock_lock(&g_seen_lock);
    if (![set containsObject:key]) {
        [set addObject:key];
        first = true;
    }
    os_unfair_lock_unlock(&g_seen_lock);
    return first;
}

bool njyn_is_blocked(NSString* label) {
    if (!label) return false;
    os_unfair_lock_lock(&g_seen_lock);
    bool blocked = [g_blocked_pipelines containsObject:label];
    os_unfair_lock_unlock(&g_seen_lock);
    return blocked;
}

NSMutableDictionary<NSNumber*, NSString*>* njyn_encoder_textures(id encoder) {
    NSMutableDictionary* d = objc_getAssociatedObject(encoder, &njyn_enc_textures_assoc_key);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(encoder, &njyn_enc_textures_assoc_key, d,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}

bool njyn_encoder_has_hidden_texture(id encoder) {
    NSMutableDictionary<NSNumber*, NSString*>* d =
        objc_getAssociatedObject(encoder, &njyn_enc_textures_assoc_key);
    if (!d || d.count == 0) return false;
    bool hit = false;
    os_unfair_lock_lock(&g_seen_lock);
    if (g_hidden_textures.count > 0) {
        for (NSString* label in d.allValues) {
            if ([g_hidden_textures containsObject:label]) { hit = true; break; }
        }
    }
    os_unfair_lock_unlock(&g_seen_lock);
    return hit;
}

id<MTLTexture> njyn_solid_color_texture(uint32_t rgba) {
    if (!g_device) return nil;
    NSNumber* key = @(rgba);
    os_unfair_lock_lock(&g_tint_cache_lock);
    id<MTLTexture> t = g_tint_tex_cache[key];
    os_unfair_lock_unlock(&g_tint_cache_lock);
    if (t) return t;

    MTLTextureDescriptor* td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:1 height:1 mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    t = [g_device newTextureWithDescriptor:td];
    if (!t) return nil;
    uint8_t r = (rgba >> 24) & 0xff;
    uint8_t g = (rgba >> 16) & 0xff;
    uint8_t b = (rgba >>  8) & 0xff;
    uint8_t a =  rgba        & 0xff;
    uint8_t bgra[4] = { b, g, r, a };
    [t replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:bgra bytesPerRow:4];

    os_unfair_lock_lock(&g_tint_cache_lock);
    if (!g_tint_tex_cache[key]) g_tint_tex_cache[key] = t;
    else t = g_tint_tex_cache[key];
    os_unfair_lock_unlock(&g_tint_cache_lock);
    return t;
}
