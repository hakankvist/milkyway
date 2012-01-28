#!/usr/bin/perl -w

use strict;
use Cwd 'abs_path';
use DateTime; # Get this from CPAN or ports or whatever

# push path to common lib to @INC
use File::Basename qw(dirname basename);
use lib dirname $0;
use moo::common;

# 1 - Debug prints enabled
# 0 - Debug prints disabled
$moo::common::DEBUG_PRINTS = 0;
if (basename(__FILE__) eq "arla_debug.pl") {
    $moo::common::DEBUG_PRINTS = 1;
}

# Default config dir
my $CONFIG_DIR = File::Spec->catfile(abs_path(dirname(__FILE__)), "config");
# Name of common config-file:
my $COMMON_CONFIG_FILE = "common.conf";
# Name of arla-config file
my $ARLA_CONFIG_FILE = "arla.conf";

# The extension of the sync-files
my $SYNC_EXTENSION = ".milko_conf";
# The directory where status for syncs are saved
my $SYNC_STATUS_DIR;
# The directory where we list current active syncs
my $ACTIVE_SYNCS_DIR;
# The directory where we list fucked up syncs (host down)
my $FAIL_SYNCS_DIR;

# this hashref contains the configuration for Arla
my $arla_config;

# This array contains all sync-configs for the different projects
my @sync_configs;

# This array contains all settings specified on the command line,
# these settings are passed on to all instances of milko.
my @command_line_params;

sub read_milko_configs
{
    opendir(DIR, $CONFIG_DIR) || die "can't opendir $CONFIG_DIR: $!";
    my @philez = grep { /$SYNC_EXTENSION$/ && -f "$CONFIG_DIR/$_" } readdir(DIR);
    closedir DIR;

    for my $file (@philez){
        # first read global config
        my $config = read_config(File::Spec->catdir($CONFIG_DIR, $COMMON_CONFIG_FILE));

        # the read project specific config
        # (options here may override values in global config)
        debug_print("Reading: $file\n");
        $config = read_append_config($config, File::Spec->catdir($CONFIG_DIR, $file));

        # Append parameters read from command line
        $config = args_append_config($config, @ARGV);

        # set priority if not set.
        if (!defined($config->{priority})){
            $config->{priority} = 999;
        }

        my $fail_file = $FAIL_SYNCS_DIR.$config->{name};
        $config->{failed_sync} = 0;
        # find out if this project failed during last sync
        if ( -e $fail_file )
        {
            # Using the timestamp will make sure that files
            # projects gets sycned in the right order.
            # (non broken projects will be synced first (0) and so on)
            $config->{failed_sync} = (stat($fail_file))[9];
        }

        push @sync_configs, $config;
    }

    my $validation_message = "";
    # validate
    for my $config (@sync_configs){
        my $temp = validate_milko_config($config);
        if (length $temp){
            $validation_message .= "------------------------------------------------------------\n";
            $validation_message .= $temp;
            $temp .= '\n';

            # mark this config as invalid
            $config->{ERROR_IN_CONFIG} = 1;
        }
    }
    if (length $validation_message){
        $validation_message .= "Some configurations were found to be invalid\n.".
                               "All invalid configurations will be ignored!\n".
                               $validation_message;
        $validation_message .= "------------------------------------------------------------\n";

        send_mail($arla_config->{mail_errors_from},
                  $arla_config->{mail_errors_to},
                  "Errors found in ftp sync configuration files!",
                  $validation_message);
    }
    #die ($validation_message) if length $validation_message;
}

###
#  Main screen turn on
###
$arla_config = read_config(File::Spec->catdir($CONFIG_DIR, $COMMON_CONFIG_FILE));
$arla_config = read_append_config($arla_config, File::Spec->catdir($CONFIG_DIR, $ARLA_CONFIG_FILE));
$arla_config = args_append_config($arla_config, @ARGV);
$SYNC_STATUS_DIR = $arla_config->{sync_status_dir};
$ACTIVE_SYNCS_DIR = $arla_config->{active_syncs_dir};
$FAIL_SYNCS_DIR = $arla_config->{fail_syncs_dir};

# set number of processes if not set.
if (!defined($arla_config->{number_of_processes})){
    $arla_config->number_of_processes = 8;
}

die("Sync status directory does not exist: $SYNC_STATUS_DIR")
    unless (-d $SYNC_STATUS_DIR);
die("Active syncs directory does not exist: $ACTIVE_SYNCS_DIR")
    unless (-d $ACTIVE_SYNCS_DIR);

# get rid of the junk we don't need, only leave
# -- bla=blabla blablabla=blabla
@command_line_params = @ARGV;
while (@command_line_params && $command_line_params[0] ne '--')
{
    shift @command_line_params;
}

#
# Now read all milko configuration files
read_milko_configs();

#
# Number of active syncs.
my $active_syncs=0;

