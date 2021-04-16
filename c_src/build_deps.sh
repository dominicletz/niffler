#!/bin/bash
cd c_src/tinycc
./configure
make CFLAGS="-O3 -fPIC" LDFLAGS=-fPIC libtcc.a