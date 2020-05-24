SHELL:=/bin/bash

base_dir := $(abspath ..)
src_dir := $(abspath .)
common_dir := $(base_dir)/common
connectal_dir := $(base_dir)/connectal

# bsvdir=$(base_dir)/lib
# :$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/:$(BASEDIR)/lib/dram_ctrl_sim/ddr4:$(BASEDIR)/xilinx/ddr4_v2_2/
# bscflags=-aggressive-conditions -show-schedule -check-assert -bdir build_dir/$@ -simdir build_dir/$@  -info-dir build_dir -p %:+:$(bsvdir)  +RTS -K1G -RTS  -Xc++ -D_GLIBCXX_USE_CXX11_ABI=0  -D MainClockPeriod=1  -D DerivedClockPeriod=1 -Xc++ -O2 -steps-max-intervals 10000000 #-D DEBUG # -show-elab-progress # -D DEBUG

bscflags = -aggressive-conditions -show-schedule -check-assert -bdir build_dir/$@ -simdir build_dir/$@  -info-dir build_dir -p %:+:$(common_dir) -D MainClockPeriod=1  -D DerivedClockPeriod=1 -steps-max-intervals 10000000 # -show-elab-progress # -D DEBUG

targets = MergerTreeUnfolded
targets_obj = $(wildcard *.o)
targets_lib = $(wildcard *.so)

# set default vector size
ifeq ($(K),)
	K=8
endif
bscflags += -D VecSz=$(K)

MergerTreeUnfolded: MergerTreeUnfolded.bsv
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mkAscMergerTree $<

SeqMerger: % : $(src_dir)/%.bsv $(test_dir)/Test%.bsv

CppHelper.o: $(src_dir)/helper.cpp
	g++ -fPIC -DK=$(K) -c $< -o $@

MergerInner: SeqMerger
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test Test$<.bsv
	bsc $(bscflags) -sim -u -e mk$@Test -o $@ $(targets_obj)

Merger: SeqMerger CppHelper.o
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test Test$<.bsv
	bsc $(bscflags) -sim -u -e mk$@Test -o $@ CppHelper.o

clean:
	rm -rf build_dir $(targets) $(targets_obj) $(targets_lib) *.sched #ConnectalProjectConfig.bsv

.PHONY: clean
.DEFAULT_GOAL := all

