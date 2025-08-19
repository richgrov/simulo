em++ main.cc --no-entry \
    -sEXPORTED_FUNCTIONS="['_simulo__start', '_simulo__update', '_simulo__recalculate_transform', '_simulo__pose', '_simulo__drop']" \
    -sSTANDALONE_WASM=1 \
    -Iglm \
    -o main.wasm