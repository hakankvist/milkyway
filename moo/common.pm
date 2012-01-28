package moo::common;

use strict;

BEGIN {
    use Exporter ();
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

    # set the version for version checking
    $VERSION = 0.05;

    @ISA         = qw(Exporter);
    @EXPORT      = qw(&read_config &read_append_config &args_append_config &validate_milko_config &dump_config &touch_file &send_mail
                    &debug_print &log_print);

    %EXPORT_TAGS = qw();                         # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK = qw($DEBUG_PRINTS %Hashit &func3);
}

use vars @EXPORT_OK;

# non-exported package globals go here
use vars qw(@more $stuff);

# initalize package globals, first exported ones
$DEBUG_PRINTS = 0;
%Hashit = ();

# then the others (which are still accessible as $Some::Module::stuff)
$stuff = '';
@more  = ();

# all file-scoped lexicals must be created before
# the functions below that use them.

# file-private lexicals go here
my $priv_var    = '';
my %secret_hash = ();


# DEFINED IN SQL!
# Rsync error codes.
#my %RSYNC_ERROR_CODES;
#$RSYNC_ERROR_CODES{0}="Success";
#$RSYNC_ERROR_CODES{1}="Syntax or usage error";
#$RSYNC_ERROR_CODES{2}="Protocol incompatibility";
#$RSYNC_ERROR_CODES{3}="Errors selecting input/output files, dirs";
#$RSYNC_ERROR_CODES{4}="Requested  action  not supported";
#$RSYNC_ERROR_CODES{5}="Error starting client-server protocol";
#$RSYNC_ERROR_CODES{6}="Daemon unable to append to log-file";
#$RSYNC_ERROR_CODES{10}="Error in socket I/O";
#$RSYNC_ERROR_CODES{11}="Error in file I/O";
#$RSYNC_ERROR_CODES{12}="Error in rsync protocol data stream";
#$RSYNC_ERROR_CODES{13}="Errors with program diagnostics";
#$RSYNC_ERROR_CODES{14}="Error in IPC code";
#$RSYNC_ERROR_CODES{20}="Received SIGUSR1 or SIGINT";
#$RSYNC_ERROR_CODES{21}="Some error returned by waitpid()";
#$RSYNC_ERROR_CODES{22}="Error allocating core memory buffers";
#$RSYNC_ERROR_CODES{23}="Partial transfer due to error";
#$RSYNC_ERROR_CODES{24}="Partial transfer due to vanished source files";
#$RSYNC_ERROR_CODES{25}="The --max-delete limit stopped deletions";
#$RSYNC_ERROR_CODES{30}="Timeout in data send/receive";
# DEFINED IN SQL!

# Reads configuration from the file specified in the first parameter
# returns a hash ref with the values read.
sub read_config($) {
    my $file_name = shift @_;

    return read_append_config( {}, $file_name );
}

# Reads configuration from the file specified in the last parameter
# first parameter is the hash where to put stuff in
# returns a hash ref with the values read.
sub read_append_config($$) {
    my $result_ref = shift @_;
    my $file_name  = shift @_;

    die("configuration file $file_name does not exist!\n")
      unless ( -e $file_name );

    open( FILE, $file_name )
      or die("Could not open configuration file: $file_name\n");

    while (<FILE>) {
        chomp;
        s/#.*//;
        s/^\s+//;
        s/\s+$//;
        next unless length;
        my ( $var, $value ) = split( /\s*=\s*/, $_, 2 );

        if ($value !~ m/^\s*$/)
        {
            debug_print("Setting key/value $var=$value\n");
            $result_ref->{$var} = $value;
        }
    }
    close(FILE);

    # append the name of this config to config path, since we want
    # to trace the configs included.
    unless ( defined $result_ref->{config_path} ) {
        $result_ref->{config_path} = $file_name;
    }
    else {
        $result_ref->{config_path} .= ", $file_name";
    }

    return $result_ref;
}

# First parameter is the hash where the configuration is stored
# The array is contains parameters sent to the application.
# Values before "--" are ignored.
# Value pairs after "--" are intepreted as configuration variables.
# Returns the configuration hash
sub args_append_config($@) {
    my $result_ref = shift @_;
    my @args = @_;

    #maybe some error handling here?

    while (@args && $args[0] ne "--") {
        shift @args;
    }
    if (@args && $args[0] eq "--") {
        shift @args;
    }

    debug_print("Command line values:", join(", ", @args), "\n");

    while (@args ){
        my $pair = shift @args;

        chomp $pair;
        $pair =~ s/#.*//;
        $pair =~ s/^\s+//;
        $pair =~ s/\s+$//;
        my ( $var, $value ) = split( /\s*=\s*/, $pair, 2 );

        if ($value !~ m/^\s*$/)
        {
            debug_print("Setting key/value $var=$value\n");
            $result_ref->{$var} = $value;
        }
        else {
            debug_print("Ignoring junk from command line: \"$pair\"\n");
        }
    }

    # Trace in some way?

    return $result_ref;
}


