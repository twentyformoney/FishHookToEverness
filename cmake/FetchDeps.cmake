include(FetchContent)

# ---------- ImGui (vendored at vendor/imgui) ----------
set(IMGUI_DIR ${CMAKE_SOURCE_DIR}/vendor/imgui)

if(NOT EXISTS ${IMGUI_DIR}/imgui.cpp)
    message(FATAL_ERROR "vendored ImGui not found at ${IMGUI_DIR}")
endif()

add_library(imgui STATIC
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/imgui_demo.cpp
)
target_include_directories(imgui PUBLIC ${IMGUI_DIR})

# Metal + OSX backends. ARC required by imgui_impl_osx.mm (modern ImGui).
add_library(imgui_backends STATIC
    ${IMGUI_DIR}/backends/imgui_impl_metal.mm
    ${IMGUI_DIR}/backends/imgui_impl_osx.mm
)
target_include_directories(imgui_backends PUBLIC ${IMGUI_DIR} ${IMGUI_DIR}/backends)
target_link_libraries(imgui_backends PUBLIC imgui)
target_link_libraries(imgui_backends PUBLIC
    "-framework Cocoa"
    "-framework Metal"
    "-framework MetalKit"
    "-framework QuartzCore"
    "-framework GameController"
)
set_source_files_properties(
    ${IMGUI_DIR}/backends/imgui_impl_osx.mm
    ${IMGUI_DIR}/backends/imgui_impl_metal.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc"
)

# ---------- fishhook (FetchContent) ----------
FetchContent_Declare(
    fishhook
    GIT_REPOSITORY https://github.com/facebook/fishhook.git
    GIT_TAG main
)
FetchContent_MakeAvailable(fishhook)

# fishhook ships without a CMakeLists; build it ourselves.
if(NOT TARGET fishhook)
    add_library(fishhook STATIC ${fishhook_SOURCE_DIR}/fishhook.c)
    target_include_directories(fishhook PUBLIC ${fishhook_SOURCE_DIR})
endif()
