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
use Text::CSV;
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
	     usage => "suite fetch <suitename>");
    }

    my $conn = $db->get('CONN');

    try eval {
	$conn->begin_work();

	print "Updating $suitename release:\n";
	STDOUT->flush;

	my ($uri, $distribution, $release_files) =
	    suite_fetch_release($db, $suitename);

	# Update Sources using Sources.bz2
	print "Updating $suitename sources:\n";
	my $src_detail = $conn->prepare("SELECT component, sha256 FROM suite_source_detail WHERE suitenick = ? AND build = true");
	$src_detail->bind_param(1, $suitename);
	$src_detail->execute();
	while (my $srcref = $src_detail->fetchrow_hashref()) {
	    suite_fetch_sources($db,
				SUITE => $suitename,
				URI => $uri,
				DISTRIBUTION => $distribution,
				FILES => $release_files,
				COMPONENT => $srcref->{'component'},
				SHA256 => $srcref->{'sha256'});
	}

	# Update Packages
	print "Updating $suitename packages:\n";
	my $pkg_detail = $conn->prepare("SELECT architecture,component,sha256 FROM suite_binary_detail WHERE suitenick = ? AND build = true");
	$pkg_detail->bind_param(1, $suitename);
	$pkg_detail->execute();
	while (my $pkgref = $pkg_detail->fetchrow_hashref()) {
	    suite_fetch_packages($db,
				 SUITE => $suitename,
				 URI => $uri,
				 DISTRIBUTION => $distribution,
				 FILES => $release_files,
				 COMPONENT => $pkgref->{'component'},
				 ARCHITECTURE => $pkgref->{'architecture'},
				 SHA256 => $pkgref->{'sha256'});
	}

	$conn->commit();
    };

    if (catch my $err) {
	$conn->rollback();
	$err->rethrow();
    }
}

sub suite_fetch_release {
    my $db = shift;
    my $suitename = shift;

    my $conn = $db->get('CONN');

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

    # Try to get InRelease, then fall back to Release and Release.gpg
    # if not available.
    try eval {
	$release = download_cached_distfile(URI => $uri,
					    FILE => { NAME => "InRelease"},
					    DIST => $distribution,
					    CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));
	print "  InRelease\n";
	STDOUT->flush;
	key_verify_file($db, $key, $release);
    };
    if (catch my $err) {
	print "InRelease not found; falling back to Release: $err\n";
	$release = download_cached_distfile(URI => $uri,
					    FILE => { NAME => "Release"},
					    DIST => $distribution,
					    CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));
	$releasegpg = download_cached_distfile(URI => $uri,
					       FILE => { NAME => "Release.gpg" },
					       DIST => $distribution,
					       CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));
	print "  Release\n";
	STDOUT->flush;
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

    # Check validity if Valid-Until was provided.
    if ($parserel->{'Valid-Until'}) {
	my $valid = $conn->prepare("SELECT validuntil > now() AS valid FROM suite_release WHERE (suitenick = ?)");
	$valid->bind_param(1, $suitename);
	$valid->execute();
	my $vref = $valid->fetchrow_hashref();
	if (!$vref->{'valid'}) {
	    Sbuild::Exception::DB->throw
		(error => "Invalid archive (out of date)");
	}
    }

    # Update source component mappings
    foreach my $component (split('\s+', $parserel->{'Components'})) {
	my $detail = $conn->prepare("SELECT merge_suite_source_detail(?,?)");
	$detail->bind_param(1, $suitename);
	$detail->bind_param(2, $component);
	$detail->execute();
    }
    # Update binary arch-component mappings
    foreach my $arch (split('\s+', $parserel->{'Architectures'})) {
	foreach my $component (split('\s+', $parserel->{'Components'})) {
	    my $detail = $conn->prepare("SELECT merge_suite_binary_detail(?,?,?)");
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
	    $files{$file} = { NAME=>$file, SHA256=>$hash, SIZE=>$size };
	}
    }

    return ($uri, $distribution, \%files);
}

