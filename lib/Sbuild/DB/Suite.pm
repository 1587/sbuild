#
# Copyright © 2011 Roger Leigh <rleigh@debian.org>
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

package Sbuild::DB::Suite;

use strict;
use warnings;

use DBI;
use DBD::Pg;
use File::Temp qw(tempdir);
use Sbuild::Exception;
use Sbuild::Base;
use Sbuild::DBUtil qw(escape_path download valid_changes);
use Exception::Class::TryCatch;
use Sbuild::DB::Key qw(key_verify_file);

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw(suite_fetch suite_add suite_update suite_remove
                 suite_show suite_list);
}

sub suite_fetch {
    my $db = shift;
    my $suitename = shift;

    my $conn = $db->get('CONN');

    # Try to get InRelease, then fall back to Release and Release.gpg
    # if not available.

    my $find = $conn->prepare("SELECT suitenick, key, uri, distribution FROM suites WHERE (suitenick = ?)");
    $find->bind_param(1, $suitename);
    $find->execute();
    my $rows = $find->rows();
    if (!$rows) {
	Sbuild::Exception::DB->throw
	    (error => "Suite ‘$suitename’ not found");
    }
    my $ref = $find->fetchrow_hashref();

    my $key = $ref->{'key'};
    my $uribase = $ref->{'uri'} . "/dists/" . $ref->{'distribution'};
    my $uri;
    my $stripuri;

    my $release;
    my $releasegpg;

    try eval {
	my $uri = $uribase . "/InRelease";
	# Remove protocol.
	my $stripuri = $uri;
	$stripuri =~ s|.*(//){1}?||;
	$release = download(URI => $uri,
			    FILE => escape_path($stripuri),
			    DIR => $db->get_conf('ARCHIVE_CACHE'));
	print "Downloaded $uri as " . escape_path($stripuri) . "\n";

	key_verify_file($db, $key,
			$db->get_conf('ARCHIVE_CACHE') . '/' . $release);
    };
    if (catch my $err) {
	print "InRelease not found; falling back to Release\n";
	$uri = $uribase . "/Release";
	$stripuri = $uri;
	$stripuri =~ s|.*(//){1}?||;
	$release = download(URI => $uri,
			    FILE => escape_path($stripuri),
			    DIR => $db->get_conf('ARCHIVE_CACHE'));

	$uri = $uribase . "/Release.gpg";
	$stripuri = $uri;
	$stripuri =~ s|.*(//){1}?||;
	$releasegpg = download(URI => $uri,
			       FILE => escape_path($stripuri),
			       DIR => $db->get_conf('ARCHIVE_CACHE'));

	key_verify_file($db, $key,
			$db->get_conf('ARCHIVE_CACHE') . '/' . $releasegpg,
			$db->get_conf('ARCHIVE_CACHE') . '/' . $release);
    }

    # Release file successfully downloaded and validated.  Now import
    # details.
}

sub suite_add {
    my $db = shift;
    my $suitename = shift;
    my $key = shift;
    my $uri = shift;
    my $distribution = shift;

    my $conn = $db->get('CONN');

    if (!$suitename) {
	Sbuild::Exception::DB->throw
	    (error => "No suitename, key, uri or distribution specified",
	     usage => "suite add <suitename> <key> <uri> <distribution>");
    }

    my $find = $conn->prepare("SELECT suitenick FROM suites WHERE (suitenick = ?)");
    $find->bind_param(1, $suitename);
    $find->execute();
    my $rows = $find->rows();
    if ($rows) {
	Sbuild::Exception::DB->throw
	    (error => "Suite ‘$suitename’ already exists");
    }

    my $insert = $conn->prepare("INSERT INTO suites (suitenick, key, uri, distribution) VALUES (?, ?, ?, ?)");
    $insert->bind_param(1, $suitename);
    $insert->bind_param(2, $key);
    $insert->bind_param(3, $uri);
    $insert->bind_param(4, $distribution);
    $rows = $insert->execute();
    print "Inserted $rows row(s)\n";
}

sub suite_update {
    my $db = shift;
    my $suitename = shift;
    my @changes = @_;

    if (!$suitename) {
	Sbuild::Exception::DB->throw
	    (error => "No suitename specified",
	     usage => "suite update <suitename> [key=<key>] [uri=<uri>] [distribution=<distribution>]");
    }

    if (@changes < 1) {
	Sbuild::Exception::DB->throw
	    (error => "No updates specified",
	     usage => "suite update <suitename> [key=<key>] [uri=<uri>] [distribution=<distribution>]");
    }

    my %changes = ();
    try eval {
	%changes = valid_changes(CHANGES=>\@changes, VALID=>[qw(key uri distribution)]);
    };
    if (catch my $err) {
	Sbuild::Exception::DB->throw
	    (error => $err,
	     usage => "suite update <suitename> [key=<key>] [uri=<uri>] [distribution=<distribution>]");
    }

    my $conn = $db->get('CONN');

    my $find = $conn->prepare("SELECT suitenick FROM suites WHERE (suitenick = ?)");
    $find->bind_param(1, $suitename);
    $find->execute();
    my $rows = $find->rows();
    if (!$rows) {
	Sbuild::Exception::DB->throw
	    (error => "Suite ‘$suitename’ does not exist");
    }

    foreach my $change (keys %changes) {
	my $update = $conn->prepare("UPDATE suites SET $change = ? WHERE (suitenick = ?)");
	$update->bind_param(1, $changes{$change});
	$update->bind_param(2, $suitename);
	$rows = $update->execute();
	print "Updated $rows row(s)\n";
    }
}

sub suite_remove {
    my $db = shift;
    my $suitename = shift;

    if (!$suitename) {
	Sbuild::Exception::DB->throw
	    (error => "No suite specified",
	     usage => "suite remove <suitename>");
    }

    if (@_) {
	Sbuild::Exception::DB->throw
	    (error => "Only one suite may be specified",
	     usage => "suite remove <suitename>");
    }

    my $conn = $db->get('CONN');

    my $delete = $conn->prepare("DELETE FROM suites WHERE (suitenick = ?)");
    $delete->bind_param(1, $suitename);
    my $rows = $delete->execute();
    print "Deleted $rows row(s)\n";
}

sub suite_show {
    my $db = shift;
    my $suitename = shift;

    if (!$suitename) {
	    Sbuild::Exception::DB->throw
		(error => "No suite specified",
		 usage => "suite show <suitename>");
    }

    if (@_) {
	Sbuild::Exception::DB->throw
	    (error => "Only one suite may be specified",
	     usage => "suite show <suitename>");
    }

    # TODO: Print detail from all table relations.
    print "$suitename\n";
}

sub suite_list {
    my $db = shift;
    my $suitename = shift;

    my $conn = $db->get('CONN');

    my $find = $conn->prepare("SELECT suitenick, key, uri, distribution FROM suites");
    $find->execute();
    while(my $ref = $find->fetchrow_hashref()) {
	print $ref->{'suitenick'};
	if ($db->get_conf('VERBOSE')) {
	    print " ($ref->{'key'} $ref->{'uri'} $ref->{'distribution'})\n";
	} else {
	    print "\n";
	}
    }
}

1;
