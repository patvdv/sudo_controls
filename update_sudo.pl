#!/usr/bin/env perl
#******************************************************************************
# @(#) update_sudo.pl
#******************************************************************************
# @(#) Copyright (C) 2014 by KUDOS BVBA <info@kudos.be>.  All rights reserved.
#
# This program is a free software; you can redistribute it and/or modify
# it under the same terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details
#******************************************************************************
# This script distributes SUDO fragments to the appropriate files into a
# designated repository based on the 'grants', 'alias' and 'fragments' files.
# Superfluous usage of 'hostname' reporting in log messages is encouraged to
# make reading of multiplexed output from update_sudo.pl through backgrounded
# jobs via manage_sudo.sh much easier.
#
# @(#) HISTORY: see perldoc 'update_sudo.pl'
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

#******************************************************************************
# PRAGMAs/LIBs
#******************************************************************************

use strict;
use Net::Domain qw(hostfqdn hostname);
use POSIX qw(uname);
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use File::Temp qw(tempfile);


#******************************************************************************
# DATA structures
#******************************************************************************

# ------------------------- CONFIGURATION starts here -------------------------
# define the V.R.F (version/release/fix)
my $MY_VRF = "1.1.0";
# name of global configuration file (no path, must be located in the script directory)
my $global_config_file = "update_sudo.conf";
# name of localized configuration file (no path, must be located in the script directory)
my $local_config_file = "update_sudo.conf.local";
# selinux context label of sudoers fragment files
my $selinux_context = "etc_t";
# ------------------------- CONFIGURATION ends here --------------------------- 
# initialize variables
my ($debug, $verbose, $preview, $global, $use_fqdn) = (0,0,0,0,0);
my (@config_files, $fragments_dir, $visudo_bin, $immutable_self_file, $immutable_self_cmd);
my (%options, %aliases, %frags, @grants);
my ($os, $host, $hostname, $run_dir);
my ($selinux_status, $selinux_context, $has_selinux) = ("","",0);
$|++;


#******************************************************************************
# SUBroutines
#******************************************************************************

# -----------------------------------------------------------------------------
sub do_log {
    
    my $message = shift;

    if ($message =~ /^ERROR:/ || $message =~ /^WARN:/) {
        print STDERR "$message\n";
    } elsif ($message =~ /^DEBUG:/) {
        print STDOUT "$message\n" if ($debug);
    } else {
        print STDOUT "$message\n" if ($verbose);
    }

    return (1);
}

# -----------------------------------------------------------------------------
sub parse_config_file {

    my $config_file = shift;

    unless (open (CONF_FD, "<", $config_file)) {
        do_log ("ERROR: failed to open the configuration file ${config_file} [$! $hostname]") 
        and exit (1);
    }
    while (<CONF_FD>) {
        chomp ();
        # parse settings
        if (/^\s*$/ || /^#/) {
            next;
        } else {
            if (/^\s*use_fqdn\s*=\s*([0-9]+)\s*$/) {
                $use_fqdn = $1;
                do_log ("DEBUG: picking up setting: use_fqdn=${use_fqdn}");
            }
            if (/^\s*fragments_dir\s*=\s*([0-9A-Za-z_\-\.\/~]+)\s*$/) {
                $fragments_dir = $1;
                do_log ("DEBUG: picking up setting: fragments_dir=${fragments_dir}");
            }
            if (/^\s*visudo_bin\s*=\s*([0-9A-Za-z_\-\.\/~]+)\s*$/) {
                $visudo_bin = $1;
                do_log ("DEBUG: picking up setting: visudo_bin=${visudo_bin}");
            }
            if (/^\s*immutable_self_file\s*=\s*([0-9A-Za-z_\-\.\/~]+)\s*$/) {
                $immutable_self_file = $1;
                do_log ("DEBUG: picking up setting: immutable_self_file=${immutable_self_file}");
            }
            if (/^\s*immutable_self_cmd\s*=\s*([0-9A-Za-z_\-\.\/~%:=\(\) ]+)\s*$/) {
                $immutable_self_cmd = $1;
                do_log ("DEBUG: picking up setting: immutable_self_cmd=${immutable_self_cmd}");
            }
        }
    }
    
    # parameter checks
    if (not defined ($immutable_self_file) or $immutable_self_file eq "") {
        do_log ("ERROR: 'immutable_self_file' parameter not defined [$hostname]")
        and exit(1);
    }

    return (1);
}

