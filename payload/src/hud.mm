#import "hud.h"
#import "state.h"
#import "log.h"

#import <Cocoa/Cocoa.h>
#include <string.h>

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

static dispatch_once_t g_imgui_once;
static os_unfair_lock g_imgui_lock = OS_UNFAIR_LOCK_INIT;

static NSView* njyn_find_host_view(CAMetalLayer* layer) {
    if ([layer.delegate isKindOfClass:[NSView class]]) return (NSView*)layer.delegate;
    NSWindow* w = NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
    return w.contentView;
}

void njyn_imgui_setup(CAMetalLayer* layer) {
    dispatch_once(&g_imgui_once, ^{
        void (^setup)(void) = ^{
            g_device = layer.device;
            NSView* view = njyn_find_host_view(layer);
            g_host_view = view;

            IMGUI_CHECKVERSION();
            ImGui::CreateContext();
            ImGuiIO& io = ImGui::GetIO();
            io.IniFilename = nullptr;
            io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
            ImGui::StyleColorsDark();

            ImGui_ImplMetal_Init(g_device);
            if (view) ImGui_ImplOSX_Init(view);

            g_imgui_ready = (view != nil && g_device != nil);
            nijuyon_log("[nijuyon] ImGui ready (device=%p view=%p)\n",
                        (__bridge void*)g_device, (__bridge void*)view);
        };
        if (NSThread.isMainThread) setup();
        else dispatch_sync(dispatch_get_main_queue(), setup);
    });
}

