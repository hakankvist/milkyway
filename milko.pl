#!/usr/bin/perl -w

use DBI;

use strict;

# push path to common lib to @INC
use File::Basename qw(dirname basename);
use lib dirname $0;
use moo::common;

# 1 - Debug prints enabled
# 0 - Debug prints disabled
$moo::common::DEBUG_PRINTS = 0;
if (basename(__FILE__) eq "milko_debug.pl") {
    $moo::common::DEBUG_PRINTS = 1;
}

# this milko config
my $config = {};

# time stampts for time measuring.
my $begin_time;
my $end_time;

sub insert_into_database
{
    my $begin_time = shift @_;
    my $end_time = shift @_;
    my $exec_status = shift @_;
    my $log_file = shift @_;

    my $error_message = "";

    # insert status data into the database here
    my $dsn = "DBI:mysql:database=$config->{database};host=$config->{db_host};port=$config->{db_port}";
    my $dbh = DBI->connect($dsn, $config->{db_user}, $config->{db_password});
    my $drh = DBI->install_driver("mysql");

    if (defined($dbh))
    {
        # Find out the ID of the current project.
        my $sql = "SELECT id FROM projects where name = '".$config->{name}."'";
        my $sth = $dbh->prepare($sql);
        $sth->execute();
        my $project_id = -1;
        if (my @row = $sth->fetchrow_array()) {
            $project_id = $row[0];
        }
        else{
            $error_message .= "SQLError: Unable to fetch id from database\n".
                "\t$sql\n";
        }
        $sth->finish();


        if (!length($error_message))
        {
            # make a procedure in the database?
            $sql = "INSERT INTO sync_status(project_id, starttime, endtime, status) VALUES($project_id, FROM_UNIXTIME($begin_time), FROM_UNIXTIME($end_time), $exec_status)";
            unless ($dbh->do($sql)){
                $error_message .= "SQLError: Unable to insert into synch_status\n".
                    "\t$sql\n";
            }
        }

        if (!length($error_message))
        {
            # find out the id ..., then insert blob.
            my $inserted_id =  $dbh->{mysql_insertid};
            if (open(LOG_FILEHANDLE, $log_file))
            {
                read(LOG_FILEHANDLE, my $log_data, -s $log_file );
                close(LOG_FILEHANDLE);
                $sql = "INSERT INTO sync_logdata(sync_id, rsync_log) VALUES($inserted_id, ?)";
                my $sth = $dbh->prepare($sql);
                unless($sth->execute($log_data))
                {
                    $error_message .= "SQLError: Unable to insert into sync_logdata\n".
                        "\tINSERT INTO sync_logdata(id, rsync_log) VALUES($inserted_id, ....)\n";
                }
                $sth->finish;
            }
        }

        $dbh->disconnect();
    }
    else
    {
        $error_message .= "Mysql connection problems DBI->connect failed \n";
    }

    return $error_message;
}

