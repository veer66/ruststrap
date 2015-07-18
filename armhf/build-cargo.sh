#!/bin/bash

# I run this in Raspbian chroot with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM chroot \
#     /chroot/raspbian/cargo /ruststrap/armhf/build-cargo.sh

set -x
set -e

: ${DIST_DIR:=~/dist}
: ${DROPBOX:=dropbox_uploader.sh}
: ${MAX_NUMBER_OF_NIGHTLIES:=10}
: ${NIGHTLY_DIR:=~/nightly}
: ${SRC_DIR:=~/cargo}

CARGO_NIGHTLY_DIR=$NIGHTLY_DIR/cargo
RUST_NIGHTLY_DIR=$NIGHTLY_DIR/rust

# update source to match upstream
cd $SRC_DIR
git checkout .
git checkout master
git pull

# optionally checkout older commit
git checkout $1
git submodule update

# apply patch to link statically against libssl
git apply $HOME/ruststrap/armhf/static-ssl.patch

# get information about HEAD
HEAD_HASH=$(git rev-parse --short HEAD)
HEAD_DATE=$(TZ=UTC date -d @$(git show -s --format=%ct HEAD) +'%Y-%m-%d')
TARBALL=cargo-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
LOGFILE=cargo-$HEAD_DATE-$HEAD_HASH.test.output.txt

## test rust and cargo nightlies
rustc -V

## build it, if compilation fails try the next nightly
cd $SRC_DIR
./configure \
    --disable-verify-install \
    --enable-nightly \
    --enable-optimize \
    --local-cargo=$HOME/bin/cargo \
    --local-rust-root=$HOME \
    --prefix=/
  make clean
  make || exit 1

## package
rm -rf $DIST_DIR/*
DESTDIR=$DIST_DIR make install
cd $DIST_DIR

# smoke test the produced cargo nightly
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:lib bin/cargo -V

tar czf ~/$TARBALL .

cd ~
TARBALL_HASH=$(sha1sum $TARBALL | tr -s ' ' | cut -d ' ' -f 1)
mv $TARBALL $TARBALL-$TARBALL_HASH.tar.gz
TARBALL=$TARBALL-$TARBALL_HASH.tar.gz

# run tests
if [ -z $DONTTEST ]; then
    cd $SRC_DIR
    uname -a > $LOGFILE
    rustc -V >> $LOGFILE
    echo >> $LOGFILE
    RUST_TEST_THREADS=1 make test -k >>$LOGFILE 2>&1 || true
fi
