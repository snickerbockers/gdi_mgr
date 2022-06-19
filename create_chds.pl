#!/usr/bin/env perl

use v5.20;

use File::Spec::Functions 'catfile';
use File::Basename;

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
                say "gdi file found to be $node";
                $gdi_file = $full_path;
            }
        }
    }

    closedir($dh);

    return $gdi_file;
}

for (@ARGV) {
    if (!m/\.gdi$/i) {
        next unless (-d);
        # need to find the .gdi file
        $_ = get_gdi_path($_);
    }
    say "about to come up with a new name for \"$_\"";
    # my ($filename, $dirs, $suffix) = fileparse($_);
    # my $outfile = catfile($dirs, $filename) . ".chd";
    my $outfile = $_;
    $outfile =~ s/\.gdi/\.chd/i;
    say "outfile is \"$outfile\"";

    `chdman createcd -o "$outfile" -i "$_"` or die "failure on \"$_\"";
}
