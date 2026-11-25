# Test fixtures that more than one part of the build needs.

# d3d12_xs_stub: d3d12_xs.dll with an import library, for the stand-in titles that import
# d3d12_xs.dll!D3D12XboxCreateDevice (tiny_frame, tiny_guest_draw). It is built into fixtures/stubs, away from the
# guests, so at run time only gta6rt's shim registry can answer the import. Callable from any directory; the target
# is created by the first call.
function(leonida_add_d3d12_xs_stub)
  if(TARGET d3d12_xs_stub)
    return()
  endif()
  add_library(d3d12_xs_stub SHARED
    "${PROJECT_SOURCE_DIR}/test/fixtures/d3d12_xs_stub.cpp"
    "${PROJECT_SOURCE_DIR}/test/fixtures/d3d12_xs_stub.def"
  )
  target_compile_definitions(d3d12_xs_stub PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_xs_stub PRIVATE /W4 /permissive- /utf-8)
  set_target_properties(d3d12_xs_stub PROPERTIES
    OUTPUT_NAME d3d12_xs
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/fixtures/stubs/$<CONFIG>"
    ARCHIVE_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/fixtures/stubs/$<CONFIG>"
  )
endfunction()
