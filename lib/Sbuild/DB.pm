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
use Sbuild::DBUtil qw(valid_changes);
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

    my $dbname = $self->get_conf('DBNAME');
    my $dbuser = $self->get_conf('DBUSER');
    my $dbpassword = $self->get_conf('DBPASSWORD');
    my $conn = DBI->connect("DBI:Pg:dbname=$dbname",$dbuser,$dbpassword);
    if (!$conn) {
	Sbuild::Exception::DB->throw
	    (error => "Can't connect to database ‘$dbname’ as user ‘$dbuser’")
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
	Sbuild::Exception::DB->throw
	    (error => "Error running gpg --list-keys: $?",
	     info => "Are the specified keys present in the keyring?");
    }

    open(my $fh, '-|', 'gpg', @keyring_opts, '--export', '--armor', @keys)
	or die 'Can\'t open pipe to gpg';
    binmode($fh,":raw");
    my $gpgkey = do { local $/; <$fh> };
    if (!$fh->close()) {
	Sbuild::Exception::DB->throw
	    (error => "Error closing gpg pipe: $?");
    }

    return $gpgkey;
}

sub key_add {
    my $self = shift;
    my $keyname = shift;
    my @keys = @_;

    my $conn = $self->get('CONN');

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

    my $file = $self->fetch_gpg_key(@keys);
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
    my $self = shift;
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

    my $conn = $self->get('CONN');

    my $find = $conn->prepare("SELECT name FROM keys WHERE (name = ?)");
    $find->bind_param(1, $keyname);
    $find->execute();
    my $rows = $find->rows();
    if (!$rows) {
	Sbuild::Exception::DB->throw
	    (error => "Key ‘$keyname’ does not exist");
    }

    my $file = $self->fetch_gpg_key(@keys);
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
    my $self = shift;
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
	Sbuild::Exception::DB->throw
	    (error => "No key specified",
	     usage => "key verify <keyname> <filename> [<detachedsig>]");
    }

    if (!@filenames) {
	Sbuild::Exception::DB->throw
	    (error => "No file specified",
	     usage => "key verify <keyname> <filename> [<detachedsig>]");
    }

    my $key = $self->_find_key($keyname);
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
	    Sbuild::Exception::DB->throw
		(error => "Key ‘$keyname’ not found");
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
	    Sbuild::Exception::DB->throw
		(error => "No key specified",
		 usage => "key show <keyname>");
    }

    if (@_) {
	Sbuild::Exception::DB->throw
	    (error => "Only one key may be specified",
	     usage => "key show <keyname>");
    }

    my $key = $self->_find_key($keyname);
    if (!$key) {
	    Sbuild::Exception::DB->throw
		(error => "Key ‘$keyname’ not found");
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
