add_library(payload SHARED
    src/payload.mm
)

set_target_properties(payload PROPERTIES
    PREFIX "lib"
    SUFFIX ".dylib"
    XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME OFF
)

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
