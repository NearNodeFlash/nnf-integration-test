| test   | src                              | srcType | dest                                       | destType   | expected                                             |
| ------ | -------------------------------- | ------- | ------------------------------------------ | ---------- | ---------------------------------------------------- |
| file1  | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest                          | dir        | /lus/global/testdir/dest/*/data.out                         |
| file2  | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest/                         | dir/       | /lus/global/testdir/dest/*/data.out                         |
| file2a | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest/data.out                 | file       | /lus/global/testdir/dest/*/data.out                         |
| file3  | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest/component                | DNE - file | /lus/global/testdir/dest/*/component                        |
| file4  | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest/newdir/                  | DNE - dir/ | /lus/global/testdir/dest/newdir/*/data.out                  |
| file5  | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest/newdir/component         | DNE - file | /lus/global/testdir/dest/newdir/*/component                 |
| file6  | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest/newdir/newdir2/          | DNE - dir/ | /lus/global/testdir/dest/newdir/newdir2/*/data.out          |
| file7  | $DW_JOB_copyout-test/job/data.out     | file    | /lus/global/testdir/dest/newdir/newdir2/component | DNE - file | /lus/global/testdir/dest/newdir/newdir2/*/component         |
| dir1   | $DW_JOB_copyout-test/job              | dir     | /lus/global/testdir/dest                          | dir        | /lus/global/testdir/dest/*/job/data.out                     |
| dir2   | $DW_JOB_copyout-test/job/job2         | dir     | /lus/global/testdir/dest                          | dir        | /lus/global/testdir/dest/*/job2/data3.out                   |
| dir3   | $DW_JOB_copyout-test/job              | dir     | /lus/global/testdir/dest/                         | dir/       | /lus/global/testdir/dest/*/job/data.out                     |
| dir4   | $DW_JOB_copyout-test/job/             | dir/    | /lus/global/testdir/dest                          | dir        | /lus/global/testdir/dest/*/data.out                         |
| dir5   | $DW_JOB_copyout-test/job/             | dir/    | /lus/global/testdir/dest/                         | dir/       | /lus/global/testdir/dest/*/data.out                         |
| dir6   | $DW_JOB_copyout-test/job              | dir     | /lus/global/testdir/dest/newdir                   | DNE - dir  | /lus/global/testdir/dest/newdir/*/job/data.out              |
| dir7   | $DW_JOB_copyout-test/job              | dir     | /lus/global/testdir/dest/newdir/                  | DNE - dir/ | /lus/global/testdir/dest/newdir/*/job/data.out              |
| dir8   | $DW_JOB_copyout-test/job/             | dir/    | /lus/global/testdir/dest/newdir                   | DNE - dir  | /lus/global/testdir/dest/newdir/*/data.out                  |
| dir9   | $DW_JOB_copyout-test/job/             | dir/    | /lus/global/testdir/dest/newdir/                  | DNE - dir/ | /lus/global/testdir/dest/newdir/*/data.out                  |
| dir10  | $DW_JOB_copyout-test/job              | dir     | /lus/global/testdir/dest/newdir/newdir2           | DNE - dir  | /lus/global/testdir/dest/newdir/newdir2/*/job/data.out      |
| dir11  | $DW_JOB_copyout-test/job              | dir     | /lus/global/testdir/dest/newdir/newdir2/          | DNE - dir/ | /lus/global/testdir/dest/newdir/newdir2/*/job/data.out      |
| dir12  | $DW_JOB_copyout-test/job/             | dir/    | /lus/global/testdir/dest/newdir/newdir2           | DNE - dir  | /lus/global/testdir/dest/newdir/newdir2/*/data.out          |
| dir13  | $DW_JOB_copyout-test/job/             | dir/    | /lus/global/testdir/dest/newdir/newdir2/          | DNE - dir/ | /lus/global/testdir/dest/newdir/newdir2/*/data.out          |
| root1  | $DW_JOB_copyout-test                  | dir     | /lus/global/testdir/dest                          | dir        | /lus/global/testdir/dest/*/job/data.out                     |
| root2  | $DW_JOB_copyout-test                  | dir     | /lus/global/testdir/dest/                         | dir/       | /lus/global/testdir/dest/*/job/data.out                     |
| root3  | $DW_JOB_copyout-test/                 | dir/    | /lus/global/testdir/dest                          | dir        | /lus/global/testdir/dest/*/job/data.out                     |
| root4  | $DW_JOB_copyout-test/                 | dir/    | /lus/global/testdir/dest/                         | dir/       | /lus/global/testdir/dest/*/job/data.out                     |
| root5  | $DW_JOB_copyout-test                  | dir     | /lus/global/testdir/dest/newdir                   | dir        | /lus/global/testdir/dest/newdir/*/job/data.out              |
| root6  | $DW_JOB_copyout-test                  | dir     | /lus/global/testdir/dest/newdir/                  | dir/       | /lus/global/testdir/dest/newdir/*/job/data.out              |
| root7  | $DW_JOB_copyout-test/                 | dir/    | /lus/global/testdir/dest/newdir                   | dir        | /lus/global/testdir/dest/newdir/*/job/data.out              |
| root8  | $DW_JOB_copyout-test/                 | dir/    | /lus/global/testdir/dest/newdir/                  | dir/       | /lus/global/testdir/dest/newdir/*/job/data.out              |
