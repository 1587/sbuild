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

package Sbuild::DB::Action::Admin;

use strict;
use warnings;

use DBI;
use DBD::Pg;
use File::Temp qw(tempdir);
use Sbuild qw(debug);
use Sbuild::Exception;
use Sbuild::DBUtil qw();
use Exception::Class::TryCatch;
use Module::Pluggable search_path => ['Sbuild::DB::Schema'], instantiate => 'new';

our %schemas;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw(actions);

    # Register actions
    foreach my $p (plugins()) {
	my $version = $p->sversion();
	debug("Found plugin: $p, schema version: $version\n");
	$schemas{$version} = $p;
    }
}

sub actions {
    return { "admin" =>
	     { "schemaver" => \&admin_schemaver,
	       "setup" => \&admin_setup,
	       "upgrade" => \&admin_upgrade }
    };
}

sub admin_schemaver {
    my $db = shift;

    my $conn = $db->connect(1);

    try eval {
	my $ver = $conn->prepare("SELECT max(version) AS max FROM schema");
	$ver->execute();

	my $vref = $ver->fetchrow_hashref();

	my $version = $vref->{'max'};
	return $version;
    };

    if (catch my $err) {
	print STDERR "I: Database does not have a schema table\n";
	return undef;
    }
}


sub admin_setup {
    my $db = shift;

    my $conn = $db->connect(1);

    my $version = admin_schemaver($db);
    if (!defined($version)) {
	foreach my $ver (sort keys %schemas) {
	    print "Setting up schema version: $ver\n";
	    my $schema = $schemas{$ver};
	    $schema->upgrade($db);
	}
    } else {
	print STDOUT "Database appears to be initialised, and at schema version $version\n";
    }
}

sub admin_upgrade {
    my $db = shift;

    my $conn = $db->connect(1);

    my $version = admin_schemaver($db);
    if (defined($version)) {
	foreach my $ver (sort keys %schemas) {
	    print "Setting up schema version: $ver\n";
	    my $schema = $schemas{$ver};
	    $schema->upgrade($db);
	}
    } else {
	print STDOUT "Database appears to be uninitialised; run setup first\n";
    }
}

1;
