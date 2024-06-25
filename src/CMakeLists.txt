if (WIN32)
    set(OS_SPECIFIC_FILES
        "window/win32/window.cc"
        "window/win32/window.h"
    )
endif()

add_executable(villa 
   "window/window.h"
   "app.cc"
   "app.h"
   "main.cc"
   ${OS_SPECIFIC_FILES}
)

set_property(TARGET villa PROPERTY CXX_STANDARD 20)
