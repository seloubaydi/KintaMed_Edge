cmake_minimum_required(VERSION 3.13)
project(KintaMed_Edge CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- 1. Find OpenCV ---
find_package(OpenCV REQUIRED)

# --- 2. Include Directories ---
include_directories(
    ${OpenCV_INCLUDE_DIRS}
    ./include
    .
)

# Reference existing libraries
link_directories(${CMAKE_CURRENT_SOURCE_DIR}/libs/x64)

# Create shared library using the NEW inference file
add_library(medgemma_bridge SHARED
    ../../lib/cpp/medgemma_inference.cpp
)

# Link against ONNX Runtime, GenAI, and OpenCV
target_link_libraries(medgemma_bridge PRIVATE
    ${OpenCV_LIBS}
    ${CMAKE_CURRENT_SOURCE_DIR}/libs/x64/libonnxruntime-genai.so
    ${CMAKE_CURRENT_SOURCE_DIR}/libs/x64/libonnxruntime.so
)

# LIBRARY_OUTPUT_DIRECTORY ensures it's in the build directory for development
set_target_properties(medgemma_bridge PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    INSTALL_RPATH "$ORIGIN"
)
