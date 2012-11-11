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
use Sbuild qw(debug);
use Sbuild::Exception;
use Sbuild::Base;
use Exception::Class::TryCatch;
use Module::Pluggable search_path => ['Sbuild::DB'], instantiate => 'new';

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw(run_command list_commands);
}

my %actions = ();

sub new {
    my $class = shift;
    my $conf = shift;

    my $self = $class->SUPER::new($conf);
    bless($self, $class);

    # Register actions
    foreach my $p ($self->plugins()) {
	debug("Found plugin: $p");
	my $action = $p->actions();
	@actions{keys %{$action}} = values %{$action};
    }

    return $self;
}

sub connect() {
    my $self = shift;
    my $super = shift;
    $super = 0 if !defined($super);

    if (defined($self->get('CONN'))) {
	return $self->get('CONN');
    }

    my $dbservice = $self->get_conf('DBSERVICE');
    my ($dbuser, $dbpassword);
    if ($super) {
	$dbuser = $self->get_conf('DBSUPERUSER');
	$dbpassword = $self->get_conf('DBSUPERPASSWORD');
    } else {
	$dbuser = $self->get_conf('DBUSER');
	$dbpassword = $self->get_conf('DBPASSWORD');
    }
    my $conn = DBI->connect("DBI:Pg:service=$dbservice",$dbuser,$dbpassword,
	{RaiseError => 1});
    if (!$conn) {
	Sbuild::Exception::DB->throw
	    (error => "Can't connect to database service ‘$dbservice’ as user ‘$dbuser’");
    }
    $self->set('CONN', $conn);
    return $conn;
}

sub disconnect() {
    my $self = shift;
    my $conn = $self->get('CONN');
    if (!defined($conn)) {
	return
    }
    $conn->disconnect();
    $self->set('CONN', undef);
}

sub run_command {
    my $self = shift;
    my $context = [];

    $self->__run_command(\%actions, $context, @_);
}

sub __run_command {
    my $self = shift;
    my $actions = shift;
    my $context = shift;
    my $command = shift;
    if (!defined($command)) {
	$command = '__default';
    }

    push(@$context, $command);

    if (exists ${actions}->{"$command"}) {
	my $action = ${actions}->{$command};
	if (ref($action) eq 'HASH') {
	    $self->__run_command($action, $context, @_);
	} else {
	    $action->($self, @_);
	}
    } else {
	pop(@$context) if $command eq "__default";
	my $used = join(' ', @{$context});
	pop(@$context) if $command ne "__default";
	my $context = join(' ', @$context);
	my @commands = ();
	foreach my $cmd (keys{%{$actions}}) {
	    push (@commands, $cmd) if $cmd ne '__default';
	}
	@commands = sort(@commands);
	my @msg = ();
	if ($context) {
	    push(@msg, $context);
	}
	push(@msg, '{', join(' | ', @commands), '}');
	my $error = "‘$used’ is not an sbuild-db command";
	$error = "$used has no default action" if $command eq "__default";
	Sbuild::Exception::DB->throw
	    (error => $error,
	     usage => join(' ', @msg));
    }
}

sub list_commands {
    my $self = shift;
    my $context = [];
    my $pad = 0;

    print STDERR "Available commands:\n\n";
    $self->__list_commands(\%actions, \$pad);
}

sub __list_commands {
    my $self = shift;
    my $actions = shift;
    my $pad = shift;

    my $first = 1;
    foreach my $command (sort keys{%{$actions}}) {
	if ($command eq '__default') {
	    next;
	}
	if ($first && $$pad) {
	    print STDERR ' ';
	    $first = 0;
	} else {
	    print STDERR ' ' x ($$pad);
	}
	$$pad += length($command) + 1;
	my $action = ${actions}->{$command};
	print STDERR $command;
	if (ref($action) eq 'HASH') {
	    $self->__list_commands($action, $pad);
	} else {
	    print STDERR "\n";
	}
	$$pad -= length($command) + 1;
    }
}

1;
