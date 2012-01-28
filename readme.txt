:: Some examples ::

A dry run with fake directories:
./milko_debug.pl config/common.conf config/aminet.milko_conf -- dry_run=1 \
   active_syncs_dir=$PWD/sync_dir/ \
   sync_status_dir=$PWD/status_dir/ \
   destination_dir=/tmp/

./arla_debug.pl -- dry_run=1 \
   active_syncs_dir=$PWD/sync_dir/ \
   sync_status_dir=$PWD/status_dir/ \
   fail_syncs_dir=$PWD/fail_dir/ \
   destination_dir=/tmp/

