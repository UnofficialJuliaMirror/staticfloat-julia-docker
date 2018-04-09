## Install cmake into /usr/local
ARG cmake_version=3.6.3
ARG cmake_url=https://cmake.org/files/v3.6/cmake-${cmake_version}.tar.gz

WORKDIR /src

# Unfortunately, we have to pass `-k` to `curl` because cmake.org has weird SSL
# certificates, and old versions of `curl` can't deal with it.  :(
RUN EXTRA_CURL_FLAGS="-k" download_unpack.sh "${cmake_url}"

# Build the cmake sources!
WORKDIR /src/cmake-${cmake_version}
RUN ${L32} ./configure --prefix=/usr/local
RUN ${L32} make -j4

# Install as root
USER root
RUN ${L32} make install

# Patch cmake defaults
WORKDIR /
RUN patch -p0 < /downloads/patches/cmake_install.patch

# Now cleanup /src
WORKDIR /src
RUN rm -rf cmake-${cmake_version}
