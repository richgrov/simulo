set -e

cd vendor/onnxruntime
./build.sh --config RelWithDebInfo --parallel --compile_no_warning_as_error --skip_submodule_sync --use_vcpkg --cmake_extra_defines CMAKE_OSX_ARCHITECTURES=arm64 --cmake_generator Ninja

cd ../..

mkdir -p vendor/opencv/build
cd vendor/opencv/build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWITH_OPENCL=OFF -DWITH_ITT=OFF -DWITH_OPENEXR=OFF -DBUILD_OPENEXR=OFF -G Ninja ..
cmake --build .
cmake --install . --prefix ./install

cd ../..

cd vendor/BearSSL
make

cd ..
