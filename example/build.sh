OUT_DIR="example"
em++ $OUT_DIR/main.cc --no-entry \
    -sEXPORTED_FUNCTIONS="['_simulo__start', '_simulo__update', '_simulo__recalculate_transform', '_simulo__pose', '_simulo__drop']" \
    -sSTANDALONE_WASM=1 \
    -I$OUT_DIR/glm \
    -o $OUT_DIR/main.wasm