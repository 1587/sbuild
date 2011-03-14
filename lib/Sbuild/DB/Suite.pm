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
use Dpkg::Control;
use Dpkg::Index;
use Dpkg::Control::Hash;
use File::Temp qw(tempdir);
use Sbuild::Exception;
use Sbuild::Base;
use Sbuild::DBUtil qw(uncompress escape_path download download_cached_distfile valid_changes);
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

    if (!$suitename) {
	Sbuild::Exception::DB->throw
	    (error => "No suite specified",
	     usage => "suite remove <suitename>");
    }

    my $conn = $db->get('CONN');

    try eval {
	$conn->begin_work();

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
	my $distribution = $ref->{'distribution'};
	my $uri = $ref->{'uri'};

	my $release;
	my $releasegpg;

	try eval {
	    $release = download_cached_distfile(URI => $uri,
						FILE => "InRelease",
						DIST => $distribution,
						CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));
	    key_verify_file($db, $key, $release);
	};
	if (catch my $err) {
	    print "InRelease not found; falling back to Release: $err\n";
	    $release = download_cached_distfile(URI => $uri,
						FILE => "Release",
						DIST => $distribution,
						CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));
	    $releasegpg = download_cached_distfile(URI => $uri,
						   FILE => "Release.gpg",
						   DIST => $distribution,
						   CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));
	    key_verify_file($db, $key, $releasegpg, $release);
	}

	# Release file successfully downloaded and validated.  Now import
	# details.
	my $parserel = Dpkg::Control::Hash->new(allow_pgp=>1);
	$parserel->load($release);

	my $insert = $conn->prepare("SELECT merge_release(?, ?, ?, ?, ?, ?, ?, ?)");
	$insert->bind_param(1, $suitename);
	$insert->bind_param(2, $parserel->{'Suite'});
	$insert->bind_param(3, $parserel->{'Codename'});
	$insert->bind_param(4, $parserel->{'Version'});
	$insert->bind_param(5, $parserel->{'Origin'});
	$insert->bind_param(6, $parserel->{'Label'});
	$insert->bind_param(7, $parserel->{'Date'});
	$insert->bind_param(8, $parserel->{'Valid-Until'});
	$insert->execute();

	# Check validity
	my $valid = $conn->prepare("SELECT validuntil > now() AS valid FROM suite_release WHERE (suitenick = ?)");
	$valid->bind_param(1, $suitename);
	$valid->execute();
	my $vref = $valid->fetchrow_hashref();
	if (!$vref->{'valid'}) {
	    Sbuild::Exception::DB->throw
		(error => "Invalid archive (out of date)");
	}

	# Update arch-component mappings
	foreach my $arch (split('\s+', $parserel->{'Architectures'})) {
	    foreach my $component (split('\s+', $parserel->{'Components'})) {
		my $detail = $conn->prepare("SELECT merge_suite_detail(?,?,?)");
		$detail->bind_param(1, $suitename);
		$detail->bind_param(2, $arch);
		$detail->bind_param(3, $component);
		$detail->execute();
	    }
	}

	# Sort out files
	my %files = ();
	{
	    foreach my $line (split("\n", $parserel->{'SHA256'})) {
		next if (!$line); # Skip blank line from split
		my ($hash, $size, $file) = split(/\s+/, $line);
		$files{$file} = { SHA256=>$hash, SIZE=>$size };
	    }
	}

	# Update Sources using Sources.bz2
	print "Updating $suitename sources:\n";
	foreach my $component (split('\s+', $parserel->{'Components'})) {
	    print "  $component:";
	    my $sfile = "$component/source/Sources.bz2";
	    if ($files{$sfile}) {
		print " download";
		STDOUT->flush;
		my $source = download_cached_distfile(URI => $uri,
						      FILE => $sfile,
						      DIST => $distribution,
						      CACHEDIR => $db->get_conf('ARCHIVE_CACHE'),
						      SHA256 => $files{$sfile}->{'SHA256'},
						      SIZE => $files{$sfile}->{'SIZE'});

		print " decompress";
		STDOUT->flush;
		my $z = new IO::Uncompress::AnyUncompress($source);
		if (!$z) {
		    Sbuild::Exception::DB->throw
			(error => "Can't open $source for decompression: $!");
		}
		my $source_info = Dpkg::Index->new(type=>CTRL_INDEX_SRC);
		$source_info->parse($z, $source);

		print " import";
		STDOUT->flush;
		foreach my $pkgname ($source_info->get_keys()) {
		    my $pkg = $source_info->get_by_key($pkgname);

		    my $msource = $conn->prepare("SELECT merge_source(?,?,?,?,?,?,?,?,?,?,?)");
		    $msource->bind_param(1, $pkg->{'Package'});
		    $msource->bind_param(2, $pkg->{'Version'});
		    $msource->bind_param(3, $component);
		    $msource->bind_param(4, $pkg->{'Section'});
		    $msource->bind_param(5, $pkg->{'Priority'});
		    $msource->bind_param(6, $pkg->{'Maintainer'});
		    $msource->bind_param(7, $pkg->{'Build-Depends'});
		    $msource->bind_param(8, $pkg->{'Build-Depends-Indep'});
		    $msource->bind_param(9, $pkg->{'Build-Conflicts'});
		    $msource->bind_param(10, $pkg->{'Build-Conflicts-Indep'});
		    $msource->bind_param(11, $pkg->{'Standards-Version'});
		    $msource->execute();
		}
		print ".\n";
		STDOUT->flush;
	    }
	}

	# Update Packages
	print "Updating $suitename packages:\n";
	my $pkg_detail = $conn->prepare("SELECT architecture,component FROM suite_detail WHERE suitenick = ? AND build = true");
	$pkg_detail->bind_param(1, $suitename);
	$pkg_detail->execute();
	while (my $pkgref = $pkg_detail->fetchrow_hashref()) {
	    my $component = $pkgref->{'component'};
	    my $architecture = $pkgref->{'architecture'};
	    print "  $component/$architecture:";
	    my $sfile = "$component/binary-$architecture/Packages.bz2";
	    if ($files{$sfile}) {
		print " download";
		STDOUT->flush;
		my $packages = download_cached_distfile(URI => $uri,
							FILE => $sfile,
							DIST => $distribution,
							CACHEDIR => $db->get_conf('ARCHIVE_CACHE'),
							SHA256 => $files{$sfile}->{'SHA256'},
							SIZE => $files{$sfile}->{'SIZE'});

		print " decompress";
		STDOUT->flush;
		my $z = new IO::Uncompress::AnyUncompress($packages);
		if (!$z) {
		    Sbuild::Exception::DB->throw
			(error => "Can't open $packages for decompression: $!");
		}
		my $packages_info = Dpkg::Index->new(type=>CTRL_INDEX_PKG);
		$packages_info->parse($z, $packages);

		print " import";
		STDOUT->flush;
		foreach my $pkgname ($packages_info->get_keys()) {
		    my $pkg = $packages_info->get_by_key($pkgname);

		    my $source = $pkg->{'Package'};
		    my $source_version = $pkg->{'Version'};
		    my $source_detail = $pkg->{'Source'};
		    if ($source_detail) {
			my $match = ($source_detail =~ m/(\S+)\s?(?:\((\S+\)))?/);
			if (!$match) {
			    Sbuild::Exception::DB->throw
				(error => "Can't parse Source field ‘$source_detail’");
			}
			$source = $1;
			if ($2) {
			    $source_version = $2;
			}
		    }

		    my $mpackages = $conn->prepare("SELECT merge_binary(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
		    $mpackages->bind_param(1, $pkg->{'Package'});
		    $mpackages->bind_param(2, $pkg->{'Version'});
		    $mpackages->bind_param(3, $pkg->{'Architecture'});
		    $mpackages->bind_param(4, $source);
		    $mpackages->bind_param(5, $source_version);
		    $mpackages->bind_param(6, $pkg->{'Section'});
		    $mpackages->bind_param(7, 'deb');
		    $mpackages->bind_param(8, $pkg->{'Priority'});
		    $mpackages->bind_param(9, $pkg->{'Installed-Size'});
		    $mpackages->bind_param(10, $pkg->{'Multi-Arch'});
		    $mpackages->bind_param(11, $pkg->{'Essential'});
		    $mpackages->bind_param(12, $pkg->{'Build-Essential'});
		    $mpackages->bind_param(13, $pkg->{'Pre-Depends'});
		    $mpackages->bind_param(14, $pkg->{'Depends'});
		    $mpackages->bind_param(15, $pkg->{'Recommends'});
		    $mpackages->bind_param(16, $pkg->{'Suggests'});
		    $mpackages->bind_param(17, $pkg->{'Conflicts'});
		    $mpackages->bind_param(18, $pkg->{'Breaks'});
		    $mpackages->bind_param(19, $pkg->{'Enhances'});
		    $mpackages->bind_param(20, $pkg->{'Replaces'});
		    $mpackages->bind_param(21, $pkg->{'Provides'});
		    $mpackages->execute();
		}
		print ".\n";
		STDOUT->flush;
	    }


	}


	$conn->commit();
    };

    if (catch my $err) {
	$conn->rollback();
	$err->rethrow();
    }

    # Update Packages
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
