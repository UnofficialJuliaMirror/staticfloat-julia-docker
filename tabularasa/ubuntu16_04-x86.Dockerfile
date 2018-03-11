FROM ivochkin/ubuntu-i386:xenial

# This enables putting `linux32` before commands like `./configure` and `make`
ARG L32=linux32

INCLUDE lib/alpha
RUN apt update && apt install -y python python-dev curl build-essential unzip
RUN curl -L 'https://bootstrap.pypa.io/get-pip.py' | python
INCLUDE lib/omega
