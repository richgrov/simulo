add_executable(example main.cc)
target_link_libraries(example villa)
set_property(TARGET example PROPERTY CXX_STANDARD 20)
