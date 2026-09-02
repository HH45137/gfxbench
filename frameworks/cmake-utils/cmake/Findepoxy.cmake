# Findepoxy.cmake
#
# On developer machines, build_windows.bat generates a per-machine bridge in
# _Findepoxy.cmake (an alias file listed in .gitignore) that hard-codes the local
# 3rdparty libepoxy build. If that bridge exists, use it first. Otherwise fall
# back to the in-tree epoxy-config.cmake produced by the libepoxy build.

if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/_Findepoxy.cmake")
    include("${CMAKE_CURRENT_LIST_DIR}/_Findepoxy.cmake")
    if(epoxy_FOUND OR EPOXY_FOUND)
        return()
    endif()
endif()

# Fall back to the epoxy-config.cmake that the 3rdparty/libepoxy CMake build
# places in its build tree.
find_package(epoxy CONFIG QUIET)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(epoxy DEFAULT_MSG epoxy_LIBRARIES epoxy_INCLUDE_DIRS)
