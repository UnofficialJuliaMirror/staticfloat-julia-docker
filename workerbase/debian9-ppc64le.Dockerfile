FROM ppc64le/debian:9

# Eliminate troublesome debian-security repos, as they dropped support for Jessie
RUN sed -i '/debian-security/d' /etc/apt/sources.list

INCLUDE lib/alpha
INCLUDE lib/builddeps_apt
INCLUDE lib/build_tools

# This enables qemu-*-static emulation on x86_64
ARG qemu_arch=ppc64le
INCLUDE lib/multiarch

INCLUDE lib/omega
