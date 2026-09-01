export PLATFORM=linux
export APPLICATION_TYPE=developer
export MAKEFLAGS="-j$(nproc)"
export CONFIG=Release
export CFLAGS="-D_GNU_SOURCE"
export CXXFLAGS="-D_GNU_SOURCE"
export PRODUCT_ID="gfxbench_gl"

./scripts/build-3rdparty.sh
./scripts/build.sh
