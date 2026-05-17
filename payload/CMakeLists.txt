set(PAYLOAD_SOURCES
    src/payload.mm
    src/log.mm
    src/state.mm
    src/swizzle.mm
    src/hud.mm
    src/metal_hooks.mm
    src/fishhook_binds.mm
)

add_library(payload SHARED ${PAYLOAD_SOURCES})

set_target_properties(payload PROPERTIES
    PREFIX "lib"
    SUFFIX ".dylib"
    XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME OFF
)

# ImGui Obj-C overlay code uses ARC.
set_source_files_properties(${PAYLOAD_SOURCES} PROPERTIES COMPILE_FLAGS "-fobjc-arc")

# g_player is resolved at runtime via dlsym; allow undefined at link time.
target_link_options(payload PRIVATE -Wl,-undefined,dynamic_lookup)

target_link_libraries(payload PRIVATE
    fishhook
    imgui
    imgui_backends
    "-framework Cocoa"
    "-framework Metal"
    "-framework MetalKit"
    "-framework QuartzCore"
    "-framework Foundation"
)
