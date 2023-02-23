#!/usr/bin/env bash

# Copyright (c) 2017, Lawrence Livermore National Security, LLC.
# Produced at the Lawrence Livermore National Laboratory
# Written by Chunhua Liao, Pei-Hung Lin, Joshua Asplund,
# Markus Schordan, and Ian Karlin
# (email: liao6@llnl.gov, lin32@llnl.gov, asplund1@llnl.gov,
# schordan1@llnl.gov, karlin1@llnl.gov)
# LLNL-CODE-732144
# All rights reserved.
#
# This file is part of DataRaceBench. For details, see
# https://github.com/LLNL/dataracebench. Please also see the LICENSE file
# for our additional BSD notice
# 
# Redistribution of Backstroke and use in source and binary forms, with
# or without modification, are permitted provided that the following
# conditions are met:
#
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the disclaimer below.
#
# * Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the disclaimer (as noted below)
#   in the documentation and/or other materials provided with the
#   distribution.
#
# * Neither the name of the LLNS/LLNL nor the names of its contributors
#   may be used to endorse or promote products derived from this
#   software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
# CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL LAWRENCE LIVERMORE NATIONAL
# SECURITY, LLC, THE U.S. DEPARTMENT OF ENERGY OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
# THE POSSIBILITY OF SUCH DAMAGE.

