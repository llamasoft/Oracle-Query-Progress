# Oracle Query Progress

This a SQL\*Plus script meant to display the progress of a long running query.  Simply supply the `sql_id` of the query (obtainable from `v$session_longops`) and it will return the execution plan as well as the current progress.
The script does depend on two utility functions that have been included in `simplify_count.sql`.  You will need to run that first before running the main script.


Example script output:

    ==============================================
    Query Sid:               560
    Query Exec ID:      16777216
    Query Exec Time: 2015-MAR-26 09:07 AM
    
                                                                                                                Exec Time
      ID Plan Step                                                 Est. Rows        Row Count Memory   Temp         (Min) Step Status
    ---- --------------------------------------------------------- --------- ---------------- -------- -------- --------- ---------------
       0 SELECT STATEMENT                                                           2,874,501                          17 EXECUTING
       1 |PX COORDINATOR                                                            2,874,501                          17 EXECUTING
       2 | PX SEND QC (RANDOM) - :TQ10003                             19.2 M        2,871,840                          17 EXECUTING
       3 |  HASH JOIN OUTER BUFFERED                                  19.2 M        2,871,840    3.8 G    7.0 G        20 EXECUTING
       4 |   HASH JOIN OUTER                                          13.4 M       13,416,688                           2 READY
       5 |   |PX RECEIVE                                              13.4 M       13,416,688                           0 READY
       6 |   | PX SEND HASH - :TQ10000                                13.4 M       13,416,688                           0 READY
       7 |   |  PX BLOCK ITERATOR                                     13.4 M       13,416,688                           0 READY
       8 |   |   TABLE ACCESS FULL - SMALL_INPUT_TABLE                13.4 M       13,416,688                           0 READY
       9 |   |PX RECEIVE                                              24.5 M       24,533,581                           2 READY
      10 |   | PX SEND HASH - :TQ10001                                24.5 M       24,533,581                           1 READY
      11 |   |  PX BLOCK ITERATOR                                     24.5 M       24,533,581                           1 READY
      12 |   |   TABLE ACCESS FULL - MEDIUM_INPUT_TABLE               24.5 M       24,533,581                           1 READY
      13 |   PX RECEIVE                                              134.6 M      175,036,199                           2 READY
      14 |   |PX SEND HASH - :TQ10002                                134.6 M      175,036,199                           2 READY
      15 |   | PX BLOCK ITERATOR                                     134.6 M      175,036,199                           2 READY
      16 |   |  TABLE ACCESS FULL - LARGE_INPUT_TABLE                134.6 M      175,036,199                           2 READY


Note: The script *can* run without SQL\*Plus but you'll still need to supply the sql_id some way or another.