sub suite_fetch_sources {
    my $db = shift;
    my %opts = @_;

    my $suitename = $opts{'SUITE'};
    my $files = $opts{'FILES'};
    my $component = $opts{'COMPONENT'};
    my $oldsha256 = $opts{'SHA256'};
    my $uri = $opts{'URI'};
    my $distribution = $opts{'DISTRIBUTION'};

    Sbuild::Exception::DB->throw
	(error => "suite_fetch_sources: Missing arguments")
	if (!$suitename || !$files || !$component ||
	    !$uri || !$distribution);

    my $conn = $db->get('CONN');


    print "  $component:";
    my $sfile = $files->{"$component/source/Sources"};
    my $bsfile = $files->{"$component/source/Sources.bz2"};
    if ($sfile && $bsfile) {
	print " download";
	STDOUT->flush;
	my $source = download_cached_distfile(URI => $uri,
					      FILE => $sfile,
					      BZ2FILE => $bsfile,
					      DIST => $distribution,
					      CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));

	if ($oldsha256 && $sfile->{'SHA256'} eq $oldsha256) {
	    if ($db->get_conf('FORCE')) {
		print " (already merged, force merge)";
	    } else {
		print " (already merged, skipping)\n";
		STDOUT->flush;
		return;
	    }
	}

	print " parse";
	STDOUT->flush;
	my $source_info = Dpkg::Index->new(type=>CTRL_INDEX_SRC);
	$source_info->load($source);

	print " import";
	STDOUT->flush;
	$conn->do("CREATE TEMPORARY TABLE new_sources (LIKE sources INCLUDING DEFAULTS)");
	$conn->do("CREATE TEMPORARY TABLE new_sources_architectures (LIKE source_package_architectures INCLUDING DEFAULTS)");

	# Cache prepared statements outside loop.
	my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
	$conn->do("COPY new_sources (source_package, source_version, component, section, priority, maintainer, uploaders, build_dep, build_dep_indep, build_confl, build_confl_indep, stdver) FROM STDIN CSV");

	foreach my $pkgname ($source_info->get_keys()) {
	    my $pkg = $source_info->get_by_key($pkgname);

	    $csv->combine($pkg->{'Package'},
			  $pkg->{'Version'},
			  $component,
			  $pkg->{'Section'},
			  $pkg->{'Priority'},
			  $pkg->{'Maintainer'},
			  $pkg->{'Uploaders'},
			  $pkg->{'Build-Depends'},
			  $pkg->{'Build-Depends-Indep'},
			  $pkg->{'Build-Conflicts'},
			  $pkg->{'Build-Conflicts-Indep'},
			  $pkg->{'Standards-Version'})
		or Sbuild::Exception::DB->throw
		(error => "Can't transform source ‘$pkg->{'Package'}_$pkg->{'Version'}’ to CSV",
		 detail => 'Input: '.$csv->error_input);

	    $conn->pg_putcopydata($csv->string);
	}
	$conn->pg_putcopyend();


	$conn->do("COPY new_sources_architectures (source_package, source_version, architecture) FROM STDIN CSV");

	foreach my $pkgname ($source_info->get_keys()) {
	    my $pkg = $source_info->get_by_key($pkgname);
	    # Update architectures
	    foreach my $arch (split('\s+', $pkg->{'Architecture'})) {
		next if (!$arch); # Skip blank line from split

		$csv->combine($pkg->{'Package'},
			      $pkg->{'Version'},
			      $arch)
		    or Sbuild::Exception::DB->throw
		    (error => "Can't transform source ‘$pkg->{'Package'}_$pkg->{'Version'}’ to CSV");
		    $conn->pg_putcopydata($csv->string);
	    }
	}
	$conn->pg_putcopyend();

	# Move into main table.
	print " merge";
	my $smerge = $conn->prepare("SELECT merge_sources(?,?,?)");
	$smerge->bind_param(1, $suitename);
	$smerge->bind_param(2, $component);
	$smerge->bind_param(3, $sfile->{'SHA256'});
	$smerge->execute();

	$conn->do("DROP TABLE new_sources");
	$conn->do("DROP TABLE new_sources_architectures");
	print ".\n";
	STDOUT->flush;
    }
}

