#!/usr/bin/env perl

use v5.20;

use File::Spec::Functions 'catfile';
use XML::LibXML;
use Data::Dumper;
use Set::Scalar;

# sub ident_file {
#     my $gdi_path = $_[0];
#     my @csum = split(/\s/, `md5sum $gdi_path`);
#     my $dom = $_[1];

#     for my $game ($dom->findnodes('/datafile/game')) {
#         my $title = $game->{name};
#         #say "game found - $title";
#         for my $rom ($game->getElementsByTagName('rom')) {
#             my $md5 = $rom->{md5};
#             if ($md5 eq $csum[0]) {
#                 #say "file $gdi_path matches $rom->{name} in $title";
#                 return [$title, $rom->{name}];
#             }
#         }
#     }
#     return undef;
# }

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

    die "$gdi_dir is not a directory!" if !(-d $gdi_dir);
    say "going to try to open $gdi_dir";
    opendir(my $gdi_dir_handle, $gdi_dir) or return undef;
    say 'well we got it open...';
    while (readdir $gdi_dir_handle) {
        next if -d $_;
        my $full_path = catfile($gdi_dir, $_);
        my @md5sum = split(/\s/, `md5sum $full_path`);
        $res{$full_path} = $md5sum[0];
    }
    closedir($gdi_dir_handle);

    return \%res;
}

my $romdir = $ARGV[0];
my $tosec_path = $ARGV[1];

say "checking $romdir against $tosec_path...";

my $xml_parser = XML::LibXML->new;
my $tosec = $xml_parser->parse_file($ARGV[1]) or die "unable to load TOSEC database";

# hash that maps gdi directories to game names in the TOSEC.
my %roms;

my $n_roms = 0;

my %gdi_list;

opendir(my $dh, $romdir) or die "unable to open $romdir";
while (readdir $dh) {
    next if $_ eq '.' or $_ eq '..';
    say "evaluating md5 checksum of $_...";
    $n_roms++;

    my $full_gdi_path = catfile($romdir, $_);

    my $file_list = md5sum_directory($romdir);
    next if !defined($file_list);
    say 'alright its goin\' in the file list...';
    $gdi_list{$full_gdi_path} = $file_list;

    # $roms{$full_gdi_path} = Set::Scalar->new();
    # opendir(my $gdi_dir_handle, $full_gdi_path);
    # while (readdir $gdi_dir_handle) {
    #     next if $_ eq '.' or $_ eq '..';
    #     my $full_path = catfile($full_gdi_path, $_);
    #     my $match = ident_file($full_path, $tosec);
    #     if (defined($match)) {
    #         $roms{$full_gdi_path} += $match->[0];
    #         say "$full_path is a match for $match->[1] in $match->[0]";
    #     }
    # }
    #closedir($gdi_dir_handle);
}
closedir($dh);

#say Dumper \%gdi_list;

 gdi:
for my $gdi (keys(%gdi_list)) {
    say "evaluating $gdi...";

    my $gdi_files = $gdi_list{$gdi};

  tosec_game:
    for my $game ($tosec->findnodes('/datafile/game')) {
      romfile:
        for my $romfile ($game->getElementsByTagName('rom')) {
            my $md5_expect = $romfile->{md5};

            for my $md5_actual (values(%$gdi_files)) {
                if ($md5_actual eq $md5_expect) {
                    next romfile;
                }
            }
            next tosec_game;
      }
        say "$gdi identified as \"$game->{name}\"";
        next gdi;
    }

    say "unable to make definite identification of $gdi";
}

# say "=========================================================================";
# say "==";
# say "== total of " . scalar(%roms) . " / $n_roms rom matches found";
# say "==";
# say "=========================================================================";

# #say Dumper \%roms;

# for my $gdi_path (keys(%roms)) {
#     my $matches = $roms{$gdi_path};
#     say "$gdi_path: " . $matches->size . " candidates found";

#     for my $game ($matches->elements) {
#         say "\t$game";
#         my %files = tosec_file_list($game, $tosec);
#         for my $filename (keys(%files)) {
#             say "\t\t$filename => $files{$filename}";
#         }
#     }
# }

# #say "%roms";

# #for my $gdi_path (keys(%roms)) {
# #    say "$_........................$roms{$_}";
# #}

# #my $match = ident_file("/home/snickers/dreamcast_rips/sonic_adventure/track03.bin",
# #                       $tosec);


# #say "first arg is $ARGV[0]";

# # opendir(my $dir, "$ARGV[0]") or die "unable to open $ARGV[0]";

# # while (my $gdi_dir = readdir($dir)) {
# #     next if ($gdi_dir eq '.' or $gdi_dir eq '..');
# #     say "found $gdi_dir";
# # }

# # close($dir);
