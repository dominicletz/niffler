#!/bin/bash
cd c_src/tinycc
./configure
make CFLAGS=-fPIC LDFLAGS=-fPIC libtcc.a