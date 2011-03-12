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

package Sbuild::DB::Key;

use strict;
use warnings;

use DBI;
use DBD::Pg;
use File::Temp qw(tempdir);
use Sbuild::Exception;
use Sbuild::DBUtil qw(fetch_gpg_key);
use Exception::Class::TryCatch;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw(key_add key_update key_remove key_verify_file
                 key_show key_list);
}


sub key_add {
    my $db = shift;
    my $keyname = shift;
    my @keys = @_;

    my $conn = $db->get('CONN');

    if (!$keyname) {
	Sbuild::Exception::DB->throw
	    (error => "No keyname specified",
	     usage => "key add <keyname> <keyid1> [<keyid>]");
    }

    if (@keys < 1) {
	Sbuild::Exception::DB->throw
	    (error => "No keyid specified",
	     usage => "key add <keyname> <keyid1> [<keyid>]");
    }

    my $find = $conn->prepare("SELECT name FROM keys WHERE (name = ?)");
    $find->bind_param(1, $keyname);
    $find->execute();
    my $rows = $find->rows();
    if ($rows) {
	Sbuild::Exception::DB->throw
	    (error => "Key ‘$keyname’ already exists");
    }

    my $file = $db->fetch_gpg_key(@keys);
    if (!$file) {
	Sbuild::Exception::DB->throw
	    (error => "Failed to get gpg key");
    }

    my $insert = $conn->prepare("INSERT INTO keys (name, key) VALUES (?, ?)");
    $insert->bind_param(1, $keyname);
    $insert->bind_param(2, $file, { pg_type=>DBD::Pg::PG_BYTEA });
    $rows = $insert->execute();
    print "Inserted $rows row(s)\n";
}

sub key_update {
    my $db = shift;
    my $keyname = shift;
    my @keys = @_;

    if (!$keyname) {
	Sbuild::Exception::DB->throw
	    (error => "No keyname specified",
	     usage => "key update <keyname> <keyid1> [<keyid>]");
    }

    if (@keys < 1) {
	Sbuild::Exception::DB->throw
	    (error => "No keyid specified",
	     usage => "key update <keyname> <keyid1> [<keyid>]");
    }

    my $conn = $db->get('CONN');

    my $find = $conn->prepare("SELECT name FROM keys WHERE (name = ?)");
    $find->bind_param(1, $keyname);
    $find->execute();
    my $rows = $find->rows();
    if (!$rows) {
	Sbuild::Exception::DB->throw
	    (error => "Key ‘$keyname’ does not exist");
    }

    my $file = $db->fetch_gpg_key(@keys);
    if (!$file) {
	Sbuild::Exception::DB->throw
	    (error => "Failed to get gpg key");
    }

    my $update = $conn->prepare("UPDATE keys SET key = ? WHERE (name = ?)");
    $update->bind_param(1, $file, { pg_type=>DBD::Pg::PG_BYTEA });
    $update->bind_param(2, $keyname);
    $rows = $update->execute();
    print "Updated $rows row(s)\n";
}

sub key_remove {
    my $db = shift;
    my $keyname = shift;

    if (!$keyname) {
	Sbuild::Exception::DB->throw
	    (error => "No key specified",
	     usage => "key remove <keyname>");
    }

    if (@_) {
	Sbuild::Exception::DB->throw
	    (error => "Only one key may be specified",
	     usage => "key remove <keyname>");
    }

    my $conn = $db->get('CONN');

    my $delete = $conn->prepare("DELETE FROM keys WHERE (name = ?)");
    $delete->bind_param(1, $keyname);
    my $rows = $delete->execute();
    print "Deleted $rows row(s)\n";
}

sub key_verify_file {
    my $db = shift;
    my $keyname = shift;
    my @filenames = shift;

    if (!$keyname) {
	Sbuild::Exception::DB->throw
	    (error => "No key specified",
	     usage => "key verify <keyname> <filename> [<detachedsig>]");
    }

    if (!@filenames) {
	Sbuild::Exception::DB->throw
	    (error => "No file specified",
	     usage => "key verify <keyname> <filename> [<detachedsig>]");
    }

    my $key = $db->_find_key($keyname);
    if (!$key) {
	Sbuild::Exception::DB->throw
	    (error => "Key ‘$keyname’ not found");
    }

    # Create temporary GPG keyring with keys from database, and then
    # verify the specified file.  Use --trust-model=always, because
    # the keys are supposedly manually vetted before import.

    my $tempdir = tempdir(TEMPLATE=>'sbuild-db-verify-XXXXXX',
	TMPDIR=>1, CLEANUP=>1);
    local $ENV{'GNUPGHOME'} = $tempdir;
    $SIG{PIPE} = 'IGNORE';
    open(my $fh, '|-', 'gpg', '--import')
	or die 'Can\'t open pipe to gpg';
    binmode($fh,":raw");
    print $fh $key;
    $fh->flush;
    if (!$fh->close()) {
	Sbuild::Exception::DB->throw
	    (error => "Error closing gpg pipe: $?");
    }

    my $status = system('gpgv', '--keyring', "$tempdir/pubring.gpg", @filenames);
    if ($status) {
	Sbuild::Exception::DB->throw
	    (error => "Error verifying signature on ‘$filenames[0]’: $?");
    }
}

sub _find_key {
    my $db = shift;
    my $keyname = shift;

    my $key = undef;
    if ($keyname) {
	my $conn = $db->get('CONN');

	my $find = $conn->prepare("SELECT key FROM keys WHERE (name = ?)");
	$find->bind_param(1, $keyname);
	$find->execute();
	my $rows = $find->rows();
	if (!$rows) {
	    Sbuild::Exception::DB->throw
		(error => "Key ‘$keyname’ not found");
	}

	my $ref = $find->fetchrow_hashref();
	$key = $ref->{'key'};
    }

    return $key;
}

sub key_show {
    my $db = shift;
    my $keyname = shift;

    if (!$keyname) {
	    Sbuild::Exception::DB->throw
		(error => "No key specified",
		 usage => "key show <keyname>");
    }

    if (@_) {
	Sbuild::Exception::DB->throw
	    (error => "Only one key may be specified",
	     usage => "key show <keyname>");
    }

    my $key = $db->_find_key($keyname);
    if (!$key) {
	    Sbuild::Exception::DB->throw
		(error => "Key ‘$keyname’ not found");
    }

    print $key;
}

sub key_list {
    my $db = shift;
    my $keyname = shift;

    my $conn = $db->get('CONN');

    my $find = $conn->prepare("SELECT name FROM keys");
    $find->execute();
    while(my $ref = $find->fetchrow_hashref()) {
	print $ref->{'name'} . "\n";
    }
}

1;
