cmake_minimum_required(VERSION 3.14)
project(KintaMed_Edge_Bridge CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Include Directories ---
# Reuse the headers from the linux/cpp/include tree which contains:
#   onnxruntime_cxx_api.h, ort_genai.h, stb_image.h, stb_image_resize2.h, etc.
set(BRIDGE_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../linux/cpp/include")

include_directories(
    ${BRIDGE_INCLUDE_DIR}
    ${BRIDGE_INCLUDE_DIR}/core
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Windows ONNX Runtime / GenAI import libraries (.lib) must be in libs/x64/
set(BRIDGE_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libs/x64")
link_directories(${BRIDGE_LIB_DIR})

# --- Build medgemma_bridge.dll ---
add_library(medgemma_bridge SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/../../lib/cpp/medgemma_inference.cpp"
)

# Export symbols on MSVC via the __declspec(dllexport) macros in the source
# (the source already has #ifdef _WIN32 #define EXPORT __declspec(dllexport))
target_compile_definitions(medgemma_bridge PRIVATE
    _CRT_SECURE_NO_WARNINGS
    NOMINMAX
)

# Link against ONNX Runtime import libraries (.lib files for the DLLs)
target_link_libraries(medgemma_bridge PRIVATE
    "${BRIDGE_LIB_DIR}/onnxruntime.lib"
    "${BRIDGE_LIB_DIR}/onnxruntime-genai.lib"
)

# Put the DLL into the standard CMake binary output dir
set_target_properties(medgemma_bridge PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/medgemma_bridge"
    # Ensure we don't get the lib prefix on Windows
    PREFIX ""
)
