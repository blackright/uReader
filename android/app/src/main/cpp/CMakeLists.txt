cmake_minimum_required(VERSION 3.22)
project(ureader_french_frontend VERSION 1.52.0 LANGUAGES C CXX)

if(NOT EXISTS "${ESPEAK_SOURCE_DIR}/src/include/espeak-ng/speak_lib.h")
    message(FATAL_ERROR "Pinned eSpeak source is required for the Kokoro frontend")
endif()
file(SHA256 "${ESPEAK_SOURCE_DIR}/CMakeLists.txt" ESPEAK_BUILD_SHA256)
if(NOT ESPEAK_BUILD_SHA256 STREQUAL "93a940dbd943b0403d360fc23865a924abf6a934a95585a8235bad51b9095d97")
    message(FATAL_ERROR "Use pinned eSpeak 1.52.0 source 4870adfa25b1a32b4361592f1be8a40337c58d6c; another revision changes pronunciation")
endif()
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(COMPILE_INTONATIONS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(USE_MBROLA OFF CACHE BOOL "" FORCE)
set(USE_LIBSONIC OFF CACHE BOOL "" FORCE)
set(USE_LIBPCAUDIO OFF CACHE BOOL "" FORCE)
set(USE_ASYNC OFF CACHE BOOL "" FORCE)
set(USE_SPEECHPLAYER OFF CACHE BOOL "" FORCE)
# Upstream probes/fetches sonic before applying USE_LIBSONIC. Prevent an implicit
# download; the disabled audio speed processor is not used for phonemization.
set(SONIC_LIB m CACHE STRING "" FORCE)
set(SONIC_INC "${ESPEAK_SOURCE_DIR}/src/include" CACHE PATH "" FORCE)
# Include only the library sources: upstream 1.52.0's root also runs host data
# generators and tests, which cannot be executed while cross-compiling Android.
include("${ESPEAK_SOURCE_DIR}/cmake/deps.cmake")
include("${ESPEAK_SOURCE_DIR}/cmake/config.cmake")
add_subdirectory("${ESPEAK_SOURCE_DIR}/src" espeak EXCLUDE_FROM_ALL)
# Android private paths plus the content-addressed frontend directory exceed
# the upstream POSIX default (160). Use its supported override consistently.
target_compile_definitions(espeak-ng PRIVATE N_PATH_HOME=1024)
add_library(ureader_french SHARED french_frontend.cpp)
target_compile_features(ureader_french PRIVATE cxx_std_17)
# Do not propagate eSpeak's C compatibility headers into libc++ (<string>
# includes <wctype.h>, which the upstream compatibility directory shadows).
target_include_directories(ureader_french PRIVATE "${ESPEAK_SOURCE_DIR}/src/include")
add_dependencies(ureader_french espeak-ng)
target_link_libraries(ureader_french PRIVATE "$<TARGET_FILE:espeak-ng>" ucd m)
