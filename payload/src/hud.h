#pragma once

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// One-time ImGui init: requires the layer's device and the host's NSView.
// Safe to call from any thread; bounces to main if needed.
void njyn_imgui_setup(CAMetalLayer* layer);

// Renders our overlay into the same drawable the host is about to present.
// No-op if ImGui isn't ready or args are nil.
void njyn_draw_imgui(id<MTLCommandBuffer> cb, id<CAMetalDrawable> drawable);