sub validate_milko_config($) {
    my $config = shift @_;

    my $error_mess = "";

    # directories that should be set
    foreach my $item (qw(active_syncs_dir sync_status_dir destination_dir fail_syncs_dir)) {
        $error_mess .= "\t $item is not set\n"
          unless ( defined( $config->{$item} ) );
        if ( defined( $config->{$item} ) ) {
            unless ( -d $config->{$item} ) {
                $error_mess .=
                  "\t Directory $item ($config->{$item}) does not exist!\n";
            }
            if ( $config->{$item} !~ m/\/$/ ) {
                $error_mess .=
                  "\t Directory $item MUST end with a trailing /!\n";
            }
        }
    }

    #sub directories must end with /
    foreach my $item (qw(second_sync_dir first_sync_dir)) {
        if ( defined( $config->{$item} ) ) {
            if ( $config->{$item} !~ m/\/$/ ) {
                $error_mess .=
                  "\t Directory $item MUST end with a trailing /!\n";
            }
        }
    }

    # variables that should be set
    foreach my $item (qw(name
                      database db_host db_port db_user db_password
                      mail_errors_from mail_errors_to))
    {
        $error_mess .= "\t $item is not set\n"
          unless ( defined( $config->{$item} ) );
    }

    # if we should login with username / password, then both
    # rsync_username / rsync_password should be set
    if ( defined($config->{rsync_username}) && !defined($config->{rsync_password}) )
    {
        $error_mess .= "\trsync_username is set but not rsync_password\n";
    }
    if ( !defined($config->{rsync_username}) && defined($config->{rsync_password}) )
    {
        $error_mess .= "\trsync_password is set but not rsync_username\n";
    }


    # sync_how_often is specially treated
    # example of valid values:
    # 3, 3h, 12m
    # default time unit is hours
    $error_mess .=
        "\t sync_how_often is not set properly\n"
      . "\t Should be <1-9*>[h|m]{0,1]}\n"
      unless ( defined( $config->{sync_how_often} )
        && $config->{sync_how_often} =~ m/^[\d]+(h|m|)$/ );

    #
    foreach my $item (qw(push_mirror two_stage_sync first_delete second_delete
                rsync_compress rsync_hardlinks rsync_delay_updates rsync_numeric_ids
                rsync_perserve_permissions rsync_copy_links dry_run))
    {
        if ( defined( $config->{$item} ) ) {
            $error_mess .=
                "\t $item must be set to 0 or 1 (or not set at all)\n"
                unless ( $config->{$item} =~ m/^[0|1]$/ );
        }
    }

    if ( defined( $config->{sync_at_time} ) ) {
        my @times = split( /\s*,\s*/, $config->{sync_at_time} );
        foreach my $time (@times) {
            $error_mess .= "\t \"$time\" is not a valid time, must be in range 00:00-23:59\n"
                unless ( $time =~ /^[0-1][0-9]:[0-5][0-9]$/ || $time =~ /^[2][0-3]:[0-5][0-9]$/);
        }
    }

    foreach my $item (qw(priority number_of_processes))
    {
        if ( defined( $config->{$item} ) ) {
            $error_mess .=
                "\t $item must be set to an integer (or not set at all)\n"
                unless ( $config->{$item} =~ m/^\d+$/ );
        }
    }

    if ( length($error_mess) ) {
        $error_mess =
            "Config generated from files: "
          . $config->{config_path} . "\n"
          . $error_mess;
        if ( defined( $config->{name} ) ) {
            $error_mess = $config->{name} . "\n" . $error_mess;
        }
        else {
            $error_mess .= "(unknown config name)\n$error_mess";
        }
        $error_mess = "(pid: $$) : Found errors in config: " . $error_mess;
    }

    return $error_mess;
}

# Dump a config to standard output
sub dump_config($) {
    my $config = shift @_;

    print "{\n";
    foreach my $key ( keys %$config ) {
        print "\t $key => $config->{$key}\n";
    }
    print "}\n";
}

# touch a file
sub touch_file($) {
    my $file_name = shift @_;

    if ( -e $file_name ) {

        #set time for file if it already exists
        utime undef, undef, $file_name
          or return 0;
    }
    else {

        # create file if it does not exists
        open( STATUS_FILE, ">$file_name" ) && close STATUS_FILE
          or return 0;
    }

    return 1;
}

# If arla is executed through cron the all messages sent to STDERR)
# (using warn in perl) should be sent by mail right?

# Sends a mail
sub send_mail($$$$) {
    my $from_adress = shift @_;
    my $to_adress   = shift @_;
    my $subject     = shift @_;
    my $message     = shift @_;
    my $config      = shift @_;

    # Note that if we can't mail, then we should really die

    my $mail_body = <<"EOF";
From: $from_adress
To: $to_adress
Subject: $subject

$message
EOF

    if (defined($config->{dry_run}) && $config->{dry_run}==1){
        print $mail_body;
    }
    else
    {
        #this example is taken from the perl documentation system
        open(SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq")
            or die ("Can't fork for sendmail: $!\n");
        print SENDMAIL $mail_body;

        close(SENDMAIL) or warn "sendmail didn't close nicely";

        debug_print($mail_body);
    }
}

# Use this command for debugprints
sub debug_print($)
{
    if($DEBUG_PRINTS){
        print "(pid: $$) : ";
        foreach my $apa (@_){
            print $apa;
        }
    }
}

sub log_print($)
{
    print "(pid: $$) : ";
    foreach my $apa (@_){
        print $apa;
    }
}


END { }              # module clean-up code here (global destructor)

1;
__END__
