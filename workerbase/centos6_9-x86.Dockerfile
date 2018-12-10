FROM staticfloat/centos-i386:centos6

# This enables putting `linux32` before commands like `./configure` and `make`
ARG L32=linux32

INCLUDE lib/alpha
INCLUDE lib/builddeps_yum
INCLUDE lib/build_tools

COPY build_crosscompiler.sh /build.sh
COPY patches /downloads/patches

INCLUDE lib/omega
