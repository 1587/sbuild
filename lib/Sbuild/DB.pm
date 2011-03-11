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
use Sbuild::Base;

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

    my $dbname = $self->get_conf('DBNAME');
    my $dbuser = $self->get_conf('DBUSER');
    my $dbpassword = $self->get_conf('DBPASSWORD');
    my $conn = DBI->connect("DBI:Pg:dbname=$dbname",$dbuser,$dbpassword);
    if (!$conn) {
	print STDERR "Can't connect to database '$dbname' as user '$dbuser'";
	$self = undef;
    }
    $self->set('CONN', $conn);

    return $self;
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
	print STDERR "Error running gpg --list-keys: $?\n";
	print STDERR "Are the specified keys present in the keyring?\n";
	exit 1;
    }

    open(my $fh, '-|', 'gpg', @keyring_opts, '--export', '--armor', @keys)
	or die 'Can\'t open pipe to gpg';
    binmode($fh,":raw");
    my $file = do { local $/; <$fh> };
    if (!$fh->close()) {
	print STDERR "Error closing gpg pipe: $?\n";
	exit 1;
    }

    return $file;
}

sub key_add {
    my $self = shift;
    my $keyname = shift;
    my @keys = @_;

    my $conn = $self->get('CONN');

    if (!$keyname) {
	print STDERR "No keyname specified\n";
	print STDERR "Usage: sbuild-db key add <keyname> <keyid1> [<keyid>]\n";
	exit 1;
    }

    if (@keys < 1) {
	print STDERR "No keyid specified.\n";
	print STDERR "Usage: sbuild-db key add <keyname> <keyid1> [<keyid>]\n";
	exit 1;
    }

    my $find = $conn->prepare("SELECT name FROM keys WHERE (name = ?)");
    $find->bind_param(1, $keyname);
    $find->execute();
    my $rows = $find->rows();
    if ($rows) {
	print STDERR "Key $keyname already exists\n";
	exit 1;
    }

    my $file = $self->fetch_gpg_key(@keys);
    die "Failed to get gpg key" if !$file;

    my $insert = $conn->prepare("INSERT INTO keys (name, key) VALUES (?, ?)");
    $insert->bind_param(1, $keyname);
    $insert->bind_param(2, $file, { pg_type=>DBD::Pg::PG_BYTEA });
    $rows = $insert->execute();
    print "Inserted $rows row(s)\n";
}

sub key_update {
    my $self = shift;
    my $keyname = shift;
    my @keys = @_;

    if (!$keyname) {
	print STDERR "No keyname specified\n";
	print STDERR "Usage: sbuild-db key update <keyname> <keyid1> [<keyid>]\n";
	exit 1;
    }

    if (@keys < 1) {
	print STDERR "No keyid specified.\n";
	print STDERR "Usage: sbuild-db key update <keyname> <keyid1> [<keyid>]\n";
	exit 1;
    }

    my $conn = $self->get('CONN');

    my $find = $conn->prepare("SELECT name FROM keys WHERE (name = ?)");
    $find->bind_param(1, $keyname);
    $find->execute();
    my $rows = $find->rows();
    if (!$rows) {
	print STDERR "Key $keyname does not exist\n";
	exit 1;
    }

    my $file = $self->fetch_gpg_key(@keys);
    die "Failed to get gpg key" if !$file;

    my $update = $conn->prepare("UPDATE keys SET key = ? WHERE (name = ?)");
    $update->bind_param(1, $file, { pg_type=>DBD::Pg::PG_BYTEA });
    $update->bind_param(2, $keyname);
    $rows = $update->execute();
    print "Updated $rows row(s)\n";
}

sub key_remove {
    my $self = shift;
    my $keyname = shift;

    if (!$keyname) {
	print STDERR "No key specified\n";
	print STDERR "Usage: sbuild-db key remove <keyname>\n";
	exit 1;
    }

    if (@_) {
	print STDERR "Only one key may be specified.\n";
	print STDERR "Usage: sbuild-db key remove <keyname>\n";
	exit 1;
    }

    my $conn = $self->get('CONN');

    my $delete = $conn->prepare("DELETE FROM keys WHERE (name = ?)");
    $delete->bind_param(1, $keyname);
    my $rows = $delete->execute();
    print "Deleted $rows row(s)\n";
}

sub key_verify_file {
    my $self = shift;
    my $keyname = shift;
    my @filenames = shift;

    if (!$keyname) {
	print STDERR "No key specified\n";
	print STDERR "Usage: sbuild-db verify <keyname> <filename>\n";
    }

    if (!@filenames) {
	print STDERR "No file specified\n";
	print STDERR "Usage: sbuild-db verify <keyname> <filename> [<detachedsig>]\n";
    }

    my $key = $self->_find_key($keyname);
    if (!$key) {
	print STDERR "Key $keyname not found\n";
	exit 1;
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
	print STDERR "Error closing gpg pipe: $?\n";
	exit 1;
    }

    my $status = system('gpgv', '--keyring', "$tempdir/pubring.gpg", @filenames);
    if ($status) {
	print STDERR "Error verifying signature on $filenames[0]: $?\n";
	exit 1;
    }
}

sub _find_key {
    my $self = shift;
    my $keyname = shift;

    my $key = undef;
    if ($keyname) {
	my $conn = $self->get('CONN');

	my $find = $conn->prepare("SELECT key FROM keys WHERE (name = ?)");
	$find->bind_param(1, $keyname);
	$find->execute();
	my $rows = $find->rows();
	if (!$rows) {
	    print STDERR "Key $keyname not found\n";
	    exit 1;
	}

	my $ref = $find->fetchrow_hashref();
	$key = $ref->{'key'};
    }

    return $key;
}

sub key_show {
    my $self = shift;
    my $keyname = shift;

    if (!$keyname) {
	print STDERR "No key specified\n";
	print STDERR "Usage: sbuild-db key show <keyname>\n";
    }

    my $key = $self->_find_key($keyname);
    if (!$key) {
	print STDERR "Key $keyname not found\n";
	exit 1;
    }

    print $key;
}

sub key_list {
    my $self = shift;
    my $keyname = shift;

    my $conn = $self->get('CONN');

    my $find = $conn->prepare("SELECT name FROM keys");
    $find->execute();
    while(my $ref = $find->fetchrow_hashref()) {
	print $ref->{'name'} . "\n";
    }
}

1;