sub execute_rsync($$$$$)
{
    my $sub_dir = shift @_;
    my $more_ignore_items = shift @_;
    my $delete = shift @_;
    my $log_file = shift @_;
    my $config = shift @_;

    $begin_time = time();

    my $name = "";
    my $remote_server = "";
    my $remote_dir = "";
    my $ignore_items = "";
    my $destination_dir = "";
    my $rsync_flags = " --recursive --times --verbose --timeout=3600 ";
    my $rsync_links = " --links ";
    my $rsync_hardlinks = " --hard-links ";
    my $rsync_username = "";

    $name = $config->{name};
    $remote_server = $config->{remote_server};
    $remote_dir = $config->{remote_dir}.$sub_dir;

    if (defined($config->{rsync_username})){
        $rsync_username = $config->{rsync_username}."@";
    }

    if (defined($config->{rsync_compress}) && $config->{rsync_compress} == 1){
        $rsync_flags .= " --compress ";
    }

    if (defined($config->{rsync_numeric_ids}) && $config->{rsync_numeric_ids} == 1){
        $rsync_flags .= " --numeric-ids ";
    }

    if (defined($config->{rsync_delay_updates}) && $config->{rsync_delay_updates} == 1){
        $rsync_flags .= " --delay-updates ";
    }

    if (defined($config->{rsync_preserve_permissions}) && $config->{rsync_preserve_permissions} == 1){
        $rsync_flags .= " --perms ";
    }

    if ($delete){
        $rsync_flags .= " --delete --delete-after ";
    }

    if (defined($config->{rsync_copy_links}) && $config->{rsync_copy_links} == 1){
        # use of copy links will disable any links.
        $rsync_links = " --copy-links ";
        $rsync_hardlinks = "";
    }
    elsif (defined($config->{rsync_hardlinks}) && $config->{rsync_hardlinks} == 0){
        $rsync_hardlinks = "";
    }

    if (defined $config->{ignore_items}){
        if ($more_ignore_items ne ""){
            $more_ignore_items .= ",";
        }
        $more_ignore_items .= $config->{ignore_items};
    }
    if ($more_ignore_items ne "")
    {
        my @tmp_array = split(/,\s*/, $more_ignore_items);
        foreach my $item (@tmp_array){
            $ignore_items .= " --exclude '$item' ";
        }
    }

    $destination_dir = $config->{destination_dir}.$sub_dir;

    #
    # If password should be used we must set the password as an ENVIRONMENT variable
    # it can not be supplied on the command line
    if (defined($config->{rsync_password}))
    {
        $ENV{RSYNC_PASSWORD} = $config->{rsync_password};
    }

    my $exec_status = 0;
    my $exec_string;
    if ($moo::common::DEBUG_PRINTS){
        $exec_string = "/usr/bin/rsync $rsync_flags $rsync_links $rsync_hardlinks $ignore_items rsync://$rsync_username$remote_server"."$remote_dir $destination_dir";
    }
    else {
        $exec_string = "/usr/bin/rsync $rsync_flags $rsync_links $rsync_hardlinks $ignore_items rsync://$rsync_username$remote_server"."$remote_dir $destination_dir  1>$log_file 2>&1";
    }
    if (defined($config->{dry_run}) && $config->{dry_run}==1){
        my $seconds = 60;
        log_print("Executing: \"$exec_string\"\n");
        log_print("Sleeping for $seconds seconds\n");
        sleep($seconds);
        log_print("Rsync done\n");
        $? = 0;
    }
    else{
        debug_print("Executing: \"$exec_string\"\n");
        system($exec_string);
    }

    if ($? == -1) {
        # print "failed to execute: $!\n";
        $exec_status = -1;
    }
    elsif ($? & 127) {
        # printf "child died with signal %d, %s coredump\n", ($? & 127),  ($? & 128) ? 'with' : 'without';
        $exec_status = -2;
    }
    else {
        # printf "child exited with value %d\n", $? >> 8;
        $exec_status = $? >> 8;

        my $error_syncs_file = $config->{fail_syncs_dir}.$config->{name};

        # todo should we handle other error cases aswell?
        if ($exec_status == 35 || $exec_status == 10)
        {
            # 35 = connection timout
            # 10 = Error in socket IO
            debug_print("Connection timeout or unable to connect, touching $error_syncs_file\n");
            touch_file($error_syncs_file);
        }
        elsif (-e $error_syncs_file)
        {
            # syncs was successful or non fatal error
            debug_print("Removing $error_syncs_file\n");
            unlink $error_syncs_file;
        }
    }

    # Set end_time timestamp.
    $end_time = time();

    if (defined($config->{dry_run}) && $config->{dry_run}==1){
        log_print("Not inserting into database due to dry_run set\n");
    }
    else
    {
        my $error_message = insert_into_database($begin_time, $end_time, $exec_status, $log_file);

        if (length($error_message))
        {
            send_mail($config->{mail_errors_from},
                      $config->{mail_errors_to},
                      "The shit hit the fan when inserting into databae",
                      $error_message);
        }
    }

    return $exec_status;
}


