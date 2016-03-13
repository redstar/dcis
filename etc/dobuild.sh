#!/bin/bash -x

# Set save path
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin:/usr/armv7a-hardfloat-linux-gnueabi/gcc-bin/4.9.3:/usr/src/build-ldc/bin

# Checkout repository
git clone --recursive $1 || exit 1
cd $2 || exit 1
git checkout $3 || exit 1

# Build the project
dub build -v
