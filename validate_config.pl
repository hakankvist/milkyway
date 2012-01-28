#!/usr/bin/perl -w

use DBI;

use strict;

# push path to common lib to @INC
use File::Basename 'dirname';
use lib dirname $0;
use moo::common;

# 1 - Debug prints enabled
# 0 - Debug prints disabled
$moo::common::DEBUG_PRINTS = 0;

# this milko config
my $config = {};

sub validate_database
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
            "\t$sql\n" .
            "\tThe project name must exist in the database prior to running milko\n";
    }
    $sth->finish();

    return $error_message;
}


###
#  Main screen turn on
###

my $usage = <<END;
validate_config.pl [GLOBAL_CONFIG] <CONFIG_FILE>

Options in CONFIG_FILE overrides options in GLOBAL_CONFIG

So a typicall execution will look like:

./validate_config.pl config/common.config config/debian.milko_config
END

die ($usage) unless ($#ARGV == 0 || $#ARGV == 1);

die("File $ARGV[0] does not exist!")
  unless (-e $ARGV[0]);

$config = read_config($ARGV[0]);

if ($#ARGV==1){
    die("File $ARGV[1] does not exist!")
        unless (-e $ARGV[1]);

    $config = read_append_config($config, $ARGV[1]);
}

my $validation_error = validate_milko_config($config);
die ($validation_error) if length $validation_error;

if ($moo::common::DEBUG_PRINTS){
    dump_config($config);
}

print ("\n\tIf you can see this message then the configuration is valid.\n\n");
