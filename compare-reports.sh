#!/bin/bash

SKETCH_FAILED=0
FOUND_BOARD_IN_DATABASE=0
FOUND_SKETCH_IN_DATABASE=0
SYSTEM_FAILURE=0
INDEX_I=0
INDEX_J=0
INDEX_K=0
INDEX_L=0

echo "Computing the total number of boards from full-sketches-report.json"
num_boards_sketches_report=$(jq '.boards | length' sketches-reports/full-sketches-report.json)
echo $num_boards_sketches_report

echo "Computing the total number of boards from full-database-report.json"
num_boards_database_report=$(jq '.boards | length' database-reports/full-database-report.json)
echo $num_boards_database_report


#First iteration over the number of boards used in the current compilation
#for((i=0;i<$num_boards_sketches_report;i+=1)); do
while [ $INDEX_I -lt $num_boards_sketches_report ]; do
  echo "INDEX_I = $INDEX_I"
  #save the current board name
  board_name=$(cat sketches-reports/full-sketches-report.json | jq '.boards[$INDEX_I].board')
  echo "Current board name: $board_name"
  #echo "Computing the total number of compiled sketches per $board_name"
  #compute and save the number of sketches compiled for that board
  num_sketches_per_board=$(jq '."boards[$INDEX_I].sketches" | length' sketches-reports/full-sketches-report.json)
  echo "Number of sketches for current board: $num_sketches_per_board"

  #iterate over all the sketches of that board and check which compilations failed
  #for((j=0;j<$num_sketches_per_board;j+=1)); do
  while [ $INDEX_J -lt $num_sketches_per_board ]; do
    compilation_status=$(cat sketches-reports/full-sketches-report.json | jq '.boards[$INDEX_I].sketches[$INDEX_J].compilation_success')
    if [ "$compilation_status" == "false" ]; then
      #reset the flags that checks if a board/sketch has been found in the database
      FOUND_BOARD_IN_DATABASE=0
      FOUND_SKETCH_IN_DATABASE=0
      #increment the number of sketch failed
      SKETCH_FAILED+=1
      #save the sketch name
      name_failed_sketch=$(cat sketches-reports/full-sketches-report.json | jq '.boards[$INDEX_I].sketches[$INDEX_J].name')

      #iterate over the available boards in the report util the current board is found
      #for((k=0;k<$num_boards_database_report;k+=1)); do
      while [ $INDEX_K -lt $num_boards_database_report ]; do
        database_board_name=$(database-reports/full-database-report.json | jq '.boards[$INDEX_K].board')
        if [ "$database_board_name" == "$board_name" ]; then
          FOUND_BOARD_IN_DATABASE=1
          #compute the number of available sketches in the database for the current board
          #echo "Computing the total number of database compiled sketches per $database_board_name"
          num_database_sketches_per_board=$(jq '.boards[$INDEX_K].sketches | length' database-reports/full-database-report.json)

          #iterate over all the database sketches of that board until the one that failed is found
          #for((l=0;l<$num_database_sketches_per_board;l+=1)); do
          while [ $INDEX_L -lt $num_database_sketches_per_board ]; do
            database_sketch_name=$(cat database-reports/full-database-report.json | jq '.boards[$INDEX_K].sketches[$INDEX_L].name')
            if [ "$database_sketch_name" == "$name_failed_sketch" ]; then
              #set the related flag
              FOUND_SKETCH_IN_DATABASE=1
              database_compilation_status=$(cat database-reports/full-database-report.json | jq '.boards[$INDEX_K].sketches[$INDEX_L].compilation_success')
              #check the expected results
              if [ "$database_compilation_status" == "true" ]; then
                #echo "COMPILATION FAILURE: compilation of sketch $database_sketch_name was EXPECTED TO PASS on board $database_board_name"
                SYSTEM_FAILURE=1
              else
                #echo "Ignore compilation failure: compilation of sketch $database_sketch_name was EXPECTED TO FAIL on board $database_board_name"
                SKETCH_FAILED-=1
              fi
              break
            fi
            if [ $FOUND_SKETCH_IN_DATABASE == 0 ]; then
              let INDEX_L=INDEX_L+1
              #l=$[$l+1]
            else
              break
            fi
          done

          #check if the sketch has been found or not
          if [ $FOUND_SKETCH_IN_DATABASE == 0 ]; then
            echo "ERROR: Sketch $database_sketch_name NOT FOUND!"
          else
            break
          fi

        fi
        if [ $FOUND_SKETCH_IN_DATABASE == 0 ]; then
          let INDEX_K=INDEX_K+1
          #k=$[$k+1]
        else
          break
        fi
      done

      #check if the board has been found or not
      if [ $FOUND_BOARD_IN_DATABASE == 0 ]; then
        echo "ERROR: Board $database_board_name NOT FOUND!"
      fi

    fi
    let INDEX_J=INDEX_J+1
    #j=$[$j+1]
  done
  let INDEX_I=INDEX_I+1
  #i=$[$i+1]
done

if [ $SYSTEM_FAILURE == 1 ]; then
  echo "$SKETCH_FAILED SKETCHES FAILED!"
  exit 1
else
  echo "Failure check completed successfully!"
  exit 0
fi