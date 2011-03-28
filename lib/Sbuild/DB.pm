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

package Sbuild::DB;

use strict;
use warnings;

use DBI;
use DBD::Pg;
use File::Temp qw(tempdir);
use Sbuild::Exception;
use Sbuild::Base;
use Exception::Class::TryCatch;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw();
}

sub new {
    my $class = shift;
    my $conf = shift;

    my $self = $class->SUPER::new($conf);
    bless($self, $class);

    my $dbservice = $self->get_conf('DBSERVICE');
    my $dbuser = $self->get_conf('DBUSER');
    my $dbpassword = $self->get_conf('DBPASSWORD');
    my $conn = DBI->connect("DBI:Pg:service=$dbservice",$dbuser,$dbpassword,
	{RaiseError => 1});
    if (!$conn) {
	Sbuild::Exception::DB->throw
	    (error => "Can't connect to database service ‘$dbservice’ as user ‘$dbuser’")
    }
    $self->set('CONN', $conn);

    return $self;
}

1;
