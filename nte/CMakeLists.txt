add_executable(nte MACOSX_BUNDLE
    src/main.mm
)

set_target_properties(nte PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in
    MACOSX_BUNDLE_BUNDLE_NAME "HTGame-IOS-Shipping"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.hottagaems.nte"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0.7"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1"
    XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME OFF
)

# Critical: dlsym from payload needs g_player visible in the export trie.
# macOS analog of GNU -rdynamic.
target_link_options(nte PRIVATE -Wl,-export_dynamic)

target_include_directories(nte PRIVATE include)

target_link_libraries(nte PRIVATE
    "-framework Cocoa"
    "-framework Metal"
    "-framework MetalKit"
    "-framework QuartzCore"
)
