#!/bin/bash

# I run this in Raspbian chroot with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM \
#     chroot /chroot/raspbian/rust /ruststrap/armhf/build-rust.sh

set -x
set -e

: ${CHANNEL:=nightly}
: ${DIST_DIR:=~/dist}
: ${SRC_DIR:=~/rust}
: ${MAX_NUMBER_OF_NIGHTLIES:=10}

case $CHANNEL in
    beta | stable ) CHANNEL=--release-channel=$CHANNEL;;
    nightly) CHANNEL=;;
    *) echo "unknown release channel: $CHANNEL" && exit 1;;
esac

# Update source to upstream
cd $SRC_DIR
git checkout master
git pull

# Optionally checkout older hash
git checkout $1
git submodule update

rustc -V

# Get information about HEAD
cd $SRC_DIR
HEAD_HASH=$(git rev-parse --short HEAD)
HEAD_DATE=$(TZ=UTC date -d @$(git show -s --format=%ct HEAD) +'%Y-%m-%d')
TARBALL=rust-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
LOGFILE=rust-$HEAD_DATE-$HEAD_HASH.test.output.txt

# build it
cd build
../configure \
  $CHANNEL \
  --disable-valgrind \
  --enable-ccache \
  --enable-local-rust \
  --local-rust-root=$SNAP_DIR \
  --prefix=/ \
  --enable-llvm-static-stdcpp \
  --build=arm-unknown-linux-gnueabihf \
  --host=arm-unknown-linux-gnueabihf \
  --target=arm-unknown-linux-gnueabihf
make clean
make -j$(nproc)

# package
rm -rf $DIST_DIR/*
DESTDIR=$DIST_DIR make install -j$(nproc)
cd $DIST_DIR
tar czf ~/$TARBALL .
cd ~
TARBALL_HASH=$(sha1sum $TARBALL | tr -s ' ' | cut -d ' ' -f 1)
mv $TARBALL $TARBALL-$TARBALL_HASH.tar.gz
TARBALL=$TARBALL-$TARBALL_HASH.tar.gz

# run tests
if [ -z $DONTTEST ]; then
  cd $SRC_DIR/build
  uname -a > $LOGFILE
  echo >> $LOGFILE
  RUST_TEST_THREADS=1 timeout 7200 make check -k >>$LOGFILE 2>&1 || true
fi
