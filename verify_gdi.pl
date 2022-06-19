#!/usr/bin/env perl

use v5.20;

use File::Spec::Functions 'catfile';
use File::Basename;
use XML::LibXML;
use Getopt::Std;

my $verbose_mode = 0;
my $romdir; # directory holding the .gdi

sub say_verbose {
    if ($verbose_mode) {
        say $_[0];
    }
}

sub exit_error {
    say "INPUT: '$romdir'";
    say "\tERROR: @_[0]";
    exit 2;
}

# given the path to the .gdi file, get a list of files in that .gdi file
# paths returned are relative to the directory the .gdi is in; they are not
# full paths
sub enum_gdi_files {
    my $gdi_path = @_[0];

    # need to store the relative path of the gdi so we separate out the dirs
    my ($filename, $dirs, $suffix) = fileparse($gdi_path);
    my @file_list = ( $filename . $suffix );

    open my $dh, "<", $gdi_path or exit_error("could not open $gdi_path");

    for (<$dh>) {
        chomp;
        my @fields = split;
        next if(scalar(@fields) < 5);
        push @file_list, $fields[4];
    }

    close $dh;

    return @file_list;
}

# given a game's name and a pointer to the tosec dom, get a reference to a hash of files and their md5sums
sub tosec_file_list {
    (my $title, my $tosec) = @_;

    for my $game ($tosec->findnodes('/datafile/game')) {
        my $game_name = $game->{name};
        if ($game_name eq $title) {
            my %files;
            for my $rom ($game->getElementsByTagName('rom')) {
                $files{$rom->{name}} = $rom->{md5};
            }
            return %files;
        }
    }
    return undef;
}

################################################################################
#
# md5sum_directory
#
# This function will iterate through all files in the given directory and return
# a reference to a hash which maps file paths to the md5sums of the given files
#
# ARGUMENTS:
#     string representing a path to the directory which contains the .gdi and
#         the binary track files
#
################################################################################
sub md5sum_directory {
    my $gdi_dir = @_[0];
    my %res;

    exit_error("\"$gdi_dir\" is not a directory!") if !(-d $gdi_dir);
    say_verbose("going to try to open $gdi_dir");
    opendir(my $gdi_dir_handle, $gdi_dir) or return undef;
    say_verbose('well we got it open...');
    while (readdir $gdi_dir_handle) {
        next if -d $_;
        my $full_path = catfile($gdi_dir, $_);
        my @md5sum = split(/\s/, `md5sum $full_path`);
        $res{$full_path} = $md5sum[0];
    }
    closedir($gdi_dir_handle);

    return \%res;
}

# file_list must be full paths
# returns hash that maps paths to md5sums
sub md5sum_files {
    my %res;
    my @file_list = @{$_[0]};

    for (@file_list) {
        say_verbose("md5sum $_");
        my @md5sum = split(/\s/, `md5sum "$_"`);
        $res{$_} = $md5sum[0];
    }
    return \%res;
}

################################################################################
#
# get_gdi_path
#
# returns the full path to the .gdi file, or undef if there is none (or if
#     there's more than one)
#
# ARGUMENTS:
#     string representing a path to the directory which contains the .gdi and
#         the binary track files
#
################################################################################
sub get_gdi_path {
    my $gdi_dir = @_[0];
    my $gdi_file = undef;

    -d $gdi_dir or return undef;
    opendir(my $dh, $gdi_dir) or return undef;

    # make sure there's a .gdi file
    while (readdir $dh) {
        next if -d;
        my $node = $_;
        my $full_path = catfile($gdi_dir, $node);
        if ($node =~ m/\.gdi$/ && -r $full_path) {
            if ($gdi_file) {
                # we don't allow for duplicate .gdi files
                return undef;
            } else {
                say_verbose("gdi file found to be $node");
                $gdi_file = $full_path;
            }
        }
    }

    closedir($dh);

    return $gdi_file;
}

my $use_str =
    "usage: verify_gdi -t <path_to_tosec.xml> -g <path_to_gdi_directory>";

our $opt_t;
our $opt_g;
our $opt_v;
getopts('t:g:v');

$opt_g or exit_error($use_str);
$opt_t or exit_error($use_str);

$verbose_mode = $opt_v;

$romdir = $opt_g;
my $tosec_path = $opt_t;