# -----------------------------------------------------------------------------
sub resolve_aliases
{
    my $input = shift;
    my (@tmp_array, @new_array, $entry);

    @tmp_array = split (/,/, $input);
    foreach $entry (@tmp_array) {
        if ($entry =~ /^\@/) {
            ($aliases{$entry})
                ? push (@new_array, @{$aliases{$entry}}) 
                : do_log ("WARN: unable to resolve alias $entry [$hostname]");
        } else {
            ($entry)
                ? push (@new_array, $entry)
                : do_log ("WARN: unable to resolve alias $entry [$hostname]");
        }
    }
    return (@new_array);
}

# -----------------------------------------------------------------------------
sub set_file {

    my ($file, $perm, $uid, $gid) = @_;
    
    chmod ($perm, "$file") 
        or do_log ("ERROR: cannot set permissions on $file [$! $hostname]")
        and exit (1);
    chown ($uid, $gid, "$file")
        or do_log ("ERROR: cannot set ownerships on $file [$! $hostname]")
        and exit (1);   
        
    return (1);
}


#******************************************************************************
# MAIN routine
#******************************************************************************

# -----------------------------------------------------------------------------
# process script arguments & options
# -----------------------------------------------------------------------------

if ( @ARGV > 0 ) {
    Getopt::Long::Configure ('prefix_pattern=(--|-|\/)', 'bundling', 'no_ignore_case');
    GetOptions (\%options,
            qw(
                debug|d
                help|h|?
                global|g
                preview|p
                verbose|v
                version|V
            )) || pod2usage(-verbose => 0);
}
pod2usage(-verbose => 0) unless (%options);         
            
# check version parameter
if ($options{'version'}) {
    $verbose = 1;
    do_log ("INFO: $0: version $MY_VRF");
    exit (0);
}
# check help parameter
if ($options{'help'}) {
    pod2usage(-verbose => 3);
    exit (0);
};
# check global parameter
if ($options{'global'}) {
    $global = 1;
}
# check preview parameter
if ($options{'preview'}) {
    $preview = 1;
    $verbose = 1;
    if ($global) {
        do_log ("INFO: running in GLOBAL PREVIEW mode");    
    } else {
        do_log ("INFO: running in PREVIEW mode");
    }
} else {
    do_log ("INFO: running in UPDATE mode");
}
# debug & verbose
if ($options{'debug'}) {
    $debug   = 1;
    $verbose = 1;
}
$verbose = 1 if ($options{'verbose'});

# what am I?
$os = `uname`;
chomp ($os);
# who am I?
unless ($preview and $global) {
    if ($< != 0) {
        do_log ("ERROR: script must be invoked as user 'root' [$hostname]") 
        and exit (1);
    }
}
# where am I?
unless ($use_fqdn) {
    $hostname = hostfqdn();
} else {
    $hostname = hostname();
}
$0 =~ /^(.+[\\\/])[^\\\/]+[\\\/]*$/;
my $run_dir = $1 || ".";
$run_dir =~ s#/$##;     # remove trailing slash

do_log ("INFO: runtime info: ".getpwuid ($<)."; ${hostname}\@${run_dir}; Perl v$]"); 

# -----------------------------------------------------------------------------
# check/process configuration files, environment checks
# -----------------------------------------------------------------------------

# don't do anything without configuration file(s)
do_log ("INFO: parsing configuration file(s) ...");
push (@config_files, "$run_dir/$global_config_file") if (-f "$run_dir/$global_config_file");
push (@config_files, "$run_dir/$local_config_file") if (-f "$run_dir/$local_config_file");
unless (@config_files) {
    do_log ("ERROR: unable to find any configuration file, bailing out [$hostname]") 
    and exit (1);
}

