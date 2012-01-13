#
# DBUtil: Database utility functions
# Copyright © 2005 Ryan Murray <rmurray@debian.org>
# Copyright © 2005-2008 Roger Leigh <rleigh@debian.org
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see
# <http://www.gnu.org/licenses/>.
#
#######################################################################

package Sbuild::DBUtil;

use strict;
use warnings;

use File::Temp;
use LWP::Simple;
use Sbuild qw(isin);
use Sbuild::Exception;
use Exception::Class::TryCatch;
use Digest::SHA qw();
use File::stat;
use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter);

    @EXPORT = qw(uncompress escape_path check_file_hash_size download download_cached_distfile valid_changes);

}

sub uncompress {
    my $file = shift;

    my $buffer;

    if (!anyuncompress($file,\$buffer)) {
 	Sbuild::Exception::DB->throw
	    (error => "Failed to decompress %file: $AnyUncompressError")
    }

    return $buffer;
}

sub escape_path {
    my $path=shift;

    # Filename quoting for safety taken from apt URItoFileName and
    # QuoteString.
    my @chars = split('', $path);

    foreach(@chars) {
	if (index('\\|{}[]<>"^~_=!@#$%^&*', $_) != -1 || # "Bad" characters
	    !m/[[:print:]]/ || # Not printable
	    ord($_) == 0x25 || # Percent '%' char
	    ord($_) <= 0x20 || # Control chars
	    ord($_) >= 0x7f) { # Control chars
	    $_ = sprintf("%%%02x", ord($_));
	}
    }

    my $uri = join('', @chars);
    $uri =~ s;/;_;g; # Escape slashes

    return $uri;
}

# This method is used to retrieve a file, usually from a location on the
# Internet, but it can also be used for files in the local system.
# $url is location of file, $file is path to write $url into.
sub download {
    my %opts = @_;

    # The parameters will be any URI and a location to save the file to.
    my $uri = $opts{URI};
    my $file = $opts{FILE};
    my $dir = $opts{DIR};
    my $dest = $dir . "/" . $file;

    # print "URI: $uri\n";
    # print "FILE: $file\n";
    # print "DIR: $dir\n";

    Sbuild::Exception::DB->throw
	(error => "download: Missing arguments")
	if (!$uri || !$file || !$dir);


    # If $uri is a readable plain file on the local system, just return the
    # $uri.
    # TODO: Copy to cache.
    return $uri if (-f $uri && -r $uri);

    # Filehandle we'll be writing to.
    my $fh = File::Temp->new(DIR=>$dir, TEMPLATE=>$file . "XXXXXX",UNLINK=>0)
	or Sbuild::Exception::DB->throw
	(error => "Can't create temporary file");

    try eval {
	my $content = get($uri)
	    or Sbuild::Exception::DB->throw
	    (error => "Can't fetch URI ‘$uri’");

	print $fh $content;
	$fh->flush();
	$fh->close; # Close the destination file

	# Print out amount of content received before returning the path of the
	# file.
	# print "Download of $uri sucessful.\n";
	# print "Size of content downloaded: ";
	# use bytes;
	# print bytes::length($content) . "\n";

	if (!rename($fh->filename, $dest)) {
	    Sbuild::Exception::DB->throw
		(error => "Can't rename temporary file ‘" .
		 $fh->filename . "’ to ‘" . $dest . "’");
	}

#	print "Downloaded $uri to $dest\n";
    };
    if (catch my $err) {
	    unlink $fh->filename;
	    $err->rethrow();
    }

    return $dest;
}

sub check_file_hash_size {
    my $file = shift;
    my $sha256 = shift;
    my $size = shift;

    my $st = stat($file);
    if (!$st) {
#	print "Can't stat $file: $!\n";
	return 0;
    }

    if ($size != $st->size) {
#	print "File size mismatch for $file: should be $size, but is " . $st->size . "\n";
	return 0;
    }

    my $exsha = Digest::SHA->new('SHA256');
    $exsha->addfile($file);
    my $exdigest = $exsha->hexdigest();

    if ($sha256 ne $exdigest) {
	print "File SHA256 mismatch for $file: should be $sha256, but is $exdigest\n";
	return 0;
    }

#    print "Downloaded file $file size and SHA256 match, using cached copy\n";
    return 1;
}

# This method is used to retrieve a file, usually from a location on
# the Internet, but it can also be used for files in the local system.
# This downloads relative to /dists/distribution, and also does SHA256/size
# checking (optional).
# $url is location of file, $file is path to write $url into.
sub download_cached_distfile {
    my %opts = @_;

    # The parameters will be any URI and a location to save the file to.
    my $uri = $opts{URI};
    my $dist = $opts{DIST};
    my $file = $opts{FILE};
    my $bz2file = $opts{BZ2FILE};
    my $cdir = $opts{CACHEDIR};

    Sbuild::Exception::DB->throw
	(error => "download_cached_distfile: Missing arguments")
	if (!$uri || !$dist || !$file || !$cdir);

    $uri = "$uri/dists/$dist/$file->{'NAME'}";

    STDOUT->flush;

    my $stripuri = $uri;
    $stripuri =~ s|.*(//){1}?||;
    my $cfile = escape_path($stripuri);

    # If file exists locally, verify it if SHA256 sum and size are given.
    if ($file->{'SHA256'} && $file->{'SIZE'} &&
	check_file_hash_size("$cdir/$cfile", $file->{'SHA256'}, $file->{'SIZE'})) {
	    return "$cdir/$cfile";
	    # Mismatch or no hash/size, so download again
	}

    my $dlfile;
    if ($bz2file) {
	$dlfile = download_cached_distfile(URI=>$opts{URI},
					   DIST=>$opts{DIST},
					   FILE=>$bz2file,
					   CACHEDIR=>$opts{CACHEDIR});

	if (-f "$cdir/$cfile") {
	    unlink "$cdir/$cfile" or
		Sbuild::Exception::DB->throw
		(error => "Failed to unlink $dlfile: $!");
	}

	my $status = system('bunzip2', $dlfile);
	if ($status) {
	    Sbuild::Exception::DB->throw
		(error => "Failed to bunzip2 decompress $dlfile: $status $!");
	}
	$dlfile = "$cdir/$cfile";
    } else {
	$dlfile = download(URI=>$uri, DIR=>$cdir, FILE=>$cfile);
    }

    if ($file->{'SHA256'} && $file->{'SIZE'} &&
	!check_file_hash_size($dlfile, $file->{'SHA256'}, $file->{'SIZE'})) {
	Sbuild::Exception::DB->throw
	    (error => "$dlfile: SHA256 or size mismatch")
    }

    return $dlfile;
}

sub valid_changes {
    my %opts = @_;

    if (!$opts{'CHANGES'} || !$opts{'VALID'}) {
	Sbuild::Exception::DB->throw
	    (error => "Missing CHANGES or VALID");
    }

    my %changes = ();
    foreach my $change (@{$opts{'CHANGES'}}) {
	my ($key, $value);
	my $match = ($change =~ m/([^=]+)=(.*)/);
	if (!$match || !isin($1, @{$opts{'VALID'}})) {
	    Sbuild::Exception::DB->throw
		(error => "Bad value ‘$change’");
	}
	$changes{$1} = $2;
    }
    return %changes;
}

1;
