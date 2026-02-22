cmake_minimum_required(VERSION 3.10)
project(medgemma_bridge LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(BRIDGE_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../lib/cpp)
set(JNI_LIBS_DIR   ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

include_directories(
    ${BRIDGE_SRC_DIR}
    ${BRIDGE_SRC_DIR}/include
)

add_library(onnxruntime-genai SHARED IMPORTED)
set_target_properties(onnxruntime-genai PROPERTIES
    IMPORTED_LOCATION ${JNI_LIBS_DIR}/libonnxruntime-genai.so)

add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION ${JNI_LIBS_DIR}/libonnxruntime.so)

add_library(medgemma_bridge SHARED
    ${BRIDGE_SRC_DIR}/medgemma_inference.cpp
)

target_link_libraries(medgemma_bridge PRIVATE
    onnxruntime-genai
    onnxruntime
    log
    z
    jnigraphics
)

set_target_properties(medgemma_bridge PROPERTIES CXX_VISIBILITY_PRESET default)

target_link_options(medgemma_bridge PRIVATE
    "-Wl,--export-dynamic"
    "-Wl,--undefined=load_medgemma_4bit"
    "-Wl,--undefined=unload_medgemma"
    "-Wl,--undefined=run_medgemma_inference"
    "-Wl,--undefined=medgemma_tokenize"
)