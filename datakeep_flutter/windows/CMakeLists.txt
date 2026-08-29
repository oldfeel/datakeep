# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(datakeep_flutter LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "datakeep_flutter")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# windows-latest（VS 2026 / MSVC 14.51）：permission_handler 等仍引用 experimental/coroutine
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
# media_kit_video：MPV API 把字符串字面量当作 void*（MSVC 默认 strictStrings 会 C2440）
add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:/Zc:strictStrings->")
# 中文系统代码页 936：UTF-8 源文件（含中文注释）否则会 C4819，再被 /WX 升级为 C2220
add_compile_options(/utf-8 /wd4819)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  # 默认 C++17：share_plus 自带的旧 WRL vector.h 在 C++20 / 新 MSVC 下无法编译
  # （ElementType / typename 等）；webview_cef 与主程序在下方单独升到 C++20
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  # /wd4596：share_plus 头文件误写 SharePlusWindowsPlugin::Utf16FromUtf8
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100" /wd"4596")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# CEF 149 Release 版 libcef.dll 在本机 LoadLibrary 返回 193（0xC000007B）；
# Debug 版可正常加载。须在 include 插件（下载/配置 CEF）之前打开。
set(WEBVIEW_CEF_USE_DEBUG_CEF ON CACHE BOOL
  "Use CEF Debug binaries; Release libcef fails to load on some Windows hosts" FORCE)

# CEF 149 设置 NTDDI_VERSION=NTDDI_WIN10_FE。Windows SDK 10.0.19041 没有该宏，
# 未定义时 NTDDI_VERSION 展开为 0，fileapi.h / wintrust.h 会裁掉 Vista+ 类型，
# 编译 libcef_dll_wrapper 时报 FILE_INFO_BY_HANDLE_CLASS / WINTRUST_SIGNATURE_SETTINGS。
# 须在插件（含 CEF wrapper）目标创建之前补定义。
if(WIN32)
  set(_dk_sdk_ver "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
  if(NOT _dk_sdk_ver AND DEFINED ENV{WindowsSDKVersion})
    string(REGEX REPLACE "[\\]$" "" _dk_sdk_ver "$ENV{WindowsSDKVersion}")
  endif()
  set(_dk_sdkddkver "")
  foreach(_dk_kits
      "C:/Program Files (x86)/Windows Kits/10/Include"
      "C:/Program Files/Windows Kits/10/Include")
    if(_dk_sdk_ver AND EXISTS "${_dk_kits}/${_dk_sdk_ver}/shared/sdkddkver.h")
      set(_dk_sdkddkver "${_dk_kits}/${_dk_sdk_ver}/shared/sdkddkver.h")
      break()
    endif()
  endforeach()
  if(NOT _dk_sdkddkver AND EXISTS
      "C:/Program Files (x86)/Windows Kits/10/Include/10.0.19041.0/shared/sdkddkver.h")
    set(_dk_sdkddkver
      "C:/Program Files (x86)/Windows Kits/10/Include/10.0.19041.0/shared/sdkddkver.h")
    set(_dk_sdk_ver "10.0.19041.0")
  endif()
  if(_dk_sdkddkver)
    file(STRINGS "${_dk_sdkddkver}" _dk_has_fe REGEX "#define[ \t]+NTDDI_WIN10_FE")
    if(NOT _dk_has_fe)
      message(STATUS "Windows SDK ${_dk_sdk_ver} 无 NTDDI_WIN10_FE，补定义为 0x0A00000A（CEF 149）")
      add_compile_definitions(NTDDI_WIN10_FE=0x0A00000A)
    endif()
  endif()
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# webview_cef / CEF 149 需要 C++20（须在插件目标创建之后设置）
target_compile_features(${BINARY_NAME} PUBLIC cxx_std_20)
if(TARGET webview_cef_plugin)
  target_compile_features(webview_cef_plugin PUBLIC cxx_std_20)
  # CEF 149：libcef 导入表被加密，须由 chrome_elf 在进程启动早期挂钩后再加载。
  # 插件硬链 libcef 会在 DLL 依赖解析阶段 0xC000007B，故改为 DELAYLOAD。
  target_link_options(webview_cef_plugin PRIVATE "/DELAYLOAD:libcef.dll")
  target_link_libraries(webview_cef_plugin PRIVATE delayimp)

  # EXE 硬依赖 chrome_elf.dll（import lib 由 runner/chrome_elf.def 生成）
  set(_dk_chrome_elf_lib "${CMAKE_CURRENT_SOURCE_DIR}/runner/chrome_elf.lib")
  if(EXISTS "${_dk_chrome_elf_lib}")
    target_link_libraries(${BINARY_NAME} PRIVATE "${_dk_chrome_elf_lib}")
    target_link_options(${BINARY_NAME} PRIVATE "/INCLUDE:GetApplyHookResult")
    message(STATUS "Linked chrome_elf.lib for CEF 149 early load")
  else()
    message(WARNING "缺少 runner/chrome_elf.lib，CEF 可能无法启动；可用 lib.exe /def:chrome_elf.def 重新生成")
  endif()
endif()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# 捆绑桌面 Syncthing（与 Linux data/bin 一致；由 scripts/build_desktop_syncthing.sh 生成）
set(BIN_DIR "${CMAKE_SOURCE_DIR}/../bin")
if(EXISTS "${BIN_DIR}/syncthing.exe")
  install(FILES "${BIN_DIR}/syncthing.exe"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/bin"
    COMPONENT Runtime)
  message(STATUS "Found syncthing.exe, will bundle with application")
elseif(EXISTS "${BIN_DIR}/syncthing")
  install(FILES "${BIN_DIR}/syncthing"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/bin"
    RENAME "syncthing.exe"
    COMPONENT Runtime)
  message(STATUS "Found syncthing (no .exe suffix), will bundle as syncthing.exe")
endif()