sub abort_if_syncing($)
{
    my $config = shift @_;

    # eine kleine status variable
    my $synch_this_project = 1;

    # check if sync is currently running
    # delete all leftovers (if the server should crash during a sync)
    opendir(DIR, $config->{active_syncs_dir}) || die "can't opendir $config->{active_syncs_dir}: $!";
    my @pid_files = grep { /^$config->{name}\.[0-9]+$/ && -f "$config->{active_syncs_dir}/$_" } readdir(DIR);
    closedir DIR;
    foreach my $pid_file (@pid_files)
    {
        my $pid;
        if($pid_file =~ m/(\d+$)/) {
            $pid = $1;
        }
        else{die("Could not extract PID from $pid_file\n");}

        #check if process still exists
        if (kill (0, $pid)){
            #process still exists, we should not start sync of this project
            $synch_this_project = 0;
        }
        else{
            debug_print("No process with $pid exists\n");
            debug_print("removing file: $config->{active_syncs_dir}$pid_file\n");
            unlink "$config->{active_syncs_dir}$pid_file";
        }
    }

    if (!$synch_this_project){
        debug_print("Already syncing project: $config->{name}\n");
        debug_print("Aborting\n");
        exit(0);
    }
}


###
#  Main screen turn on
###

my $usage = <<END;
milko.pl [GLOBAL_CONFIG] <CONFIG_FILE> -- setting1=foo setting2=foo ...

Command line options overrides all other options.
CONFIG_FILE overrides options specified in GLOBAL_CONFIG.

END

die ($usage) if ($#ARGV == -1 );

die("File $ARGV[0] does not exist!")
  unless (-e $ARGV[0]);

# First read global config
$config = read_config($ARGV[0]);

# Then read the specific config for this project
if ($#ARGV>0 && $#ARGV ne "--"){
    die("File $ARGV[1] does not exist!")
        unless (-e $ARGV[1]);

    $config = read_append_config($config, $ARGV[1]);
}

# Finally read from command line
# Maybe some error handling here..
$config = args_append_config($config, @ARGV);

my $validation_error = validate_milko_config($config);
die ($validation_error) if length $validation_error;

if ($moo::common::DEBUG_PRINTS){
    dump_config($config);
}

# Check if this project is currently syncing.
# If syncing, then we should abort.
abort_if_syncing($config);

# $$ is current pid
my $pid_file = $config->{active_syncs_dir}.$config->{name}.".".$$;
my $log_file = "/var/run/milkyway/".$config->{name}.".".$$;

touch_file($pid_file)
  or die ("Could not touch file $pid_file\n");

my $exec_status = 0;
if (defined($config->{two_stage_sync}) && $config->{two_stage_sync} == 1)
{
    my $sync_sub_dir = "";
    my $ignore_items = "";
    my $delete = 1;

    $sync_sub_dir = $config->{first_sync_dir} if defined($config->{first_sync_dir});
    $ignore_items = $config->{first_ignore_items} if defined($config->{first_ignore_items});
    $delete = $config->{first_delete} if defined($config->{first_delete});

    $exec_status = execute_rsync($sync_sub_dir, $ignore_items, $delete, $log_file, $config);

    # only perform second stage if first was succesfull
    if ($exec_status == 0){
        $sync_sub_dir = "";
        $ignore_items = "";
        $delete = 1;

        $sync_sub_dir = $config->{second_sync_dir} if defined($config->{second_sync_dir});
        $ignore_items = $config->{second_ignore_items} if defined($config->{second_ignore_items});
        $delete = $config->{second_delete} if defined($config->{second_delete});

        $exec_status = execute_rsync($sync_sub_dir, $ignore_items, $delete, $log_file, $config);
    }
}
else
{
    $exec_status = execute_rsync("", "", 1, $log_file, $config);
}

# When sync has finshed successfully, update timestamp for status file
if ($exec_status == 0)
{
    # update tracefile
    if (defined($config->{time_stamp_file})){
        system "date -u > $config->{destination_dir}$config->{time_stamp_file}";
    }
    touch_file($config->{sync_status_dir}.$config->{name});
}

# remove log file
unlink ($log_file);

# finally remove pid_file
unlink($pid_file)
  or die ("Could not remove $pid_file");
