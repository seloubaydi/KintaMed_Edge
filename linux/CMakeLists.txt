# Project-level configuration.
cmake_minimum_required(VERSION 3.13)

# Set local install prefix early to avoid system-wide install failures
# This must be done before project() for best effect.
set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/bundle" CACHE PATH "..." FORCE)

project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "KintaMed_edge")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.KintaMed.KintaMed_edge")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Bundle directory definitions (must be at the top for subproject visibility)
set(INSTALL_BUNDLE_LIB_DIR "lib")
set(INSTALL_BUNDLE_DATA_DIR "data")
set(INSTALL_BUNDLE_BIN_DIR ".")

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)

# Build the medgemma_bridge library
add_subdirectory("cpp")

# Link the bridge and its dependencies to the main application
target_link_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/cpp/libs/x64")
# target_link_libraries(${BINARY_NAME} PRIVATE medgemma_bridge)

# Generated plugin build rules
include(flutter/generated_plugins.cmake)

# === Installation ===
# Standard Flutter installation logic

# Install the main binary
install(TARGETS ${BINARY_NAME} DESTINATION "." COMPONENT Runtime)

# Install the bundled libraries from plugins
if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES ${PLUGIN_BUNDLED_LIBRARIES}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Install the Flutter library
install(FILES "${FLUTTER_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Install the ICU data file
install(FILES "${FLUTTER_ICU_DATA_FILE}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by any build.dart
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
if(EXISTS "${NATIVE_ASSETS_DIR}")
  install(DIRECTORY "${NATIVE_ASSETS_DIR}"
     DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
     COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# === Custom Installation for MedGemma ===
install(TARGETS medgemma_bridge
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES 
  "${CMAKE_CURRENT_SOURCE_DIR}/cpp/libs/x64/libonnxruntime-genai.so"
  "${CMAKE_CURRENT_SOURCE_DIR}/cpp/libs/x64/libonnxruntime.so"
  "${CMAKE_CURRENT_SOURCE_DIR}/cpp/libs/x64/libonnxruntime_providers_shared.so"
  "${CMAKE_CURRENT_SOURCE_DIR}/cpp/libs/x64/libonnxruntime.so.1"
  "${CMAKE_CURRENT_SOURCE_DIR}/cpp/libs/x64/libonnxruntime-genai.so.0"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Bundle system sqlite3 for Linux
find_library(SQLITE3_LIB NAMES sqlite3)
if(SQLITE3_LIB)
  get_filename_component(SQLITE3_REAL_PATH ${SQLITE3_LIB} REALPATH)
  install(FILES "${SQLITE3_REAL_PATH}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    RENAME "libsqlite3.x64.linux.so"
    COMPONENT Runtime)
else()
  # Fallback if find_library fails
  install(FILES "/usr/lib/x86_64-linux-gnu/libsqlite3.so.0"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    RENAME "libsqlite3.x64.linux.so"
    COMPONENT Runtime)
endif()
