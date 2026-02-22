cmake_minimum_required(VERSION 3.18)
project(KintaMed_Edge CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# ═══════════════════════════════════════════════════════════════════
#  PATH ROOTS
# ═══════════════════════════════════════════════════════════════════
set(CPP_ROOT       "${CMAKE_CURRENT_SOURCE_DIR}")
set(INCLUDE_DIR    "${CPP_ROOT}/include")          # contains opencv2/
set(LIBS_DIR       "${CPP_ROOT}/libs")

# ═══════════════════════════════════════════════════════════════════
#  PLATFORM SWITCH  (Android vs Linux desktop)
# ═══════════════════════════════════════════════════════════════════
if(ANDROID)
    # ── Android ────────────────────────────────────────────────────
    # ANDROID_ABI is set automatically by the Android Gradle plugin
    # e.g. "arm64-v8a" or "armeabi-v7a"
    set(PLATFORM_LIB_DIR "${LIBS_DIR}/android/${ANDROID_ABI}")
    set(ORT_LIB_DIR      "${PLATFORM_LIB_DIR}")
    set(OGA_LIB_DIR      "${PLATFORM_LIB_DIR}")
    set(OCV_LIB_DIR      "${LIBS_DIR}/opencv/${ANDROID_ABI}")

    # Import pre-built OpenCV .so files
    foreach(LIB core imgproc imgcodecs)
        add_library(opencv_${LIB} SHARED IMPORTED)
        set_target_properties(opencv_${LIB} PROPERTIES
            IMPORTED_LOCATION "${OCV_LIB_DIR}/libopencv_${LIB}.so"
        )
    endforeach()

    set(OPENCV_LINK_LIBS opencv_core opencv_imgproc opencv_imgcodecs)
    set(PLATFORM_EXTRA_LIBS log android z jnigraphics)

else()
    # ── Linux desktop (your current working build) ──────────────────
    set(PLATFORM_LIB_DIR "${LIBS_DIR}/x64")
    set(ORT_LIB_DIR      "${PLATFORM_LIB_DIR}")
    set(OGA_LIB_DIR      "${PLATFORM_LIB_DIR}")
    set(OCV_LIB_DIR      "${LIBS_DIR}/opencv/x64")

    # On Linux we can use the headers-only approach; link against
    # the .so files that sit next to onnxruntime if you have them,
    # OR fall back to a system-installed OpenCV.
    if(EXISTS "${OCV_LIB_DIR}/libopencv_core.so")
        # Pre-built local OpenCV (mirrors the Android setup)
        foreach(LIB core imgproc imgcodecs)
            add_library(opencv_${LIB} SHARED IMPORTED)
            set_target_properties(opencv_${LIB} PROPERTIES
                IMPORTED_LOCATION "${OCV_LIB_DIR}/libopencv_${LIB}.so"
            )
        endforeach()
        set(OPENCV_LINK_LIBS opencv_core opencv_imgproc opencv_imgcodecs)
    else()
        # Fall back: use whatever OpenCV is installed on the system
        find_package(OpenCV REQUIRED core imgproc imgcodecs)
        set(OPENCV_LINK_LIBS ${OpenCV_LIBS})
    endif()

    set(PLATFORM_EXTRA_LIBS "")
endif()

# ═══════════════════════════════════════════════════════════════════
#  IMPORT  OnnxRuntime + OGA
# ═══════════════════════════════════════════════════════════════════
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION "${ORT_LIB_DIR}/libonnxruntime.so"
)

add_library(onnxruntime_genai SHARED IMPORTED)
set_target_properties(onnxruntime_genai PROPERTIES
    IMPORTED_LOCATION "${OGA_LIB_DIR}/libonnxruntime-genai.so"
)

# ═══════════════════════════════════════════════════════════════════
#  ORT / OGA HEADERS  (put onnxruntime_cxx_api.h etc. in include/)
# ═══════════════════════════════════════════════════════════════════
# Expected layout:
#   lib/cpp/include/
#     opencv2/          ← already in place
#     onnxruntime_cxx_api.h
#     ort_genai.h
#     ...

# ═══════════════════════════════════════════════════════════════════
#  MAIN LIBRARY
# ═══════════════════════════════════════════════════════════════════
add_library(medgemma_bridge SHARED
    medgemma_inference.cpp
)

target_include_directories(medgemma_bridge PRIVATE
    ${INCLUDE_DIR}          # gives "opencv2/opencv.hpp", "onnxruntime_cxx_api.h", etc.
)

target_link_libraries(medgemma_bridge PRIVATE
    ${OPENCV_LINK_LIBS}
    onnxruntime
    onnxruntime_genai
    ${PLATFORM_EXTRA_LIBS}
)

# ═══════════════════════════════════════════════════════════════════
#  OUTPUT / RPATH
# ═══════════════════════════════════════════════════════════════════
set_target_properties(medgemma_bridge PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# Linux: find sibling .so files at runtime without LD_LIBRARY_PATH
if(NOT ANDROID)
    set_target_properties(medgemma_bridge PROPERTIES
        INSTALL_RPATH "$ORIGIN"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
endif()