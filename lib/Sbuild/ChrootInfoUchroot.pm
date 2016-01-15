#
# ChrootInfo.pm: chroot utility library for sbuild
# Copyright © 2005-2009 Roger Leigh <rleigh@debian.org>
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

package Sbuild::ChrootInfoUchroot;

use Sbuild::ChrootInfo;
use Sbuild::ChrootUchroot;

use Dpkg::Index;

use strict;
use warnings;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::ChrootInfo);

    @EXPORT = qw();
}

sub new {
    my $class = shift;
    my $conf = shift;

    my $self = $class->SUPER::new($conf);
    bless($self, $class);

    return $self;
}

sub get_info {
    my $self = shift;
    my $chroot = shift;

    my $chroot_type = "";

    # If namespaces aren't supported, try to fall back to old style session.
	open CHROOT_DATA, '-|', $self->get_conf('UCHROOT'), '--info', '--chroot', $chroot or
	die 'Can\'t run ' . $self->get_conf('UCHROOT') . ' to get chroot data';

    my $control = Dpkg::Control->new();

    $control->parse(\*CHROOT_DATA, "uchroot --info --chroot $chroot");

    my ($namespace, $chrootname) = split /:/, $control->{Name};

    my %tmp = (
	'Namespace' => $namespace,
	'Name' => $chrootname,
	'Location' => $control->{Location}
    );

    close CHROOT_DATA or die "Can't close uchroot pipe getting chroot data";

    return \%tmp;
}

sub get_info_all {
    my $self = shift;

    my $chroots = {};
    my $build_dir = $self->get_conf('BUILD_DIR');

    local %ENV;

    $ENV{'LC_ALL'} = 'C';
    $ENV{'LANGUAGE'} = 'C';

    open CHROOTS, '-|', $self->get_conf('UCHROOT'), '--info'
	or die 'Can\'t run ' . $self->get_conf('UCHROOT');
    my $tmp = undef;

    my $key_func = sub { return $_[0]->{Name}; };

    my $index = Dpkg::Index->new(get_key_func=>$key_func);

    $index->parse(\*CHROOTS, "uchroot --info");

    foreach my $name ($index->get_keys()) {
	my $cdata = $index->get_by_key($name);

	my ($namespace, $chroot) = split /:/, $name;

	if (!exists($chroots->{$namespace})) {
	    $chroots->{$namespace} = {}
	}

	$chroots->{$namespace}->{$chroot} = 1;
	foreach my $alias (split /\s+/, $cdata->{Aliases}) {
	    next if ! $alias;
	    $chroots->{$namespace}->{$alias} = 1;
	}
    }

    close CHROOTS or die "Can't close uchroot pipe";

    $self->set('Chroots', $chroots);
}

sub _create {
    my $self = shift;
    my $chroot_id = shift;

    my $chroot = undef;

    if (defined($chroot_id)) {
	$chroot = Sbuild::ChrootUchroot->new($self->get('Config'), $chroot_id);
    }

    return $chroot;
}

1;