# process configuration file: global first, local may override
foreach my $config_file (@config_files) {
    parse_config_file ($config_file);
}

# is the target directory for fragments present? (not for global preview)
unless ($preview and $global) {
    do_log ("INFO: checking for SUDO control mode ...");
    if (-d $fragments_dir) {
        do_log ("INFO: host is under SUDO control via $fragments_dir");
    } else {
        do_log ("ERROR: host is not under SUDO control [$hostname]") 
        and exit (1);
    }
}

# is syntax checking possible? (not for global preview)
unless ($preview and $global) {
    unless (-x $visudo_bin) {
        do_log ("ERROR: 'visudo' tool could not be found, will not continue [$hostname]") 
        and exit (1);
    }
}

# -----------------------------------------------------------------------------
# read aliases for teams, servers and users
# result: %aliases
# -----------------------------------------------------------------------------

do_log ("INFO: reading 'alias' file ...");

open (ALIASES, "<", "${run_dir}/alias")
    or do_log ("ERROR: cannot read 'alias' file [$! $hostname]") and exit (1);
while (<ALIASES>) {

    my ($key, $value, @values);
    
    chomp ();
    next if (/^$/ || /\#/);
    s/\s+//g;
    ($key, $value) = split (/:/);
    next unless ($value);
    @values = sort (split (/\,/, $value));
    $aliases{$key} = [@values];
};
close (ALIASES);
do_log ("DEBUG: dumping unexpanded aliases:");
print Dumper (\%aliases) if $debug;

# we can nest aliases one level deep, so do a one-level recursive sort of lookup
# of the remaining '@' aliases. Input should be passed as comma-separated
# string to resolve_aliases so don't forget to smash everything back together
# first.
foreach my $key (keys (%aliases)) {

    $aliases{$key} = [resolve_aliases (join (",", @{$aliases{$key}}))]; 
}

do_log ("INFO: ".scalar (keys (%aliases))." aliases found on $hostname");
do_log ("DEBUG: dumping expanded aliases:");
print Dumper (\%aliases) if $debug;

# -----------------------------------------------------------------------------
# read SUDO fragments stored in a single 'fragments' file or in 
# individual fragment files from a 'fragments.d' directory 
# result: %frags
# -----------------------------------------------------------------------------

do_log ("INFO: reading 'fragment' file(s) ...");

my @frag_files;

# check if the SUDO fragments are stored in a directory or file
if (-d "${run_dir}/fragments.d" && -f "${run_dir}/fragments") {
    do_log ("WARN: found both a 'fragments' file and 'fragments.d' directory. Ignoring the 'fragments' file [$hostname]")
}
if (-d "${run_dir}/fragments.d") {
    do_log ("INFO: local 'fragments' are stored in a DIRECTORY on $hostname");
    opendir (FRAGS_DIR, "${run_dir}/fragments.d")
        or do_log ("ERROR: cannot open 'fragments.d' directory [$! $hostname]") 
        and exit (1);
    while (my $frag_file = readdir (FRAGS_DIR)) {
        next if ($frag_file =~ /^\./);
        push (@frag_files, "${run_dir}/fragments.d/$frag_file");
    }
    closedir (FRAGS_DIR);    
} elsif (-f "${run_dir}/fragments") {
    do_log ("INFO: local 'fragments' are stored in a FILE on $hostname");
    push (@frag_files, "${run_dir}/fragments");
} else {
    do_log ("ERROR: cannot find any SUDO fragments in the repository! [$hostname]") 
    and exit (1);
}

# process 'fragments' files
foreach my $frag_file (@frag_files) {
    open (FRAGS, "<", $frag_file)
        or do_log ("ERROR: cannot read 'fragments' file [$! $hostname]") 
        and exit (1);
    do_log ("INFO: reading SUDO fragments from file: $frag_file");
    
    my @frag_file = <FRAGS>;
    
    # check for fragments header(s): if there is no fragment header, then we
    # consider this a single fragment file, otherwise we consider it a 
    # collection of fragments that needs to be broken down in individual fragments
    
    if (grep { /^%%%/s } @frag_file) {
    
        do_log ("INFO: fragment file $frag_file contains multiple fragments, parsing ...");
        
        my ($frag_file, $frag_def);
        my $count = 1;
        
        foreach (@frag_file) {
        
            # first header found
            if (/^%%%/ && (not defined ($frag_def) or $frag_def eq "")) {

                # look for fragment file name
                ($frag_file) = (split (/%%%/, $_))[1];
                chomp ($frag_file);
                unless (defined ($frag_file) && $frag_file ne "") {
                    do_log ("WARN: no fragment file name found in header at line $count [$hostname]")
                }
            # next header found, flush previous fragment
            } elsif (/^%%%/ && (defined ($frag_def) or $frag_def ne "")) {
                if (defined ($frag_file) && $frag_file ne "") {
                    $frags{$frag_file} = $frag_def;
                    undef $frag_def;
                } else {
                    do_log ("WARN: fragment without file name? (to line: $count) [$hostname]");
                }
                undef $frag_file;
                # get new file name
                ($frag_file) = (split ('%%%', $_))[1];
                chomp ($frag_file);
                unless (defined ($frag_file) && $frag_file ne "") {
                    do_log ("WARN: no fragment file name found in header at line $count [$hostname]")
                }          
            } else {
                # process fragment definition
                $frag_def .= $_;
            }
            # check for last fragment
            if ($frag_file && $frag_def ne "") {
                $frags{$frag_file} = $frag_def;
            }
            $count++;
        };
    } else {
        # strip off path from file name for hash key
        $frag_file = fileparse ($frag_file, qr/\.[^.]*/);
        do_log ("INFO: fragment file $frag_file contains only 1 fragment on $hostname");
        $frags{$frag_file} = join (/\n/, @frag_file);
    }   
    close (FRAGS);
}

do_log ("INFO: ".scalar (keys (%frags))." SUDO fragment(s) found on $hostname");
print Dumper(\%frags) if $debug;

# -----------------------------------------------------------------------------
# syntax checking sudo fragments (visudo)
# -----------------------------------------------------------------------------

do_log ("INFO: syntax checking sudo fragments ...");

# create one large sudoers file out of the fragments, if the syntax check fails
# then we keep the temporary file for further inspection
my ($sudo_fh, $sudo_file) = tempfile(UNLINK => 0);
print $sudo_fh join("\n", map { "$frags{$_}" } keys %frags);
$sudo_fh->flush;
my @syntax_check = `${visudo_bin} -c -f $sudo_file 2>/dev/null`;
if ($? == 0) {
    do_log ("INFO: syntax check of sudo fragments is OK on $hostname");
    unlink $sudo_file;
} else {
    do_log "ERROR: visudo check failed: ".join ("\n", @syntax_check)." [$hostname]" 
    and exit(1);
}

# -----------------------------------------------------------------------------
# read grant definitions
# result: @grants (array): fragments for which grants have been defined 
# for this server.
# -----------------------------------------------------------------------------

do_log ("INFO: reading 'grants' file ...");

open (GRANTS, "<", "${run_dir}/grants")
    or do_log ("ERROR: cannot read 'grants' file [$! $hostname]") and exit (1);
while (<GRANTS>) {

    my ($what, $where, @what, @where);
    
    chomp ();
    next if (/^$/ || /\#/);
    s/\s+//g;
    ($what, $where) = split (/:/);
    next unless ($where);
    @what  = resolve_aliases ($what);
    @where = resolve_aliases ($where);
    unless (@what and @where) {
        do_log ("WARN: ignoring line $. in 'grants' due to missing/non-resolving values [$hostname]");
        next;
    }
    
    foreach my $grant (sort (@what)) {
        foreach my $server (sort (@where)) {
            do_log ("DEBUG: adding grants for $grant on $server in \@grants") 
                if ($server eq $hostname);
            # add sudo fragment to grants list if the entry is for this host
            push (@grants, $grant) if ($server eq $hostname);
        }
    }
};
close (GRANTS);

# remove duplicates in @grants
@grants = keys (%{{ map { $_ => 1 } @grants}});

do_log ("INFO: ".scalar (@grants)." SUDO fragments with applicable grants requested on $hostname");
print Dumper(\@grants) if $debug;

# -----------------------------------------------------------------------------
# global preview, show full configuration data only
# -----------------------------------------------------------------------------

if ($preview && $global) {

    open (GRANTS, "<", "${run_dir}/grants")
        or do_log ("ERROR: cannot read 'grants' file [$! $hostname]") and exit (1);
    while (<GRANTS>) {

        my ($what, $where, @what, @where);
    
        chomp ();
        next if (/^$/ || /\#/);
        s/\s+//g;
        ($what, $where) = split (/:/);
        next unless ($where);
        @what  = resolve_aliases ($what);
        @where = resolve_aliases ($where);
        unless (@what and @where) {
            do_log ("WARN: ignoring line $. in 'grants' due to missing/non-resolving values [$hostname]");
            next;
        }
    
        foreach my $grant (sort (@what)) {
            foreach my $server (sort (@where)) {
                do_log ("$grant|$server") 
            }
        }
    };
    close (GRANTS);
    
    exit (0);
}

# -----------------------------------------------------------------------------
# distribute sudo fragments into $fragments_dir
# -----------------------------------------------------------------------------

do_log ("INFO: (de)-activating SUDO fragments ....");

# check for SELinux
unless ($preview) {
    SWITCH: {
        $os eq "Linux" && do { 
            $selinux_status = qx#/usr/sbin/getenforce 2>/dev/null#;
            chomp ($selinux_status);
            if ($selinux_status eq "Permissive" or $selinux_status eq "Enforcing") {
                do_log ("INFO: runtime info: detected active SELinux system on $hostname");
                $has_selinux = 1;
            }
            last SWITCH; 
        };
    }
}

# remove previous fragment files first
opendir (FRAGS_DIR, "${fragments_dir}")
    or do_log ("ERROR: cannot open ${fragments_dir} directory [$! $hostname]") 
    and exit (1);
while (my $frag_file = readdir (FRAGS_DIR)) {
    next if ($frag_file =~ /^\./ or $frag_file eq $immutable_self_file);
    # safe to ignore . (dot) files as sudo also does as well
    
    unless ($preview) {
        
        my $frag_file = "$fragments_dir/$frag_file";
    
        if (unlink ($frag_file)) {
            do_log ("INFO: de-activating fragment file $frag_file on $hostname");     
        } else {
            do_log ("ERROR: cannot de-activate fragment file(s) [$! $hostname]");
            exit (1);
        }
    }
}
closedir (FRAGS_DIR);    

# re-active current fragments
foreach my $grant (@grants) {

    # do not create empty sudo files
    if (exists ($frags{$grant})) {
    
        my $sudo_file = "$fragments_dir/$grant";
        
        unless ($preview) {
            open (SUDO_FILE, "+>", $sudo_file)
                or do_log ("ERROR: cannot open file for writing in $fragments_dir [$! $hostname]")
                and exit (1);
        }
        print SUDO_FILE "$frags{$grant}\n" unless $preview;
        do_log ("INFO: activating fragment $grant on $hostname");
        close (SUDO_FILE) unless $preview;
        
        # set permissions to world readable & SELinux contexts
        unless ($preview) {
            SWITCH: {
                $os eq "HP-UX" && do { 
                    set_file ($sudo_file, 0440, 2, 2); 
                    last SWITCH; 
                };
                $os eq "Linux" && do { 
                    if ($has_selinux) {
                        system ("/usr/bin/chcon -t $selinux_context $sudo_file") ||
                            do_log ("WARN: failed to set SELinux context $selinux_context on $sudo_file [$hostname]");
                    }
                    set_file ($sudo_file, 0440, 0, 0);
                    last SWITCH;                
                };
            }
        }
    } else {
        do_log ("WARN: no matching SUDO rule found available for $grant [$hostname]");
    }
}

# re-apply the immutable self fragment, just in case ;-)
unless ($preview) {

    my $self_file = "$fragments_dir/$immutable_self_file";

    open (SELF_FILE, "+>", $self_file)
        or do_log ("ERROR: cannot open file for writing in $fragments_dir [$! $hostname]")
        and exit (1);

    print SELF_FILE "# THIS IS THE IMMUTABLE SELF FRAGMENT OF SUDO CONTROLS\n";
    print SELF_FILE $immutable_self_cmd."\n";
    do_log ("INFO: activating immutable self fragment $immutable_self_file on $hostname");
    SWITCH: {
        $os eq "HP-UX" && do { 
            set_file ($self_file, 0440, 2, 2); 
            last SWITCH;
        };
        $os eq "Linux" && do { 
        if ($has_selinux) {
            system ("/usr/bin/chcon -t $selinux_context $self_file") ||
                do_log ("WARN: failed to set SELinux context $selinux_context on $self_file [$hostname]");
            }
            set_file ($self_file, 0440, 0, 0);
            last SWITCH;                
        };
    }
    close (SELF_FILE);   
}

exit (0);

#******************************************************************************
# End of SCRIPT
#******************************************************************************

#******************************************************************************
# POD
#******************************************************************************

# -----------------------------------------------------------------------------

=head1 NAME

update_sudo.pl - distributes SUDO fragments according to a desired state model.

=head1 SYNOPSIS

    update_sudo.pl [-d|--debug] 
                   [-h|--help] 
                   ([-p|--preview] [-g|--global])
                   [-v|--verbose]
                   [-V|--version]

                 
=head1 DESCRIPTION

B<update_sudo.pl> distributes SUDO fragments into the C<$fragments_dir> repository based on the F<grants>, F<alias> and F<fragments> files.
This script should be run on each host where SUDO is the required method of privilege escalation. 

For update SUDO fragments must be stored in a generic F<fragments> file within the same directory as B<update_sudo.pl> script. 
Alternatively SUDO fragments may be stored as set of individual files within a called sub-directory called F<fragments.d>. 
Both methods are mutually exclusive and the latter always take precedence.

=head1 CONFIGURATION

B<update_sudo.pl> requires the presence of at least one of the following configuration files:

=over 2

=item * F<update_sudo.conf>

=item * F<update_sudo.conf.local>

=back 

Use F<update_sudo.conf.local> for localized settings per host. Settings in the localized configuration file will always override other values.

Following settings must be configured:

=over 2

=item * B<fragments_dir>        : target directory for SUDO fragments files

=item * B<visudo_bin>           : path to the visudo tool (for sudo rules syntax checking)

=item * B<immutable_self_file>  : name of the file that contains sudo code to allow this script to run with elevated privileges

=back

=head1 OPTIONS

=over 2

=item -d | --debug

S<       >Be I<very> verbose during execution; show array/hash dumps.

=item -h | --help

S<       >Show the help page.

=item -p | --preview

S<       >Do not actually distribute any SUDO fragments, nor update/remove SUDO files.

=item -p | --global

S<       >Must be used in conjunction with the --preview option. This will dump the global namespace/configuration to STDOUT.

=item -v | --verbose

S<       >Be verbose during exection.
       
=item -V | --version

S<       >Show version of the script.

=back 

=head1 NOTES

=over 2

=item * Options may be preceded by a - (dash), -- (double dash) or a / (slash).

=item * Options may be bundled (e.g. -vp)

=back 

=head1 AUTHOR

(c) KUDOS BVBA, Patrick Van der Veken

=head1 HISTORY

@(#) 2014-12-04: VRF 1.0.0: first version [Patrick Van der Veken]
@(#) 2014-12-16: VRF 1.0.1: added SELinux context [Patrick Van der Veken]
@(#) 2014-12-16: VRF 1.0.2: fixed a problem with the immutable self fragment code [Patrick Van der Veken]
@(#) 2015-02-02: VRF 1.0.3: changed 'basename' into 'fileparse' call to support fragment files with extensions [Patrick Van der Veken]
@(#) 2015-08-18: VRF 1.1.0: replace uname/hostname syscalls, now support for FQDN via $use_fqdn, other fixes [Patrick Van der Veken]