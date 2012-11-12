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

package Sbuild::DB::Action::Key;

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

    @EXPORT = qw(actions key_add key_update key_remove key_verify_file
                 key_show key_list);
}

sub actions {
    return { "key" =>
	     { "add" => \&key_add,
	       "update" => \&key_update,
	       "remove" => \&key_remove,
	       "list" => \&key_list,
	       "show" => \&key_show,
	       "verify" => \&key_verify_file,
	       "__default" => \&key_list }
    };
}

sub fetch_gpg_key {
    my $self = shift;
    my @keys = @_;

    if (@keys < 1) {
	return undef;
    }

    print "Fetching " .  join(", ", @keys) . "\n";

    my @keyring_opts = ();
    if ($self->get_conf('GPG_KEYRING')) {
	@keyring_opts = ('--no-default-keyring', '--keyring', $self->get_conf('GPG_KEYRING'));
    }

    my $status = system('gpg', @keyring_opts, '--list-keys', @keys);
    if ($status) {
	Sbuild::Exception::DB->throw
	    (error => "Error running gpg --list-keys: $?",
	     info => "Are the specified keys present in the keyring?");
    }

    open(my $fh, '-|', 'gpg', @keyring_opts, '--export', '--armor', @keys)
	or Sbuild::Exception::DB->throw
	(error => "Can't open pipe to gpg");
    binmode($fh,":raw");
    my $gpgkey = do { local $/; <$fh> };
    if (!$fh->close()) {
	Sbuild::Exception::DB->throw
	    (error => "Error closing gpg pipe: $?");
    }

    return $gpgkey;
}

sub key_add {
    my $db = shift;
    my $keyname = shift;
    my @keys = @_;

    my $conn = $db->connect();

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

    my $file = fetch_gpg_key($db, @keys);
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

    my $conn = $db->connect();

    my $find = $conn->prepare("SELECT name FROM keys WHERE (name = ?)");
    $find->bind_param(1, $keyname);
    $find->execute();
    my $rows = $find->rows();
    if (!$rows) {
	Sbuild::Exception::DB->throw
	    (error => "Key ‘$keyname’ does not exist");
    }

    my $keydata = fetch_gpg_key($db, @keys);
    if (!$keydata) {
	Sbuild::Exception::DB->throw
	    (error => "Failed to get gpg key");
    }

    my $update = $conn->prepare("UPDATE keys SET key = ? WHERE (name = ?)");
    $update->bind_param(1, $keydata, { pg_type=>DBD::Pg::PG_BYTEA });
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

    my $conn = $db->connect();

    my $delete = $conn->prepare("DELETE FROM keys WHERE (name = ?)");
    $delete->bind_param(1, $keyname);
    my $rows = $delete->execute();
    print "Deleted $rows row(s)\n";
}

sub key_verify_file {
    my $db = shift;
    my $keyname = shift;
    my @filenames = @_;

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

    my $key = _find_key($db, $keyname);
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
    open(my $fh, '|-', 'gpg', '--quiet', '--import')
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
	my $conn = $db->connect();

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

    my $key = _find_key($db, $keyname);
    if (!$key) {
	    Sbuild::Exception::DB->throw
		(error => "Key ‘$keyname’ not found");
    }

    print $key;
}

sub key_list {
    my $db = shift;
    my $keyname = shift;

    my $conn = $db->connect();

    my $find = $conn->prepare("SELECT name FROM keys");
    $find->execute();
    while(my $ref = $find->fetchrow_hashref()) {
	print $ref->{'name'} . "\n";
    }
}

1;