OPTION=$1
DEF_LAN=$2
TESTS=$(grep -l main micro-benchmarks/*.c)
CPPTESTS=$(grep -l main micro-benchmarks/*.cpp)
FORTRANTESTS=$(find micro-benchmarks-fortran -iregex ".*\.F[0-9]*" -o -iregex ".*\.for")
POLYFLAG="micro-benchmarks/utilities/polybench.c -I micro-benchmarks -I micro-benchmarks/utilities -DPOLYBENCH_NO_FLUSH_CACHE -DPOLYBENCH_TIME -D_POSIX_C_SOURCE=200112L"
FPOLYFLAG="-Imicro-benchmarks-fortran micro-benchmarks-fortran/utilities/fpolybench.o"
LANGUAGE="default"

CC="clang"
VALGRIND="valgrind --trace-children=yes --tool=massif --stacks=yes"
CLANG_EXEC="results/exec-clang"
CLANG_EXEC_VALGRIND="$CLANG_EXEC/valgrind-$(date +"%Y-%m-%d")"
CLANG_RESULT="results/clang-result-$(date +"%Y-%m-%d")"
CLANG_EXEC_COUNT=1
DB_SIZE=32

help () {
    echo
    echo "Usage: $0 [--run] [--help] language"
    echo
    echo "--help      : this option"
    echo "--small     : compile and test all benchmarks using small parameters with Helgrind, ThreadSanitizer, Archer, Intel inspector."
    echo "--compile-clang       : compile with clang (no run)"    
    echo "--run       : compile and run all benchmarks with clang (perf evaluation)"
    echo "--run-intel : compile and run all benchmarks with Intel compilers (no evaluation)"
    echo "--helgrind  : compile and test all benchmarks with Helgrind"
    echo "--tsan-clang: compile and test all benchmarks with clang ThreadSanitizer"
    echo "--tsan-gcc  : compile and test all benchmarks with gcc ThreadSanitizer"
    echo "--archer    : compile and test all benchmarks with Archer"
    echo "--coderrect : compile and test all benchmarks with Coderrect Scanner"
    echo "--inspector : compile and test all benchmarks with Intel Inspector"
    echo "--romp      : compile and test all benchmarks with Romp"
    echo "--llov    : compile and test all benchmarks with LLVM OpenMP Verifier (LLOVE)"
    echo "--customize : compile and test customized test list and tools"
    echo
}

valid_language_name () {
  case "$1" in
    c/c++) return 0 ;;
    C/C++) return 0 ;;
    c) return 0 ;;
    C) return 0 ;;
    c++) return 0 ;;
    C++) return 0 ;;
    fortran) return 0 ;;
    Fortran) return 0 ;;
    FORTRAN) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -z "$DEF_LAN" ]; then
	echo "use default test"
fi

if valid_language_name "$DEF_LAN"; then LANGUAGE="$DEF_LAN"
        else 
		echo "Invalid language name $DEF_LAN" && help && exit 1
fi
 

if [[ -z "$OPTION" || "$OPTION" == "--help" ]]; then
    help
    exit
fi

if [[ "$OPTION" == "--small" ]]; then
  scripts/test-harness.sh -t 3 -n 2 -d 32 -l $LANGUAGE -x helgrind
  scripts/test-harness.sh -t 3 -n 2 -d 32 -l $LANGUAGE -x archer
  scripts/test-harness.sh -t 3 -n 1 -d 32 -l $LANGUAGE -x coderrect
  scripts/test-harness.sh -t 3 -n 2 -d 32 -l $LANGUAGE -x tsan-clang
  scripts/test-harness.sh -t 3 -n 2 -d 32 -l $LANGUAGE -x inspector-max-resources
  scripts/test-harness.sh -t 3 -n 2 -d 32 -l $LANGUAGE -x romp
fi

if [[ "$OPTION" == "--compile-clang" ]]; then
    rm -rf $CLANG_EXEC
    mkdir $CLANG_EXEC
    if [[ "$LANGUAGE" == "c" || "$LANGUAGE" == "C" ]]; then
    	for test in $TESTS; do
            echo "------------------------------------------"
            echo "COMPILING ($CC): $test"
            CFLAGS="-O0 -g -Wall -std=c99 -fopenmp"
            if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
            $CC $CFLAGS "$test" -lm -o $CLANG_EXEC/$(basename $test .c) 
        done    
    fi
    exit
fi

if [[ "$OPTION" == "--run" ]]; then
    rm -rf $CLANG_EXEC_VALGRIND
    mkdir -p $CLANG_EXEC_VALGRIND
    rm -rf $CLANG_RESULT
    echo -e "PROGRAM\tBIN_SIZE(B)\tTEXT_SIZE(B)\tBSS_SIZE(B)\tHEAP_SIZE(B)\tSTACK_SIZE(B)\tEXEC_TIME(S)" >> $CLANG_RESULT
    if [[ "$LANGUAGE" == "c" || "$LANGUAGE" == "C" ]]; then
    	for test in $TESTS; do
            echo "------------------------------------------"
            echo "RUNNING: $test"
            EXEC_TIME=0
            for ((n=0;n<$CLANG_EXEC_COUNT;n++))
            do
                START_TIME=$(date +%s.%6N)
                ./$CLANG_EXEC/$(basename $test .c) $DB_SIZE >> /dev/null
                END_TIME=$(date +%s.%6N)
                ELAPTIME=$(echo "scale=6; $END_TIME - $START_TIME" | bc)
                EXEC_TIME=$(echo "scale=6; $EXEC_TIME + $ELAPTIME" | bc)
            done
            EXEC_TIME=$(echo "scale=6; $EXEC_TIME / $CLANG_EXEC_COUNT" | bc)
            $VALGRIND --massif-out-file=$CLANG_EXEC_VALGRIND/$(basename $test .c).log ./$CLANG_EXEC/$(basename $test .c) $DB_SIZE
            BIN_SIZE=$(ls -al $CLANG_EXEC/$(basename $test .c) | awk '{print $5;}')
            TEXT_SIZE=$(objdump -h $CLANG_EXEC/$(basename $test .c) | grep -w .text | awk '{print "0x" $3;}' | xargs printf "%d")
            BSS_SIZE=$(objdump -h $CLANG_EXEC/$(basename $test .c) | grep -w .bss | awk '{print "0x" $3;}' | xargs printf "%d")
            HEAP_SIZE=$(grep mem_heap_B $CLANG_EXEC_VALGRIND/$(basename $test .c).log | sed -e 's/mem_heap_B=\(.*\)/\1/' | sort -g | tail -n 1)
            STACK_SIZE=$(grep mem_stacks_B $CLANG_EXEC_VALGRIND/$(basename $test .c).log | sed -e 's/mem_stacks_B=\(.*\)/\1/' | sort -g | tail -n 1)

            echo -e "$(basename $test .c)\t$BIN_SIZE\t$TEXT_SIZE\t$BSS_SIZE\t$HEAP_SIZE\t$STACK_SIZE\t$EXEC_TIME" >> $CLANG_RESULT
        done
        #rm -f ./a.out
# test for cpp files
    elif [[ "$LANGUAGE" == "c++" || "$LANGUAGE" == "C++" ]]; then
   	for test in $CPPTESTS; do
            echo "------------------------------------------"
            echo "RUNNING: $test"
            CFLAGS="-g -Wall -fopenmp"
            if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
            g++ $CFLAGS "$test" -lm
            ./a.out  > /dev/null
        done
        rm -f ./a.out
# test for fortran files
    elif [[ "$LANGUAGE" == "fortran" || "$LANGUAGE" == "FORTRAN" ]]; then
    	for test in $FORTRANTESTS; do
	    echo "------------------------------------------"
            echo "RUNNING: $test"
            FFLAGS="-fopenmp -ffree-line-length-none"
	    if grep -q 'PolyBench' "$test"; then FFLAGS+=" $FPOLYFLAG"; fi
            gfortran $FFLAGS "$test" -lm
            ./a.out  > /dev/null
         done
         rm -f ./a.out
         rm drb*
    else 
        for test in $TESTS; do
            echo "------------------------------------------"
            echo "RUNNING: $test"
            CFLAGS="-g -Wall -std=c99 -fopenmp"
            if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
            gcc $CFLAGS "$test" -lm
            ./a.out  > /dev/null
        done
        rm -f ./a.out
        for test in $CPPTESTS; do
            echo "------------------------------------------"
            echo "RUNNING: $test"
            CFLAGS="-g -Wall -fopenmp"
            if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
            g++ $CFLAGS "$test" -lm
            ./a.out  > /dev/null
        done
        rm -f ./a.out
        for test in $FORTRANTESTS; do
            echo "------------------------------------------"
            echo "RUNNING: $test"
            FFLAGS="-fopenmp  -ffree-line-length-none"
            if grep -q 'PolyBench' "$test"; then FFLAGS+=" $FPOLYFLAG"; fi
            gfortran $FFLAGS "$test" -lm
            ./a.out  > /dev/null
         done
         rm -f ./a.out
         rm drb*
    fi
    exit
fi

if [[ "$OPTION" == "--run-intel" ]]; then
    for test in $TESTS; do
        echo "------------------------------------------"
        echo "RUNNING: $test"
        CFLAGS="-g -Wall -std=c99 -fopenmp"
        if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
        icc $CFLAGS "$test" -lm
        ./a.out  > /dev/null
    done
    rm -f ./a.out
# test for cpp files
    for test in $CPPTESTS; do
        echo "------------------------------------------"
        echo "RUNNING: $test"
        CFLAGS="-g -Wall -fopenmp"
        if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
        icpc $CFLAGS "$test" -lm
        ./a.out  > /dev/null
    done
    rm -f ./a.out
# test for fortran files
    for test in $FORTRANTESTS; do
        echo "------------------------------------------"
        echo "RUNNING: $test"
        FFLAGS="-fopenmp"
        if grep -q 'PolyBench' "$test"; then FLAGS+=" $POLYFLAG"; fi
        ifort $FFLAGS "$test" -lm
        ./a.out  > /dev/null
    done
    rm -f ./a.out
    rm drb*
    exit
fi

if [[ "$OPTION" == "--run-rose" ]]; then
    for test in $TESTS; do
        echo "------------------------------------------"
        echo "TESTING using rose: $test"
        CFLAGS="-g -Wall -std=c99 -rose:openmp:ast_only"
        if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
        $ROSE_INSTALL/bin/identityTranslator -c $CFLAGS "$test" -lm
    done
# test for cpp files
    for test in $CPPTESTS; do
        echo "------------------------------------------"
        echo "TESTING using rose: $test"
        CFLAGS="-g -Wall -rose:openmp:ast_only"
        if grep -q 'PolyBench' "$test"; then CFLAGS+=" $POLYFLAG"; fi
        $ROSE_INSTALL/bin/identityTranslator -c $CFLAGS "$test" -lm
    done
    exit
fi



if [[ "$OPTION" == "--helgrind" ]]; then
    scripts/test-harness.sh -l $LANGUAGE -x helgrind
fi

if [[ "$OPTION" == "--archer" ]]; then
    scripts/test-harness.sh -t 8 -n 1 -d 32 -l $LANGUAGE -x archer
fi

if [[ "$OPTION" == "--coderrect" ]]; then
    scripts/test-harness.sh -t 8 -n 1 -d 32 -l $LANGUAGE -x coderrect
fi

if [[ "$OPTION" == "--tsan-clang" ]]; then
    scripts/test-harness.sh -t 8 -n 1 -d 32 -l $LANGUAGE -x tsan-clang
fi

if [[ "$OPTION" == "--tsan-gcc" ]]; then
    scripts/test-harness.sh -t 8 -n 5 -d 32 -l $LANGUAGE -x tsan-gcc
fi

if [[ "$OPTION" == "--inspector" ]]; then
    scripts/test-harness.sh -t 8 -n 5 -d 32 -l $LANGUAGE -x inspector-max-resources
fi

if [[ "$OPTION" == "--romp" ]]; then
   scripts/test-harness.sh -t 8 -n 5 -d 32 -l $LANGUAGE -x romp
fi

if [[ "$OPTION" == "--llov" ]]; then
   scripts/test-harness.sh -t 8 -n 5 -d 32 -l  $LANGUAGE -x llov
fi

if [[ "$OPTION" == "--customize" ]]; then
        TO=($(cat tool.def))
        for rtool in "${TO[@]}"; do
                scripts/test-harness.sh -t 8 -n 5 -d 32 -l $LANGUAGE -c 1 -x $rtool;
        done
fi
