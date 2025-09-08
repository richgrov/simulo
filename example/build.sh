em++ example/main.cc --no-entry \
    -sEXPORTED_FUNCTIONS="['_simulo_main', '_simulo__update', '_simulo__recalculate_transform', '_simulo__pose', '_simulo__drop']" \
    -sSTANDALONE_WASM=1 \
    -Iexample/glm \
    -o example/main.wasm