# correct input if the user gave us a path to the .gdi file instead of its
# parent directory
if ($romdir =~ m/\.gdi$/i) {
    my $orig_gdi_path = $romdir;
    my ($filename, $dirs, $suffix) = fileparse($romdir);
    if (get_gdi_path($dirs) eq $romdir) {
        $romdir = $dirs;
    }
}
(my $gdi_path = get_gdi_path($romdir))
    || exit_error("$romdir is not a valid GDI image");

say_verbose("gdi found at \"$gdi_path\"");

my @file_list = enum_gdi_files($gdi_path);

say_verbose("checking $romdir against $tosec_path...");

my $xml_parser = XML::LibXML->new;
my $tosec = $xml_parser->parse_file($tosec_path) or exit_error("unable to load TOSEC database");

# hash that maps gdi directories to game names in the TOSEC.
my %roms;

my $n_roms = 0;

my @file_list_full_paths;
for (@file_list) {
    say_verbose($_);
    my $full_gdi_path = catfile($romdir, $_);
    push @file_list_full_paths, $full_gdi_path;
}

my %md5sums = %{md5sum_files(\@file_list_full_paths)};

# hash that maps romfile paths to the identified romfile and game
my %rom_id;

 gdi:
    for my $romfile (keys(%md5sums)) {
        say_verbose("evaluating $romfile, md5sum $md5sums{$romfile}...");
        $rom_id{$romfile} = [ ];
        for my $game ($tosec->findnodes('/datafile/game')) {
            for my $tosec_rom ($game->getElementsByTagName('rom')) {
                my $md5_expect = $tosec_rom->{md5};

                if ($md5_expect eq $md5sums{$romfile}) {
                    push @{$rom_id{$romfile}}, [$tosec_rom->{name}, $game->{name}];
                }
            }
        }
}

# for each matched game, count the number of matched roms
# the one that matches the most is the one this game probably is
my %pop_count;

for my $romfile (keys(%rom_id)) {
    my $rom_list = $rom_id{$romfile};
    say_verbose("$romfile has " . scalar(@{$rom_list}) . " matches:");

    for my $match (@{$rom_list}) {
        say_verbose("\tmatch is \"$match->[0]\" in \"$match->[1]\"");
        if (defined($pop_count{$match->[1]})) {
            $pop_count{$match->[1]}++;
        } else {
            $pop_count{$match->[1]} = 1;
        }
    }
}

my $max = 0;
my @match_list;
for my $game (keys(%pop_count)) {
    if ($pop_count{$game} > $max) {
        $max = $pop_count{$game};
        @match_list = ( $game );
    } elsif ($pop_count{$game} == $max) {
        push @match_list, $game;
    }
}

if ($max <= 0) {
    say "INPUT: '$romdir'";
    say "\tNO BEST MATCH FOUND";
    say "\tCOMMENT: entirely unable to identify game";
    exit 1;
}

if (scalar(@match_list) != 1) {
    say "INPUT: '$romdir'";
    say "\tNO BEST MATCH FOUND";
    say "COMMENT: more than one best candidates found:";
    for my $match(@match_list) {
        say "\tCOMMENT: could be '$match'";
    }
    exit 1;
}

my $best_match = $match_list[0];

say_verbose("this game is most likely \"$best_match\"");

my $error_count = 0;
# TODO: verify that all roms needed for $best_match are present
for my $game ($tosec->findnodes('/datafile/game')) {
    if ($game->{name} eq $best_match) {
      tosec_rom:
        for my $tosec_rom ($game->getElementsByTagName('rom')) {
            # TODO check all roms to make sure there's one for the
            # current rom
            for my $romfile (keys(%md5sums)) {
                if ($md5sums{$romfile} eq $tosec_rom->{md5}) {
                    next tosec_rom;
                }
            }
            say_verbose("ERROR - could not find a match for $tosec_rom->{name}");
            $error_count++;
        }
    }
}

# generate final report in an easily-parsable format
say "INPUT: '$romdir'";
say "\tBEST MATCH: '$best_match'";
if ($error_count == 0) {
    say "\tCONFIRMATION: '$best_match'";
    say "\tCOMMENT: identity successfully confirmed.";
    exit 0;
} else {
    say "\tNO CONFIRMATION";
    say "\tCOMMENT: the input did not match all files required by '$best_match' and therefore was not confirmed";
    exit 1;
}
