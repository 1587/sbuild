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

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter);

    @EXPORT = qw(escape_path download valid_changes);

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

	if (!rename($fh->filename, $dir . '/' . $file)) {
	    Sbuild::Exception::DB->throw
		(error => "Can't rename temporary file ‘" .
		 $fh->filename . "’ to ‘" . $dir . '/' . $file . "’");
	}

	print "Downloaded $uri to " . $dir . '/' . $file . "\n";
    };
    if (catch my $err) {
	    unlink $fh->filename;
	    $err->rethrow();
    }

    return $file;
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
