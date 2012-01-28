#!/usr/bin/zsh

# Script for printing the active syncs.

# Version is YYYYMMDD
VERSION=20100619

MILKO_ROOT=/opt/milkyway
SYNC_DIR=/opt/milkyway/sync_dir
STATUS_DIR=/opt/milkyway/status_dir

echo "Active syncs"
syncs=($(ls $SYNC_DIR|sort))
echo "  PROJECT             SYNCING SINCE          LAST SUCCESFUL         PID"
for i in $syncs;
do
    name=$(echo $i|sed -r 's/\.[^\.]+$//')
    pid=$(echo $i|awk -F\. '{print $NF}')
    sync_time=$(stat -c "%y" $SYNC_DIR/$i 2>/dev/null)
    last_time=$(stat -c "%y" $STATUS_DIR/$name 2>/dev/null)
    echo -n "  "
    echo -n ${(r:20:)name}
    echo -n ${(r:19:)sync_time}"    "
    echo -n ${(r:19:)last_time}"    "
    echo "$pid";
done

echo ""
echo "Last successful syncs"
syncs=($(ls $STATUS_DIR|sort))
echo "  PROJECT             LAST SUCCESFUL"
for i in $syncs;
do
    name=$(echo $i)
    last_time=$(stat -c "%y" $STATUS_DIR/$name 2>/dev/null)
    echo -n "  "
    echo -n ${(r:20:)name}
    echo -n ${(r:19:)last_time}"    "
    echo ""
done
