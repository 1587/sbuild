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
use Sbuild::DBUtil qw(fetch_gpg_key valid_changes);
use Exception::Class::TryCatch;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw(suite_fetch_release suite_add suite_update
                 suite_remove suite_show suite_list);
}

sub suite_fetch_release {
    my $self = shift;
    my $name = shift;
    my $uri = shift;
    my $distribution = shift;

    my $conn = $self->get('CONN');

    # Try to get InRelease, then fall back to Release and Release.gpg
    # if not available.
}

sub suite_add {
    my $self = shift;
    my $suitename = shift;
    my $uri = shift;
    my $distribution = shift;

    my $conn = $self->get('CONN');

    if (!$suitename) {
	Sbuild::Exception::DB->throw
	    (error => "No suitename, uri or distribution specified",
	     usage => "suite add <suitename> <uri> <distribution>");
    }

    my $find = $conn->prepare("SELECT suitenick FROM suites WHERE (suitenick = ?)");
    $find->bind_param(1, $suitename);
    $find->execute();
    my $rows = $find->rows();
    if ($rows) {
	Sbuild::Exception::DB->throw
	    (error => "Suite ‘$suitename’ already exists");
    }

    my $insert = $conn->prepare("INSERT INTO suites (suitenick, uri, distribution) VALUES (?, ?, ?)");
    $insert->bind_param(1, $suitename);
    $insert->bind_param(2, $uri);
    $insert->bind_param(3, $distribution);
    $rows = $insert->execute();
    print "Inserted $rows row(s)\n";
}

sub suite_update {
    my $self = shift;
    my $suitename = shift;
    my @changes = @_;

    if (!$suitename) {
	Sbuild::Exception::DB->throw
	    (error => "No suitename specified",
	     usage => "suite update <suitename> [uri=<uri>] [distribution=<distribution>]");
    }

    if (@changes < 1) {
	Sbuild::Exception::DB->throw
	    (error => "No updates specified",
	     usage => "suite update <suitename> [uri=<uri>] [distribution=<distribution>]");
    }

    my %changes = ();
    try eval {
	%changes = valid_changes(CHANGES=>\@changes, VALID=>[qw(uri distribution)]);
    };
    if (catch my $err) {
	Sbuild::Exception::DB->throw
	    (error => $err,
	     usage => "suite update <suitename> [uri=<uri>] [distribution=<distribution>]");
    }

    my $conn = $self->get('CONN');

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
    my $self = shift;
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

    my $conn = $self->get('CONN');

    my $delete = $conn->prepare("DELETE FROM suites WHERE (suitenick = ?)");
    $delete->bind_param(1, $suitename);
    my $rows = $delete->execute();
    print "Deleted $rows row(s)\n";
}

sub suite_show {
    my $self = shift;
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
    my $self = shift;
    my $suitename = shift;

    my $conn = $self->get('CONN');

    my $find = $conn->prepare("SELECT suitenick, uri, distribution FROM suites");
    $find->execute();
    while(my $ref = $find->fetchrow_hashref()) {
	print $ref->{'suitenick'};
	if ($self->get_conf('VERBOSE')) {
	    print " ($ref->{'uri'} $ref->{'distribution'})\n";
	} else {
	    print "\n";
	}
    }
}

1;
