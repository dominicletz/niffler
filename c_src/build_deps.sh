#!/bin/bash
cd c_src/tinycc
./configure
make ONE_SOURCE=yes CFLAGS="-O3 -fPIC" LDFLAGS="-fPIC" libtcc.a