sub suite_fetch_packages {
    my $db = shift;
    my %opts = @_;

    my $conn = $db->get('CONN');

    my $suitename = $opts{'SUITE'};
    my $files = $opts{'FILES'};
    my $component = $opts{'COMPONENT'};
    my $oldsha256 = $opts{'SHA256'};
    my $uri = $opts{'URI'};
    my $distribution = $opts{'DISTRIBUTION'};
    my $architecture = $opts{'ARCHITECTURE'};

    Sbuild::Exception::DB->throw
	(error => "suite_fetch_packages: Missing arguments")
	if (!$suitename || !$files || !$component ||
	    !$uri || !$distribution || !$architecture);

    print "  $component/$architecture:";
    my $sfile = $files->{"$component/binary-$architecture/Packages"};
    my $bsfile = $files->{"$component/binary-$architecture/Packages.bz2"};
    if ($sfile && $bsfile) {
	print " download";
	STDOUT->flush;
	my $packages = download_cached_distfile(URI => $uri,
						FILE => $sfile,
						BZ2FILE => $bsfile,
						DIST => $distribution,
						CACHEDIR => $db->get_conf('ARCHIVE_CACHE'));

	if ($oldsha256 && $sfile->{'SHA256'} eq $oldsha256) {
	    if ($db->get_conf('FORCE')) {
		print " (already merged, force merge)";
	    } else {
		print " (already merged, skipping)\n";
		STDOUT->flush;
		return;
	    }
	}

	print " parse";
	STDOUT->flush;
	my $binary_info = Dpkg::Index->new(type=>CTRL_INDEX_PKG);
	$binary_info->load($packages);

	print " import";
	STDOUT->flush;


	$conn->do("CREATE TEMPORARY TABLE new_binaries (LIKE binaries INCLUDING DEFAULTS)");

	my $csv = Text::CSV->new ({ binary => 1, eol => $/ });
	$conn->do("COPY new_binaries (binary_package, binary_version, architecture, source_package, source_version, section, type, priority, installed_size, multi_arch, essential, build_essential, pre_depends, depends, recommends, suggests, conflicts, breaks, enhances, replaces, provides) FROM STDIN CSV");

	foreach my $pkgname ($binary_info->get_keys()) {
	    my $pkg = $binary_info->get_by_key($pkgname);

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

	    $csv->combine($pkg->{'Package'},
			  $pkg->{'Version'},
			  $pkg->{'Architecture'},
			  $source,
			  $source_version,
			  $pkg->{'Section'},
			  'deb',
			  $pkg->{'Priority'},
			  $pkg->{'Installed-Size'},
			  $pkg->{'Multi-Arch'},
			  $pkg->{'Essential'},
			  $pkg->{'Build-Essential'},
			  $pkg->{'Pre-Depends'},
			  $pkg->{'Depends'},
			  $pkg->{'Recommends'},
			  $pkg->{'Suggests'},
			  $pkg->{'Conflicts'},
			  $pkg->{'Breaks'},
			  $pkg->{'Enhances'},
			  $pkg->{'Replaces'},
			  $pkg->{'Provides'})
		or Sbuild::Exception::DB->throw
		(error => "Can't transform source ‘$pkg->{'Package'}_$pkg->{'Version'}’ to CSV");
	    $conn->pg_putcopydata($csv->string);
	}
	$conn->pg_putcopyend();

	# Move into main table.
	print " merge";
	my $smerge = $conn->prepare("SELECT merge_binaries(?,?,?,?)");
	$smerge->bind_param(1, $suitename);
	$smerge->bind_param(2, $component);
	$smerge->bind_param(3, $architecture);
	$smerge->bind_param(4, $sfile->{'SHA256'});
	$smerge->execute();

	$conn->do("DROP TABLE new_binaries");

	print ".\n";
	STDOUT->flush;
    }
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