# First count all syncs currently running
# Also find out the time of latest successfull sync
foreach my $config (@sync_configs){
    # check if sync is currently running
    # delete all leftovers (if the server should crash during a sync)
    opendir(DIR, $ACTIVE_SYNCS_DIR) || die "can't opendir $ACTIVE_SYNCS_DIR: $!";
    my @pid_files = grep { /^$config->{name}\.[0-9]+$/ && -f "$ACTIVE_SYNCS_DIR/$_" } readdir(DIR);
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
            #process still exists, increment counter
            $active_syncs++;
        }
        else{
            debug_print("No process with $pid exists\n");
            debug_print("removing file: $ACTIVE_SYNCS_DIR$pid_file\n");
            unlink "$ACTIVE_SYNCS_DIR$pid_file";
        }
    }

    my $last_synced_file = File::Spec->catdir($SYNC_STATUS_DIR, $config->{name});

    if (-e $last_synced_file)
    {
        $config->{last_synched} = (stat($last_synced_file))[9];
    }
    else
    {
        $config->{last_synched} = 0;
    }
    debug_print("Latest modified (from $last_synced_file): $config->{last_synched}\n");
}

# Now sync all remaining projects (if active_syncs is within limits)
# syncs projects with lowest prio first and sync most outdated project first
foreach my $config (sort { $a->{failed_sync} <=> $b->{failed_sync} ||
                           $a->{priority} <=> $b->{priority} ||
                           $a->{last_synched} <=> $b->{last_synched} }  @sync_configs){
    debug_print("$config->{name}, failed: $config->{failed_sync} prio: $config->{priority}, last sync: $config->{last_synched}\n");

    # eine kleine status variable
    my $synch_this_project = 1;

    # check if sync is currently running
    # delete all leftovers (if the server should crash during a sync)
    opendir(DIR, $ACTIVE_SYNCS_DIR) || die "can't opendir $ACTIVE_SYNCS_DIR: $!";
    my @pid_files = grep { /^$config->{name}\.[0-9]+$/ && -f "$ACTIVE_SYNCS_DIR/$_" } readdir(DIR);
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
            debug_print("removing file: $ACTIVE_SYNCS_DIR$pid_file\n");
            unlink "$ACTIVE_SYNCS_DIR$pid_file";
        }
    }

    # Cleanup of old leftovers have now been performed, we can now proceed
    # with the more "advanced sync logic"

    # If this config has been marked as invalid, then ignore
    if ($synch_this_project)
    {
        if (defined($config->{ERROR_IN_CONFIG})){
            $synch_this_project = 0;
            debug_print("This project config ($config->{name}) contains errors, ignoring\n");
        }
    }

    # If this project uses push mirroring, then arla.pl should NOT
    # initiate the synch
    if ($synch_this_project)
    {
        if (defined($config->{push_mirror}) && $config->{push_mirror} == 1)
        {
            $synch_this_project = 0;
            debug_print("This project is synched with PUSH MIRRORING, ignoring\n");
        }
    }

    if ($synch_this_project)
    {
        if ($active_syncs >= $arla_config->{number_of_processes}){
            $synch_this_project = 0;
            debug_print("Maximum number of running syncs reached, not syncing ($config->{name})\n");
        }
    }

    # Check if the project is fresh enough (=> no synch)
    # or if the project is outdated and should be synched
    if ($synch_this_project)
    {
        my $how_often = 0;
        my $time_in_minutes = 0; # default time in hours

        # how_often specifies default number of hours between syncs
        # may be suffixed with:
        #     m -minutes
        #     h -hours
        # no suffix will default to hours
        if ($config->{sync_how_often} =~ m/^([\d]+)(h|m|)$/){
            $how_often = $1;
            if ($2 eq "m"){
                $how_often *= 60;
            }
            else{
                #if suffix is h or empty
                $how_often *= 3600;
            }
            debug_print("Calculated how often to $how_often\n");
        }
        else{
            die ("Failed reading/parsing how_often for $config->{name}\n");
        }

        if (time() - $config->{last_synched} < $how_often)
        {
            $synch_this_project = 0;
            debug_print("This project is fresh, ignoring\n");
        }

        # if the timestamp is fresh enough check if we should sync on specific times
        # and check if the project has been synced at/after that time today
        if (!$synch_this_project && defined($config->{sync_at_time}))
        {
            my @times = split(/\s*,\s*/, $config->{sync_at_time});

            foreach my $time (@times){
                # get current timestamp
                my $dt = DateTime->from_epoch( epoch => time() );

                my ($hh, $mm) = split(/\s*:\s*/, $time, 2);

                $dt->set(hour => $hh);
                $dt->set(minute => $mm);

                if ($dt->epoch() <= time() && $config->{last_synched} < $dt->epoch())
                {
                    # this project needs to be resynced
                    $synch_this_project = 1;
                }
            }
        }
    }

    # If project should be synched call ./milko with project config as parameter
    if ($synch_this_project)
    {
        my $pid = fork();
        if ($pid == 0){
            my $path_to_milko;
            if (basename(__FILE__) eq "arla_debug.pl") {
                $path_to_milko  = File::Spec->catfile(abs_path(dirname(__FILE__)), "milko_debug.pl");
            }
            else {
                $path_to_milko  = File::Spec->catfile(abs_path(dirname(__FILE__)), "milko.pl");
            }

            exec ($path_to_milko, split(/\s*,\s*/, $config->{config_path}), @command_line_params)
                or die ("Could not start $path_to_milko $config->{config_path}\n");
        }
        elsif(!defined($pid)){
            die ("Could not fork, config: $config->{config_path}\n");
        }
        else{
            $active_syncs++;
            debug_print("Succesfully forked for config: $config->{name}\n");
        }
    }
}

debug_print("All configs read, all done\n");
