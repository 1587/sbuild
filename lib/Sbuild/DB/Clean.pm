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

package Sbuild::DB::Clean;

use strict;
use warnings;

use DBI;
use DBD::Pg;
use File::Temp qw(tempdir);
use Sbuild::Exception;
use Sbuild::DBUtil qw();
use Exception::Class::TryCatch;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw(actions clean clean_binaries clean_sources);
}

sub actions {
    return { "clean" =>
	     { "all" => \&clean,
	       "binaries" => \&clean_binaries,
	       "sources" => \&clean_sources,
	       "__default" => \&clean }
    };
}

sub clean {
    my $db = shift;

    clean_binaries($db);
    clean_sources($db);
}

sub clean_binaries {
    my $db = shift;

    my $conn = $db->get('CONN');

    print "Cleaning binaries...";
    STDOUT->flush();

    my $result = $conn->do("SELECT * FROM clean_binaries()");

    print "done.";

    print "\n";
    STDOUT->flush();
}

sub clean_sources {
    my $db = shift;

    my $conn = $db->get('CONN');

    print "Cleaning sources...";
    STDOUT->flush();

    my $results = $conn->do("SELECT * FROM clean_sources()");

    print "done.";
}


1;
