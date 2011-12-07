# Copyright © 2009 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Sbuild::Control::Changelog;

use strict;
use warnings;

our $VERSION = "1.00";

use Sbuild::Control;
use base 'Sbuild::Control';

=encoding utf8

=head1 NAME

Sbuild::Control::Changelog - represent info fields output by dpkg-parsechangelog

=head1 DESCRIPTION

This object derives directly from Sbuild::Control with the type
CTRL_CHANGELOG.

=head1 FUNCTIONS

=over 4

=item $c = Sbuild::Control::Changelog->new()

Create a new empty set of changelog related fields.

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = Sbuild::Control->new(type => CTRL_CHANGELOG, @_);
    return bless $self, $class;
}

=back

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>.

=cut

1;
