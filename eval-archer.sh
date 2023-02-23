OUTPUT_DIR="results"
EXEC_DIR="$OUTPUT_DIR/exec-archer"
PROGS="$EXEC_DIR/*"
VALGRIND="valgrind --trace-children=yes --tool=massif --stacks=yes"
ARCHER_EXEC_VALGRIND="$OUTPUT_DIR/archer-valgrind-$(date +"%Y-%m-%d")"
ARCHER_RESULT="$OUTPUT_DIR/archer-result-$(date +"%Y-%m-%d")"
DS_SIZE=32
EXEC_COUNT=5

rm -rf $ARCHER_EXEC_VALGRIND
rm -rf $ARCHER_RESULT
mkdir $ARCHER_EXEC_VALGRIND

echo "PROGRAM\tBIN_SIZE(B)\tTEXT_SIZE(B)\tBSS_SIZE(B)\tHEAP_SIZE(B)\tSTACK_SIZE(B)\tEXEC_TIME(S)" >> $ARCHER_RESULT
for PROG in $PROGS
do
    EXEC_TIME=0
    N=$EXEC_COUNT
    while [ $N -gt 0 ]; do
        echo "pass"
        START_TIME=$(date +%s.%6N)
        ./$PROG $DS_SIZE >> /dev/null
        END_TIME=$(date +%s.%6N)
        ELAPTIME=$(echo "scale=6; $END_TIME - $START_TIME" | bc)
        EXEC_TIME=$(echo "scale=6; $EXEC_TIME + $ELAPTIME" | bc)
        N=$(( N - 1))
    done
    EXEC_TIME=$(echo "scale=6; $EXEC_TIME / $EXEC_COUNT" | bc)

    $VALGRIND --massif-out-file=$ARCHER_EXEC_VALGRIND/$(basename $PROG .out).log ./$PROG $DS_SIZE

    BIN_SIZE=$(ls -al $PROG | awk '{print $5;}')
    TEXT_SIZE=$(objdump -h $PROG | grep -w .text | awk '{print "0x" $3;}' | xargs printf "%d")
    BSS_SIZE=$(objdump -h $PROG | grep -w .bss | awk '{print "0x" $3;}' | xargs printf "%d")
    HEAP_SIZE=$(grep mem_heap_B $ARCHER_EXEC_VALGRIND/$(basename $PROG .out).log | sed -e 's/mem_heap_B=\(.*\)/\1/' | sort -g | tail -n 1)
    STACK_SIZE=$(grep mem_stacks_B $ARCHER_EXEC_VALGRIND/$(basename $PROG .out).log | sed -e 's/mem_stacks_B=\(.*\)/\1/' | sort -g | tail -n 1)

    echo "$(basename $PROG .out)\t$BIN_SIZE\t$TEXT_SIZE\t$BSS_SIZE\t$HEAP_SIZE\t$STACK_SIZE\t$EXEC_TIME" >> $ARCHER_RESULT
done