void njyn_draw_imgui(id<MTLCommandBuffer> cb, id<CAMetalDrawable> drawable) {
    if (!g_imgui_ready || !cb || !drawable) return;
    NSView* view = g_host_view;
    if (!view) return;

    if (!os_unfair_lock_trylock(&g_imgui_lock)) return;
    g_in_imgui_draw = 1;
    @try {
        MTLRenderPassDescriptor* rpd = [MTLRenderPassDescriptor renderPassDescriptor];
        rpd.colorAttachments[0].texture = drawable.texture;
        rpd.colorAttachments[0].loadAction = MTLLoadActionLoad;
        rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rpd];
        [enc pushDebugGroup:@"nijuyon ImGui"];

        ImGui_ImplMetal_NewFrame(rpd);
        ImGui_ImplOSX_NewFrame(view);
        ImGui::NewFrame();

        ImGui::SetNextWindowPos(ImVec2(20, 20), ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(440, 520), ImGuiCond_FirstUseEver);
        ImGui::Begin("nijuyon HUD");
        ImGui::Text("Injected via dyld");
        ImGui::Text("FPS:   %.1f", ImGui::GetIO().Framerate);
        ImGui::Text("Frame: %d", ImGui::GetFrameCount());
        ImGui::Text("Draws=%llu  Indexed=%llu  PSO sets=%llu",
                    g_frame_stats.draw_calls, g_frame_stats.indexed_draws, g_frame_stats.pipeline_changes);
        ImGui::Separator();
        ImGui::Checkbox("Show ImGui demo", &g_show_demo);
        ImGui::Checkbox("Log every draw (verbose!)", &g_enable_capture_log);

        os_unfair_lock_lock(&g_seen_lock);
        NSArray<NSString*>* pipelines = [g_seen_pipelines.allObjects sortedArrayUsingSelector:@selector(compare:)];
        NSArray<NSString*>* textures  = [g_seen_textures.allObjects sortedArrayUsingSelector:@selector(compare:)];
        NSSet<NSString*>*   blocked   = [g_blocked_pipelines copy];
        NSDictionary<NSString*, NSNumber*>* tex_ids   = [g_texture_ids copy];
        NSDictionary<NSString*, NSNumber*>* tex_tints = [g_tinted_textures copy];
        NSSet<NSString*>* tex_hidden = [g_hidden_textures copy];
        os_unfair_lock_unlock(&g_seen_lock);

        textures = [textures sortedArrayUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
            uint32_t ia = tex_ids[a].unsignedIntValue;
            uint32_t ib = tex_ids[b].unsignedIntValue;
            if (ia < ib) return NSOrderedAscending;
            if (ia > ib) return NSOrderedDescending;
            return NSOrderedSame;
        }];

        if (ImGui::CollapsingHeader("Pipelines — tick to hide draws", ImGuiTreeNodeFlags_DefaultOpen)) {
            ImGui::Text("Total: %d  (blocked: %d)", (int)pipelines.count, (int)blocked.count);
            ImGui::BeginChild("pipelist", ImVec2(0, 220), true);
            for (NSString* label in pipelines) {
                ImGui::PushID(label.UTF8String);
                bool is_blocked = [blocked containsObject:label];
                bool was = is_blocked;
                ImGui::Checkbox(label.UTF8String, &is_blocked);
                if (is_blocked != was) {
                    os_unfair_lock_lock(&g_seen_lock);
                    if (is_blocked) [g_blocked_pipelines addObject:label];
                    else            [g_blocked_pipelines removeObject:label];
                    os_unfair_lock_unlock(&g_seen_lock);
                    nijuyon_log("[nijuyon] pipeline '%s' -> %s",
                                label.UTF8String, is_blocked ? "BLOCKED" : "allowed");
                }
                ImGui::PopID();
            }
            ImGui::EndChild();
        }

        if (ImGui::CollapsingHeader("Textures — Tint replaces with solid color, Hide skips draw")) {
            ImGui::Text("Total: %d  (tinted: %d, hidden: %d)",
                        (int)textures.count, (int)tex_tints.count, (int)tex_hidden.count);
            ImGui::BeginChild("texlist", ImVec2(0, 260), true);
            for (NSString* label in textures) {
                ImGui::PushID(label.UTF8String);
                uint32_t id_num = tex_ids[label].unsignedIntValue;
                NSNumber* tint_num = tex_tints[label];
                bool tint_on = (tint_num != nil);
                bool was_tint_on = tint_on;
                bool hidden = [tex_hidden containsObject:label];
                bool was_hidden = hidden;

                float col[4];
                if (tint_num) {
                    uint32_t v = (uint32_t)tint_num.unsignedIntValue;
                    col[0] = ((v >> 24) & 0xff) / 255.0f;
                    col[1] = ((v >> 16) & 0xff) / 255.0f;
                    col[2] = ((v >>  8) & 0xff) / 255.0f;
                    col[3] = ( v        & 0xff) / 255.0f;
                } else {
                    col[0] = 1.0f; col[1] = 0.0f; col[2] = 1.0f; col[3] = 1.0f;
                }

                ImGui::Checkbox("Tint", &tint_on);
                ImGui::SameLine();
                bool col_changed = ImGui::ColorEdit4(
                    "##color", col,
                    ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_NoLabel | ImGuiColorEditFlags_AlphaPreview);
                ImGui::SameLine();
                ImGui::Checkbox("Hide", &hidden);
                ImGui::SameLine();
                ImGui::Text("#%u %s", id_num, label.UTF8String);

                if (tint_on != was_tint_on || (tint_on && col_changed)) {
                    uint32_t packed = ((uint32_t)(col[0] * 255.0f) << 24)
                                    | ((uint32_t)(col[1] * 255.0f) << 16)
                                    | ((uint32_t)(col[2] * 255.0f) <<  8)
                                    | ((uint32_t)(col[3] * 255.0f));
                    os_unfair_lock_lock(&g_seen_lock);
                    if (tint_on) g_tinted_textures[label] = @(packed);
                    else         [g_tinted_textures removeObjectForKey:label];
                    os_unfair_lock_unlock(&g_seen_lock);
                    nijuyon_log("[nijuyon] texture #%u '%s' tint -> %s",
                                id_num, label.UTF8String, tint_on ? "ON" : "off");
                }
                if (hidden != was_hidden) {
                    os_unfair_lock_lock(&g_seen_lock);
                    if (hidden) [g_hidden_textures addObject:label];
                    else        [g_hidden_textures removeObject:label];
                    os_unfair_lock_unlock(&g_seen_lock);
                    nijuyon_log("[nijuyon] texture #%u '%s' -> %s",
                                id_num, label.UTF8String, hidden ? "HIDDEN" : "visible");
                }
                ImGui::PopID();
            }
            ImGui::EndChild();
        }
        ImGui::End();

        if (g_show_demo) ImGui::ShowDemoWindow(&g_show_demo);

        ImGui::Render();
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);

        [enc popDebugGroup];
        [enc endEncoding];

        memset(&g_frame_stats, 0, sizeof(g_frame_stats));
    } @catch (NSException* e) {
        nijuyon_log("[nijuyon] imgui draw exception: %s", e.reason.UTF8String);
    }
    g_in_imgui_draw = 0;
    os_unfair_lock_unlock(&g_imgui_lock);
}
