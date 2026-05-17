#pragma once

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include <os/lock.h>
#include <stdbool.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Shared mutable state. Touched by both the HUD and the Metal hooks.
// ---------------------------------------------------------------------------

// Live MTLDevice / queue / host view. Captured as the host hands them to us.
extern id<MTLDevice> g_device;
extern __weak id<MTLCommandQueue> g_host_queue;
extern __weak NSView* g_host_view;

extern bool g_imgui_ready;
extern bool g_show_hud;
extern bool g_show_demo;
extern bool g_enable_capture_log;

// Thread-local: non-zero while we're rendering our own ImGui overlay. Metal
// hooks check this so our own draws don't get counted / blocked.
extern __thread int g_in_imgui_draw;

struct njyn_frame_stats {
    uint64_t draw_calls;
    uint64_t indexed_draws;
    uint64_t pipeline_changes;
    uint64_t compute_dispatch;
};
extern struct njyn_frame_stats g_frame_stats;

// RE inventories. All guarded by g_seen_lock.
extern NSMutableSet<NSString*>* g_seen_pipelines;
extern NSMutableSet<NSString*>* g_seen_textures;
extern NSMutableSet<NSString*>* g_blocked_pipelines;
extern NSMutableDictionary<NSString*, NSNumber*>* g_texture_ids;      // label -> stable ID
extern NSMutableDictionary<NSString*, NSNumber*>* g_tinted_textures;  // label -> packed RGBA8
extern NSMutableSet<NSString*>* g_hidden_textures;
extern uint32_t g_next_texture_id;
extern os_unfair_lock g_seen_lock;

// Associated-object keys for per-encoder metadata. metal_hooks reads/writes
// these via objc_{get,set}AssociatedObject.
extern char njyn_pipeline_assoc_key;
extern char njyn_enc_textures_assoc_key;

// Initializes every collection above. Must be called once before any other
// state-accessing function.
void njyn_state_init(void);

// ---------------------------------------------------------------------------
// Lock-protected helpers over the inventories.
// ---------------------------------------------------------------------------

// True if `key` was not previously in `set`. Adds it as a side effect.
bool njyn_first_seen(NSMutableSet<NSString*>* set, NSString* key);

// True if the user has toggled this pipeline off in the HUD.
bool njyn_is_blocked(NSString* label);

// Per-encoder fragment-slot -> texture-label map, lazily attached.
NSMutableDictionary<NSNumber*, NSString*>* njyn_encoder_textures(id encoder);

// True if any fragment texture currently bound on `encoder` is in g_hidden_textures.
bool njyn_encoder_has_hidden_texture(id encoder);

// Get-or-create a 1x1 BGRA8Unorm texture filled with `rgba` (R<<24|G<<16|B<<8|A).
// Used to replace ("tint") a bound texture.
id<MTLTexture> njyn_solid_color_texture(uint32_t rgba);
