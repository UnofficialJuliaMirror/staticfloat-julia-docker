FROM staticfloat/centos-i386:centos6

# This enables putting `linux32` before commands like `./configure` and `make`
ARG L32=linux32

INCLUDE lib/alpha
INCLUDE lib/builddeps_yum
INCLUDE lib/build_tools

COPY build_crosscompiler.sh /build.sh
COPY patches /downloads/patches

# Also install windows cross-compilers
ENV target="x86_64-w64-mingw32"
USER buildworker
INCLUDE lib/win_crosscompiler_install
ENV target=

# Install Wine
USER root
RUN yum install -y libstdc++ flex bison
USER buildworker
INCLUDE lib/wine_install
ENV WINEARCH=win32

INCLUDE lib/omega
