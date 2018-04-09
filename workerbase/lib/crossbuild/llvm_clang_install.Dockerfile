WORKDIR /src/llvm-${llvm_ver}_build    

RUN source /build.sh; \
    cmake -G "Unix Makefiles" \
        -DLLVM_TARGETS_TO_BUILD:STRING=host \
        -DLLVM_PARALLEL_COMPILE_JOBS=${nproc} \
        -DLLVM_BINDINGS_LIST="" \
        -DLLVM_DEFAULT_TARGET_TRIPLE=$(target_to_clang_target ${compiler_target}) \
        -DDEFAULT_SYSROOT="$(get_sysroot)" \
        -DGCC_INSTALL_PREFIX="/opt/${compiler_target}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_ASSERTIONS=Off \
        -DCMAKE_INSTALL_PREFIX="/opt/${compiler_target}" \
        -DLIBCXX_HAS_MUSL_LIBC=On \
        -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
        "/src/llvm-${llvm_ver}"

RUN make -j${nproc}
RUN make install

# Cleanup
WORKDIR /src
RUN rm -rf /src/llvm-${llvm_ver}*