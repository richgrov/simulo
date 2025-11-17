set -e

mkdir -p vendor/opencv/build
cd vendor/opencv/build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWITH_OPENCL=OFF -DWITH_ITT=OFF -DWITH_OPENEXR=OFF -DBUILD_OPENEXR=OFF -G Ninja ..
cmake --build .
cmake --install . --prefix ./install
