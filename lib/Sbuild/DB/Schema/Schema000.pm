#
# Copyright © 2008-2012 Roger Leigh <rleigh@debian.org> Copyright ©
# 2008-2009 Marc 'HE' Brockschmidt <he@debian.org> Copyright ©
# 2008-2009 Adeodato Simó <adeodato@debian.org>
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

package Sbuild::DB::Schema::Schema000;

use strict;
use warnings;

use DBI;
use DBD::Pg;
use Sbuild::Exception;
use Sbuild::DBUtil qw();
use Exception::Class::TryCatch;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter Sbuild::Base);

    @EXPORT = qw(sversion upgrade);
}

sub sversion {
    return 0;
}

sub upgrade {
    my $self = shift;
    my $db = shift;

    my $conn = $db->connect(1);

    $conn->begin_work();

    my $ulist = $conn->prepare("SELECT rolname from pg_roles WHERE rolname = 'sbuild-adm'");
    my $admuser = $ulist->execute();
    if ($admuser == 1) {
	print STDOUT "User sbuild-adm already exists\n";
    } else {
	print STDOUT "Creating admin user sbuild-adm\n";
	$conn->do("CREATE ROLE \"sbuild-adm\" NOLOGIN;")
    }

    $conn->do("CREATE OR REPLACE LANGUAGE plpgsql");
    $conn->do("CREATE EXTENSION IF NOT EXISTS debversion");

    $conn->do("SET search_path = public");

    $conn->do("CREATE TABLE schema (
               version integer
                 CONSTRAINT schema_pkey PRIMARY KEY,
               description text NOT NULL
             )");

    $conn->do("COMMENT ON TABLE schema IS 'Schema revision history'");
    $conn->do("COMMENT ON COLUMN schema.version IS 'Schema version'");
    $conn->do("COMMENT ON COLUMN schema.description IS 'Schema change description'");

    $conn->do(<<'EOS');
CREATE TABLE keys (
       name text CONSTRAINT keys_pkey PRIMARY KEY,
       key bytea NOT NULL
)
EOS

    $conn->do("COMMENT ON TABLE keys IS 'GPG keys used to sign Release files'");
    $conn->do("COMMENT ON COLUMN keys.name IS 'Name used to reference a key'");
    $conn->do("COMMENT ON COLUMN keys.key IS 'GPG key as exported ASCII armoured text'");

    $conn->do(<<'EOS');
CREATE TABLE suites (
	suitenick text CONSTRAINT suites_pkey PRIMARY KEY,
	key text NOT NULL
	  CONSTRAINT suites_key_fkey REFERENCES keys(name),
	uri text NOT NULL,
	distribution text NOT NULL
)
EOS

    $conn->do("COMMENT ON TABLE suites IS 'Valid suites'");
    $conn->do("COMMENT ON COLUMN suites.suitenick IS 'Name used to reference a suite (nickname)'");
    $conn->do("COMMENT ON COLUMN suites.key IS 'GPG key name for validation'");
    $conn->do("COMMENT ON COLUMN suites.uri IS 'URI to fetch from'");
    $conn->do("COMMENT ON COLUMN suites.distribution IS 'Distribution name (used in combination with URI)'");

    $conn->do(<<'EOS');
CREATE TABLE suite_release (
        suitenick text
          UNIQUE NOT NULL
	  CONSTRAINT suite_release_suitenick_fkey
	  REFERENCES suites(suitenick)
	    ON DELETE CASCADE,
	fetched timestamp with time zone
	  NOT NULL,
	suite text NOT NULL,
	codename text NOT NULL,
	version debversion,
	origin text NOT NULL,
	label text NOT NULL,
	date timestamp with time zone NOT NULL,
	validuntil timestamp with time zone, -- old suites do not support it
        -- Old wanna-build options
	priority integer
	  NOT NULL
	  DEFAULT 10,
	depwait boolean
	  NOT NULL
	  DEFAULT 't',
	hidden boolean
	  NOT NULL
	  DEFAULT 'f'
)
EOS

    $conn->do("COMMENT ON TABLE suite_release IS 'Suite release details'");
    $conn->do("COMMENT ON COLUMN suite_release.suitenick IS 'Suite name (nickname)'");
    $conn->do("COMMENT ON COLUMN suite_release.fetched IS 'Date on which the Release file was fetched from the archive'");
    $conn->do("COMMENT ON COLUMN suite_release.suite IS 'Suite name'");
    $conn->do("COMMENT ON COLUMN suite_release.codename IS 'Suite codename'");
    $conn->do("COMMENT ON COLUMN suite_release.version IS 'Suite release version (if applicable)'");
    $conn->do("COMMENT ON COLUMN suite_release.origin IS 'Suite origin'");
    $conn->do("COMMENT ON COLUMN suite_release.label IS 'Suite label'");
    $conn->do("COMMENT ON COLUMN suite_release.date IS 'Date on which the Release file was generated'");
    $conn->do("COMMENT ON COLUMN suite_release.validuntil IS 'Date after which the data expires'");
    $conn->do("COMMENT ON COLUMN suite_release.priority IS 'Sorting order (lower is higher priority)'");
    $conn->do("COMMENT ON COLUMN suite_release.depwait IS 'Automatically wait on dependencies?'");
    $conn->do("COMMENT ON COLUMN suite_release.hidden IS 'Hide suite from public view?  (e.g. for -security)'");


    $conn->do(<<'EOS');
CREATE TABLE architectures (
	architecture text
	  CONSTRAINT arch_pkey PRIMARY KEY
)
EOS

    $conn->do("COMMENT ON TABLE architectures IS 'Architectures in use'");
    $conn->do("COMMENT ON COLUMN architectures.architecture IS 'Architecture name'");


    $conn->do(<<'EOS');
CREATE TABLE components (
	component text
	  CONSTRAINT components_pkey PRIMARY KEY
)
EOS

    $conn->do("COMMENT ON TABLE components IS 'Archive components in use'");
    $conn->do("COMMENT ON COLUMN components.component IS 'Component name'");


    $conn->do(<<'EOS');
CREATE TABLE suite_architectures (
	suitenick text
	  NOT NULL
	  CONSTRAINT suite_arch_suite_fkey
	  REFERENCES suites(suitenick)
	    ON DELETE CASCADE,
	architecture text
	  NOT NULL
	  CONSTRAINT suite_arch_architecture_fkey
	    REFERENCES architectures(architecture),
	CONSTRAINT suite_arch_pkey
	  PRIMARY KEY (suitenick, architecture)
)
EOS

    $conn->do("COMMENT ON TABLE suite_architectures IS 'Archive components in use by suite'");
    $conn->do("COMMENT ON COLUMN suite_architectures.suitenick IS 'Suite name (nickname)'");
    $conn->do("COMMENT ON COLUMN suite_architectures.architecture IS 'Architecture name'");


    $conn->do(<<'EOS');
CREATE TABLE suite_components (
	suitenick text
	  NOT NULL
	  CONSTRAINT suite_components_suite_fkey
	  REFERENCES suites(suitenick)
	    ON DELETE CASCADE,
	component text
	  NOT NULL
	  CONSTRAINT suite_components_component_fkey
	    REFERENCES components(component),
	CONSTRAINT suite_components_pkey
	  PRIMARY KEY (suitenick, component)
)
EOS

    $conn->do("COMMENT ON TABLE suite_components IS 'Archive components in use by suite'");
    $conn->do("COMMENT ON COLUMN suite_components.suitenick IS 'Suite name (nickname)'");
    $conn->do("COMMENT ON COLUMN suite_components.component IS 'Component name'");


    $conn->do(<<'EOS');
CREATE TABLE suite_source_detail (
	suitenick text
	  NOT NULL,
	component text
	  NOT NULL,
	build bool
	  NOT NULL
	  DEFAULT true,
	sha256 text,
	CONSTRAINT suite_source_detail_pkey
	  PRIMARY KEY (suitenick, component),
	CONSTRAINT suite_source_detail_suitecomponent_fkey
          FOREIGN KEY (suitenick, component)
	  REFERENCES suite_components (suitenick, component)
)
EOS

    $conn->do("COMMENT ON TABLE suite_source_detail IS 'List of architectures in each suite'");
    $conn->do("COMMENT ON COLUMN suite_source_detail.suitenick IS 'Suite name (nickname)'");
    $conn->do("COMMENT ON COLUMN suite_source_detail.component IS 'Component name'");
    $conn->do("COMMENT ON COLUMN suite_source_detail.build IS 'Fetch sources from this suite/component?'");
    $conn->do("COMMENT ON COLUMN suite_source_detail.sha256 IS 'SHA256 of latest Sources merge'");


    $conn->do(<<'EOS');
CREATE TABLE suite_binary_detail (
	suitenick text
	  NOT NULL,
	architecture text
	  NOT NULL,
	component text
	  NOT NULL,
	build bool
	  NOT NULL
	  DEFAULT false,
	sha256 text,
	CONSTRAINT suite_binary_detail_pkey
	  PRIMARY KEY (suitenick, architecture, component),
	CONSTRAINT suite_binary_detail_arch_fkey FOREIGN KEY (suitenick, architecture)
	  REFERENCES suite_architectures (suitenick, architecture),
	CONSTRAINT suite_binary_detail_component_fkey FOREIGN KEY (suitenick, component)
	  REFERENCES suite_components (suitenick, component)
)
EOS

    $conn->do("COMMENT ON TABLE suite_binary_detail IS 'List of architectures in each suite'");
    $conn->do("COMMENT ON COLUMN suite_binary_detail.suitenick IS 'Suite name (nickname)'");
    $conn->do("COMMENT ON COLUMN suite_binary_detail.architecture IS 'Architecture name'");
    $conn->do("COMMENT ON COLUMN suite_binary_detail.component IS 'Component name'");
    $conn->do("COMMENT ON COLUMN suite_binary_detail.build IS 'Build packages from this suite/architecture/component?'");
    $conn->do("COMMENT ON COLUMN suite_binary_detail.sha256 IS 'SHA256 of latest Packages merge'");


    $conn->do(<<'EOS');
CREATE TABLE package_types (
	type text
	  CONSTRAINT pkg_tpe_pkey PRIMARY KEY
)
EOS

    $conn->do("COMMENT ON TABLE package_types IS 'Valid types for binary packages'");
    $conn->do("COMMENT ON COLUMN package_types.type IS 'Type name'");


    $conn->do(<<'EOS');
CREATE TABLE binary_architectures (
	architecture text
	  CONSTRAINT binary_arch_pkey PRIMARY KEY
)
EOS

    $conn->do("COMMENT ON TABLE binary_architectures IS 'Possible values for the Architecture field in binary packages'");
    $conn->do("COMMENT ON COLUMN binary_architectures.architecture IS 'Architecture name'");


    $conn->do(<<'EOS');
CREATE TABLE package_priorities (
	priority text
	  CONSTRAINT pkg_priority_pkey PRIMARY KEY,
	priority_value integer
	  DEFAULT 0
)
EOS

    $conn->do("COMMENT ON TABLE package_priorities IS 'Valid package priorities'");
    $conn->do("COMMENT ON COLUMN package_priorities.priority IS 'Priority name'");
    $conn->do("COMMENT ON COLUMN package_priorities.priority_value IS 'Integer value for sorting priorities'");


    $conn->do(<<'EOS');
CREATE TABLE package_sections (
        section text
          CONSTRAINT pkg_sect_pkey PRIMARY KEY
)
EOS

    $conn->do("COMMENT ON TABLE package_sections IS 'Valid package sections'");
    $conn->do("COMMENT ON COLUMN package_sections.section IS 'Section name'");


    $conn->do(<<'EOS');
CREATE TABLE sources (
	source_package text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	component text
	  CONSTRAINT source_comp_fkey REFERENCES components(component)
	  NOT NULL,
	section text
	  CONSTRAINT source_section_fkey REFERENCES package_sections(section)
	  NOT NULL,
	priority text
	  CONSTRAINT source_priority_fkey REFERENCES package_priorities(priority),
	maintainer text NOT NULL,
	uploaders text,
	build_dep text,
	build_dep_indep text,
	build_confl text,
	build_confl_indep text,
	stdver text,
	CONSTRAINT sources_pkey PRIMARY KEY (source_package, source_version)
)
EOS

    $conn->do("CREATE INDEX sources_pkg_idx ON sources (source_package)");

    $conn->do("COMMENT ON TABLE sources IS 'Source packages common to all architectures (from Sources)'");
    $conn->do("COMMENT ON COLUMN sources.source_package IS 'Package name'");
    $conn->do("COMMENT ON COLUMN sources.source_version IS 'Package version number'");
    $conn->do("COMMENT ON COLUMN sources.component IS 'Archive component'");
    $conn->do("COMMENT ON COLUMN sources.section IS 'Package section'");
    $conn->do("COMMENT ON COLUMN sources.priority IS 'Package priority'");
    $conn->do("COMMENT ON COLUMN sources.maintainer IS 'Package maintainer'");
    $conn->do("COMMENT ON COLUMN sources.maintainer IS 'Package uploaders'");
    $conn->do("COMMENT ON COLUMN sources.build_dep IS 'Package build dependencies (architecture dependent)'");
    $conn->do("COMMENT ON COLUMN sources.build_dep_indep IS 'Package build dependencies (architecture independent)'");
    $conn->do("COMMENT ON COLUMN sources.build_confl IS 'Package build conflicts (architecture dependent)'");
    $conn->do("COMMENT ON COLUMN sources.build_confl_indep IS 'Package build conflicts (architecture independent)'");
    $conn->do("COMMENT ON COLUMN sources.stdver IS 'Debian Standards (policy) version number'");


    $conn->do(<<'EOS');
CREATE TABLE source_architectures (
	architecture text
	  CONSTRAINT source_arch_pkey PRIMARY KEY
)
EOS

    $conn->do("COMMENT ON TABLE source_architectures IS 'Possible values for the Architecture field in sources'");
    $conn->do("COMMENT ON COLUMN source_architectures.architecture IS 'Architecture name'");


    $conn->do(<<'EOS');
CREATE TABLE source_package_architectures (
       	source_package text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	architecture text
	  CONSTRAINT source_arch_arch_fkey
	  REFERENCES source_architectures(architecture)
	  NOT NULL,
	UNIQUE (source_package, source_version, architecture),
	CONSTRAINT source_arch_source_fkey FOREIGN KEY (source_package, source_version)
	  REFERENCES sources (source_package, source_version)
	  ON DELETE CASCADE
)
EOS

    $conn->do("COMMENT ON TABLE source_package_architectures IS 'Source package architectures (from Sources)'");
    $conn->do("COMMENT ON COLUMN source_package_architectures.source_package IS 'Package name'");
    $conn->do("COMMENT ON COLUMN source_package_architectures.source_version IS 'Package version number'");
    $conn->do("COMMENT ON COLUMN source_package_architectures.architecture IS 'Architecture name'");


    $conn->do(<<'EOS');
CREATE TABLE binaries (
	-- PostgreSQL will not allow "binary" as column name
	binary_package text NOT NULL,
	binary_version debversion NOT NULL,
	architecture text
	  CONSTRAINT bin_arch_fkey REFERENCES binary_architectures(architecture)
	  NOT NULL,
	source_package text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	section text
	  CONSTRAINT bin_section_fkey REFERENCES package_sections(section),
	type text
	  CONSTRAINT bin_pkg_type_fkey REFERENCES package_types(type)
	  NOT NULL,
	priority text
	  CONSTRAINT bin_priority_fkey REFERENCES package_priorities(priority),
	installed_size integer
	  NOT NULL,
	multi_arch text,
	essential boolean,
	build_essential boolean,
	pre_depends text,
	depends text,
	recommends text,
	suggests text,
	conflicts text,
	breaks text,
	enhances text,
	replaces text,
	provides text,
	CONSTRAINT binaries_pkey PRIMARY KEY (binary_package, binary_version, architecture),
	CONSTRAINT binaries_source_fkey FOREIGN KEY (source_package, source_version)
	  REFERENCES sources (source_package, source_version)
	  ON DELETE CASCADE
)
EOS

    $conn->do("COMMENT ON TABLE binaries IS 'Binary packages specific to single architectures (from Packages)'");
    $conn->do("COMMENT ON COLUMN binaries.binary_package IS 'Binary package name'");
    $conn->do("COMMENT ON COLUMN binaries.binary_version IS 'Binary package version number'");
    $conn->do("COMMENT ON COLUMN binaries.architecture IS 'Architecture name'");
    $conn->do("COMMENT ON COLUMN binaries.source_package IS 'Source package name'");
    $conn->do("COMMENT ON COLUMN binaries.source_version IS 'Source package version number'");
    $conn->do("COMMENT ON COLUMN binaries.section IS 'Package section'");
    $conn->do("COMMENT ON COLUMN binaries.type IS 'Package type (e.g. deb, udeb)'");
    $conn->do("COMMENT ON COLUMN binaries.priority IS 'Package priority'");
    $conn->do("COMMENT ON COLUMN binaries.installed_size IS 'Size of installed package (KiB, rounded up)'");
    $conn->do("COMMENT ON COLUMN binaries.multi_arch IS 'Multiple architecture co-installation behaviour'");
    $conn->do("COMMENT ON COLUMN binaries.essential IS 'Package is essential'");
    $conn->do("COMMENT ON COLUMN binaries.build_essential IS 'Package is essential for building'");
    $conn->do("COMMENT ON COLUMN binaries.pre_depends IS 'Package pre-dependencies'");
    $conn->do("COMMENT ON COLUMN binaries.depends IS 'Package dependencies'");
    $conn->do("COMMENT ON COLUMN binaries.recommends IS 'Package recommendations'");
    $conn->do("COMMENT ON COLUMN binaries.suggests IS 'Package suggestions'");
    $conn->do("COMMENT ON COLUMN binaries.conflicts IS 'Package conflicts with other packages'");
    $conn->do("COMMENT ON COLUMN binaries.breaks IS 'Package breaks other packages'");
    $conn->do("COMMENT ON COLUMN binaries.enhances IS 'Package enhances other packages'");
    $conn->do("COMMENT ON COLUMN binaries.replaces IS 'Package replaces other packages'");
    $conn->do("COMMENT ON COLUMN binaries.provides IS 'Package provides other packages'");


    $conn->do(<<'EOS');
CREATE TABLE suite_sources (
	source_package text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	suite text
	  CONSTRAINT suite_sources_suite_fkey REFERENCES suites(suitenick)
	  ON DELETE CASCADE
	  NOT NULL,
	component text
	  CONSTRAINT suite_sources_component_fkey REFERENCES components(component)
	  NOT NULL,
	CONSTRAINT suite_sources_pkey PRIMARY KEY (source_package, suite, component),
	CONSTRAINT suite_sources_src_fkey FOREIGN KEY (source_package, source_version)
	  REFERENCES sources (source_package, source_version)
	  ON DELETE CASCADE,
	CONSTRAINT suite_sources_suitecomp_fkey FOREIGN KEY (suite, component)
	  REFERENCES suite_components (suitenick, component)
	  ON DELETE CASCADE
)
EOS

    $conn->do("CREATE INDEX suite_sources_src_ver_idx ON suite_sources (source_package, source_version)");

    $conn->do("COMMENT ON TABLE suite_sources IS 'Source packages contained within a suite'");
    $conn->do("COMMENT ON COLUMN suite_sources.source_package IS 'Source package name'");
    $conn->do("COMMENT ON COLUMN suite_sources.source_version IS 'Source package version number'");
    $conn->do("COMMENT ON COLUMN suite_sources.suite IS 'Suite name'");
    $conn->do("COMMENT ON COLUMN suite_sources.component IS 'Suite component'");


    $conn->do(<<'EOS');
CREATE TABLE suite_binaries (
	binary_package text
	  NOT NULL,
	binary_version debversion
	  NOT NULL,
	architecture text
	  CONSTRAINT suite_bin_arch_fkey
	    REFERENCES binary_architectures(architecture)
            ON DELETE CASCADE
	  NOT NULL,
	suite text
	  CONSTRAINT suite_bin_suite_fkey
	    REFERENCES suites(suitenick)
            ON DELETE CASCADE
	  NOT NULL,
	component text
	  CONSTRAINT suite_sources_component_fkey
	    REFERENCES components(component)
	    ON DELETE CASCADE
	  NOT NULL,
	CONSTRAINT suite_bin_pkey
	  PRIMARY KEY (binary_package, architecture, suite, component),
	CONSTRAINT suite_bin_bin_fkey
          FOREIGN KEY (binary_package, binary_version, architecture)
	  REFERENCES binaries (binary_package, binary_version, architecture)
	  ON DELETE CASCADE,
	CONSTRAINT suite_bin_suite_arch_fkey FOREIGN KEY (suite, architecture)
	  REFERENCES suite_architectures (suitenick, architecture)
	  ON DELETE CASCADE
)
EOS

    $conn->do("CREATE INDEX suite_binaries_pkg_ver_idx ON suite_binaries (binary_package, binary_version)");

    $conn->do("COMMENT ON TABLE suite_binaries IS 'Binary packages contained within a suite'");
    $conn->do("COMMENT ON COLUMN suite_binaries.binary_package IS 'Binary package name'");
    $conn->do("COMMENT ON COLUMN suite_binaries.binary_version IS 'Binary package version number'");
    $conn->do("COMMENT ON COLUMN suite_binaries.architecture IS 'Architecture name'");
    $conn->do("COMMENT ON COLUMN suite_binaries.suite IS 'Suite name'");
    $conn->do("COMMENT ON COLUMN suite_binaries.component IS 'Suite component'");

    $conn->do(<<'EOS');
CREATE TABLE builders (
	builder text
	  CONSTRAINT builder_pkey PRIMARY KEY,
	arch text
	  CONSTRAINT builder_arch_fkey REFERENCES architectures(arch)
	  NOT NULL,
	address text
	  NOT NULL
)
EOS

    $conn->do("COMMENT ON TABLE builders IS 'buildd usernames (database users from _userinfo in old MLDBM db format)'");
    $conn->do("COMMENT ON COLUMN builders.builder IS 'Username'");
    $conn->do("COMMENT ON COLUMN builders.arch IS 'Buildd architecture'");
    $conn->do("COMMENT ON COLUMN builders.address IS 'Remote e-mail address of the buildd user'");

    $conn->do(<<'EOS');
CREATE TABLE package_states (
	name text
	  CONSTRAINT state_pkey PRIMARY KEY
)
EOS

    $conn->do("COMMENT ON TABLE package_states IS 'Package states'");
    $conn->do("COMMENT ON COLUMN package_states.name IS 'State name'");

    $conn->do(<<'EOS');
CREATE TABLE build_status (
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	arch text
	  CONSTRAINT build_status_arch_fkey REFERENCES architectures(arch)
	  ON DELETE CASCADE
	  NOT NULL,
	suite text
	  CONSTRAINT build_status_suite_fkey REFERENCES suites(suite)
	  ON DELETE CASCADE
	  NOT NULL,
	bin_nmu integer,
	user_name text
	  NOT NULL
	  DEFAULT CURRENT_USER,
	builder text
	  -- Can be NULL in case of states set up manually by people.
	  CONSTRAINT build_status_builder_fkey REFERENCES builders(builder),
	status text
	  CONSTRAINT build_status_status_fkey REFERENCES package_states(name)
	  NOT NULL,
	log bytea,
	ctime timestamp with time zone
	  NOT NULL
	  DEFAULT 'epoch'::timestamp,
	CONSTRAINT build_status_pkey PRIMARY KEY (source, arch, suite),
	CONSTRAINT build_status_src_fkey FOREIGN KEY(source, source_version)
	  REFERENCES sources(source, source_version)
	  ON DELETE CASCADE,
	CONSTRAINT suite_bin_suite_arch_fkey FOREIGN KEY (suite, arch)
	  REFERENCES suite_arches (suite, arch)
	  ON DELETE CASCADE
)
EOS

    $conn->do("CREATE INDEX build_status_source ON build_status (source)");

    $conn->do("COMMENT ON TABLE build_status IS 'Build status for each package'");
    $conn->do("COMMENT ON COLUMN build_status.source IS 'Source package name'");
    $conn->do("COMMENT ON COLUMN build_status.source_version IS 'Source package version number'");
    $conn->do("COMMENT ON COLUMN build_status.arch IS 'Architecture name'");
    $conn->do("COMMENT ON COLUMN build_status.suite IS 'Suite name'");
    $conn->do("COMMENT ON COLUMN build_status.bin_nmu IS 'Scheduled binary NMU version, if any'");
    $conn->do("COMMENT ON COLUMN build_status.user_name IS 'User making this change (username)'");
    $conn->do("COMMENT ON COLUMN build_status.builder IS 'Build dæmon making this change (username)'");
    $conn->do("COMMENT ON COLUMN build_status.status IS 'Status name'");
    $conn->do("COMMENT ON COLUMN build_status.ctime IS 'Stage change time'");

    $conn->do(<<'EOS');
CREATE TABLE build_status_history (
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	arch text
	  CONSTRAINT build_status_history_arch_fkey REFERENCES architectures(arch)
	  ON DELETE CASCADE
	  NOT NULL,
	suite text
	  CONSTRAINT build_status_history_suite_fkey REFERENCES suites(suite)
	  ON DELETE CASCADE
	  NOT NULL,
	bin_nmu integer,
	user_name text
	  NOT NULL
	  DEFAULT CURRENT_USER,
	builder text
	  CONSTRAINT build_status_history_builder_fkey REFERENCES builders(builder),
	status text
	  CONSTRAINT build_status_history_status_fkey REFERENCES package_states(name)
	  NOT NULL,
	log bytea,
	ctime timestamp with time zone
	  NOT NULL DEFAULT CURRENT_TIMESTAMP
)
EOS

    $conn->do("CREATE INDEX build_status_history_source ON build_status_history (source)");
    $conn->do("CREATE INDEX build_status_history_ctime ON build_status_history (ctime)");

    $conn->do("COMMENT ON TABLE build_status_history IS 'Build status history for each package'");
    $conn->do("COMMENT ON COLUMN build_status_history.source IS 'Source package name'");
    $conn->do("COMMENT ON COLUMN build_status_history.source_version IS 'Source package version number'");
    $conn->do("COMMENT ON COLUMN build_status_history.arch IS 'Architecture name'");
    $conn->do("COMMENT ON COLUMN build_status_history.suite IS 'Suite name'");
    $conn->do("COMMENT ON COLUMN build_status_history.bin_nmu IS 'Scheduled binary NMU version, if any'");
    $conn->do("COMMENT ON COLUMN build_status_history.user_name IS 'User making this change (username)'");
    $conn->do("COMMENT ON COLUMN build_status_history.builder IS 'Build dæmon making this change (username)'");
    $conn->do("COMMENT ON COLUMN build_status_history.status IS 'Status name'");
    $conn->do("COMMENT ON COLUMN build_status_history.ctime IS 'Stage change time'");

    $conn->do(<<'EOS');
CREATE TABLE build_status_properties (
	source text NOT NULL,
	arch text NOT NULL,
	source suite NOT NULL,
	prop_name text NOT NULL,
	prop_value text NOT NULL,
	CONSTRAINT build_status_properties_fkey
	  FOREIGN KEY(source, arch)
	  REFERENCES build_status(id)
	  ON DELETE CASCADE,
	CONSTRAINT build_status_properties_unique
	  UNIQUE (source, arch, prop_name)
)
EOS

    $conn->do("COMMENT ON TABLE build_status_properties IS 'Additional package-specific properties (e.g. For PermBuildPri/BuildPri/Binary-NMU-(Version|ChangeLog)/Notes)'");
    $conn->do("COMMENT ON COLUMN build_status_properties.source IS 'Source package name'");
    $conn->do("COMMENT ON COLUMN build_status_properties.arch IS 'Architecture name'");
    $conn->do("COMMENT ON COLUMN build_status_properties.suite IS 'Suite name'");
    $conn->do("COMMENT ON COLUMN build_status_properties.prop_name IS 'Property name'");
    $conn->do("COMMENT ON COLUMN build_status_properties.prop_value IS 'Property value'");

# Make this a table because in the future we may have more
# fine-grained result states.
    $conn->do(<<'EOS');
CREATE TABLE build_log_result (
	result text
	  CONSTRAINT build_log_result_pkey PRIMARY KEY,
	is_success boolean
	  DEFAULT 'f'
)
EOS

    $conn->do("COMMENT ON TABLE build_log_result IS 'Possible results states of a build log'");
    $conn->do("COMMENT ON COLUMN build_log_result.result IS 'Meaningful and short name for the result'");
    $conn->do("COMMENT ON COLUMN build_log_result.is_success IS 'Whether the result of the build is successful'");

    $conn->do(<<'EOS');
CREATE TABLE build_logs (
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	arch text
	  CONSTRAINT build_logs_arch_fkey REFERENCES architectures(arch)
	  NOT NULL,
	suite text
	  CONSTRAINT build_logs_suite_fkey REFERENCES suites(suite)
	  NOT NULL,
	date timestamp with time zone
	  NOT NULL,
	result text
	  CONSTRAINT build_logs_result_fkey REFERENCES build_log_result(result)
	  NOT NULL,
	build_time interval,
	used_space integer,
	path text
	  CONSTRAINT build_logs_pkey PRIMARY KEY
)
EOS

    $conn->do("CREATE INDEX build_logs_source_idx ON build_logs (source)");

    $conn->do("COMMENT ON TABLE build_logs IS 'Available build logs'");
    $conn->do("COMMENT ON COLUMN build_logs.source IS 'Source package name'");
    $conn->do("COMMENT ON COLUMN build_logs.source_version IS 'Source package version'");
    $conn->do("COMMENT ON COLUMN build_logs.arch IS 'Architecture name'");
    $conn->do("COMMENT ON COLUMN build_logs.suite IS 'Suite name'");
    $conn->do("COMMENT ON COLUMN build_logs.date IS 'Date of the log'");
    $conn->do("COMMENT ON COLUMN build_logs.result IS 'Result state'");
    $conn->do("COMMENT ON COLUMN build_logs.build_time IS 'Time needed by the build'");
    $conn->do("COMMENT ON COLUMN build_logs.used_space IS 'Space needed by the build'");
    $conn->do("COMMENT ON COLUMN build_logs.path IS 'Relative path to the log file'");

    $conn->do(<<'EOS');
CREATE TABLE log (
	time timestamp with time zone
	  NOT NULL DEFAULT CURRENT_TIMESTAMP,
	username text NOT NULL DEFAULT CURRENT_USER,
	message text NOT NULL
)
EOS

    $conn->do("CREATE INDEX log_idx ON log (time)");

    $conn->do("COMMENT ON TABLE log IS 'Log messages'");
    $conn->do("COMMENT ON COLUMN log.time IS 'Log entry time'");
    $conn->do("COMMENT ON COLUMN log.username IS 'Log user name'");
    $conn->do("COMMENT ON COLUMN log.message IS 'Log entry message'");

    $conn->do(<<'EOS');
CREATE TABLE people (
	login text
	  CONSTRAINT people_pkey PRIMARY KEY,
	full_name text
	  NOT NULL,
	address text
	  NOT NULL
)
EOS

    $conn->do("COMMENT ON TABLE people IS 'People wanna-build should know about'");
    $conn->do("COMMENT ON COLUMN people.login IS 'Debian login'");
    $conn->do("COMMENT ON COLUMN people.full_name IS 'Full name'");
    $conn->do("COMMENT ON COLUMN people.address IS 'E-mail address'");

    $conn->do(<<'EOS');
CREATE TABLE buildd_admins (
	builder text
	  CONSTRAINT buildd_admin_builder_fkey REFERENCES builders(builder)
	  ON DELETE CASCADE
	  NOT NULL,
	admin text
	  CONSTRAINT buildd_admin_admin_fkey REFERENCES people(login)
	  ON DELETE CASCADE
	  NOT NULL,
	backup boolean
	  DEFAULT 'f',
	UNIQUE (builder, admin)
)
EOS

    $conn->do("COMMENT ON TABLE buildd_admins IS 'Admins for each buildd'");
    $conn->do("COMMENT ON COLUMN buildd_admins.builder IS 'The buildd'");
    $conn->do("COMMENT ON COLUMN buildd_admins.admin IS 'The admin login'");
    $conn->do("COMMENT ON COLUMN buildd_admins.backup IS 'Whether this is only a backup admin'");


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_release(nsuitenick text,
                    	   		 nsuite text,
			      		 ncodename text,
	  		      		 nversion debversion,
	  		      		 norigin text,
	    		      		 nlabel text,
	     		      		 ndate timestamp with time zone,
	      		      		 nvaliduntil timestamp with time zone)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        UPDATE suite_release SET fetched=now(), suite=nsuite, codename=ncodename, version=nversion, origin=norigin, label=nlabel, date=ndate, validuntil=nvaliduntil WHERE suitenick = nsuitenick;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO suite_release (suitenick, fetched, suite, codename, version, origin, label, date, validuntil) VALUES (nsuitenick, now(), nsuite, ncodename, nversion, norigin, nlabel, ndate, nvaliduntil);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS

    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_architecture(narchitecture text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM architecture FROM architectures WHERE architecture = narchitecture;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO architectures (architecture) VALUES (narchitecture);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS

    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_component(ncomponent text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM component FROM components WHERE component = ncomponent;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO components (component) VALUES (ncomponent);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_suite_architecture(nsuitenick text,
                                                    narchitecture text)
RETURNS VOID AS
$$
BEGIN
    PERFORM merge_architecture(narchitecture);

    LOOP
        -- first try to update the key
        PERFORM suitenick, architecture FROM suite_architectures WHERE suitenick=nsuitenick AND architecture = narchitecture;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO suite_architectures (suitenick, architecture) VALUES (nsuitenick, narchitecture);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_suite_component(nsuitenick text,
                                                 ncomponent text)
RETURNS VOID AS
$$
BEGIN
    PERFORM merge_component(ncomponent);

    LOOP
        -- first try to update the key
        PERFORM suitenick, component FROM suite_components WHERE suitenick=nsuitenick AND component = ncomponent;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO suite_components (suitenick, component) VALUES (nsuitenick, ncomponent);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_suite_source_detail(nsuitenick text,
					             ncomponent text)
RETURNS VOID AS
$$
BEGIN
    LOOP
	PERFORM merge_suite_component(nsuitenick, ncomponent);

        -- first try to update the key
        PERFORM suitenick, component FROM suite_source_detail WHERE suitenick = nsuitenick AND component = ncomponent;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO suite_source_detail (suitenick, component) VALUES (nsuitenick, ncomponent);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS

    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_suite_binary_detail(nsuitenick text,
                                                     narchitecture text,
					             ncomponent text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        PERFORM merge_suite_architecture(nsuitenick, 'all');
        PERFORM merge_suite_architecture(nsuitenick, narchitecture);
	PERFORM merge_suite_component(nsuitenick, ncomponent);

        -- first try to update the key
        PERFORM suitenick, architecture, component FROM suite_binary_detail WHERE suitenick = nsuitenick AND architecture = narchitecture AND component = ncomponent;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO suite_binary_detail (suitenick, architecture, component) VALUES (nsuitenick, narchitecture, ncomponent);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_package_type(ntype text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM type FROM package_types WHERE type = ntype;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO package_types (type) VALUES (ntype);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_source_architecture(narchitecture text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM architecture FROM source_architectures WHERE architecture = narchitecture;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO source_architectures (architecture) VALUES (narchitecture);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS

    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_binary_architecture(narchitecture text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM architecture FROM binary_architectures WHERE architecture = narchitecture;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO binary_architectures (architecture) VALUES (narchitecture);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_package_priority(npriority text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM priority FROM package_priorities WHERE priority = npriority;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO package_priorities (priority) VALUES (npriority);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_package_section(nsection text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM section FROM package_sections WHERE section = nsection;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO package_sections (section) VALUES (nsection);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_sources(nsuite text,
					 ncomponent text,
					 nsha256 text)
RETURNS VOID AS
$$
BEGIN
    CREATE TEMPORARY TABLE tmp_sources (LIKE sources INCLUDING DEFAULTS);

    INSERT INTO tmp_sources
    SELECT * FROM new_sources;

    -- Move into main table.
    INSERT INTO sources
    SELECT * FROM tmp_sources
    WHERE (source_package, source_version) IN
      (SELECT source_package, source_version FROM tmp_sources AS s
       EXCEPT
       SELECT source_package, source_version FROM sources AS s);

    --  Remove old suite-source mappings.
    DELETE FROM suite_sources AS s
    WHERE s.suite = nsuite and s.component = ncomponent;

    -- Create new suite-source mappings.
    INSERT INTO suite_sources (source_package, source_version, suite, component)
    SELECT s.source_package, s.source_version, nsuite AS suite, ncomponent AS component
    FROM tmp_sources AS s;

    DELETE FROM tmp_sources
    WHERE (source_package, source_version) IN
      (SELECT source_package, source_version FROM tmp_sources AS s
       EXCEPT
       SELECT source_package, source_version FROM sources AS s);

    UPDATE sources AS s
    SET
      component=n.component,
      section=n.section,
      priority=n.priority,
      maintainer=n.maintainer,
      uploaders=n.uploaders,
      build_dep=n.build_dep,
      build_dep_indep=n.build_dep_indep,
      build_confl=n.build_confl,
      build_confl_indep=n.build_confl_indep,
      stdver=n.stdver
    FROM tmp_sources AS n
    WHERE s.source_package=n.source_package AND s.source_version=n.source_version;

    -- Update architectures
    DELETE FROM source_package_architectures
    WHERE (source_package, source_version) IN
    (SELECT source_package, source_version
     FROM new_sources_architectures);

    INSERT INTO source_package_architectures
    SELECT * FROM new_sources_architectures;

    -- Update merge state
    UPDATE suite_source_detail AS d
    SET
      sha256 = nsha256
    WHERE d.suitenick = nsuite AND d.component = ncomponent;

    DROP TABLE tmp_sources;

EXCEPTION WHEN OTHERS THEN
    DROP TABLE IF EXISTS tmp_sources;
    RAISE;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
-- Add dummy source package for binaries lacking sources.
CREATE OR REPLACE FUNCTION merge_dummy_source(nsource_package text,
                                              nsource_version debversion)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM source_package, source_version FROM sources
	WHERE source_package=nsource_package AND source_version=nsource_version;

        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO sources (source_package, source_version, component, section, priority, maintainer) VALUES (nsource_package, nsource_version, 'INVALID', 'INVALID', 'INVALID', 'INVALID');
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_source_architecture(narchitecture text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM architecture FROM source_architectures WHERE architecture = narchitecture;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO source_architectures (architecture) VALUES (narchitecture);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql
EOS


    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION merge_binaries(nsuite text,
					  ncomponent text,
					  narchitecture text,
					  nsha256 text)
RETURNS VOID AS
$$
BEGIN
    CREATE TEMPORARY TABLE tmp_binaries (LIKE binaries INCLUDING DEFAULTS);

    INSERT INTO tmp_binaries
    SELECT * FROM new_binaries;

    -- Move into main table.
    INSERT INTO binaries
    SELECT * FROM tmp_binaries
    WHERE (binary_package, binary_version) IN
      (SELECT binary_package, binary_version FROM tmp_binaries AS s
         WHERE (s.architecture = narchitecture OR
	        s.architecture = 'all')
       EXCEPT
       SELECT binary_package, binary_version FROM binaries AS s
         WHERE (s.architecture = narchitecture OR
	        s.architecture = 'all'));

    --  Remove old suite-binary mappings.
    DELETE FROM suite_binaries AS s
    WHERE s.suite = nsuite AND
          s.component = ncomponent AND
          (s.architecture = narchitecture OR s.architecture = 'all');

    -- Create new suite-binary mappings.
    INSERT INTO suite_binaries (binary_package,
                                binary_version,
				suite,
				component,
				architecture)
    SELECT s.binary_package AS binary_package,
           s.binary_version AS binary_version,
	   nsuite AS suite,
	   ncomponent AS component,
	   s.architecture AS architecture
    FROM tmp_binaries AS s;

    DELETE FROM tmp_binaries
    WHERE (binary_package, binary_version) IN
      (SELECT binary_package, binary_version FROM tmp_binaries AS s
       EXCEPT
       SELECT binary_package, binary_version FROM binaries AS s);

    UPDATE binaries AS s
    SET
      source_package=n.source_package,
      source_version=n.source_version,
      section=n.section,
      type=n.type,
      priority=n.priority,
      installed_size=n.installed_size,
      multi_arch=n.multi_arch,
      essential=n.essential,
      build_essential=n.build_essential,
      pre_depends=n.pre_depends,
      depends=n.depends,
      recommends=n.recommends,
      suggests=n.suggests,
      conflicts=n.conflicts,
      breaks=n.breaks,
      enhances=n.enhances,
      replaces=n.replaces,
      provides=n.provides
    FROM tmp_binaries AS n
    WHERE s.binary_package=n.binary_package AND
          s.binary_version=n.binary_version AND
	  s.architecture=n.architecture;

    UPDATE suite_binary_detail AS d
    SET
      sha256 = nsha256
    WHERE
      d.suitenick = nsuite AND
      d.component = ncomponent AND
      d.architecture = narchitecture;

    DROP TABLE tmp_binaries;

EXCEPTION WHEN OTHERS THEN
    DROP TABLE IF EXISTS tmp_binaries;
    RAISE;
END;
$$
LANGUAGE plpgsql
EOS

    $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION clean_binaries()
RETURNS integer AS
$$
DECLARE
    deleted integer := 0;
BEGIN

    DELETE FROM binaries
    WHERE (binary_package, binary_version, architecture) IN
    (SELECT b.binary_package AS binary_package,
            b.binary_version AS binary_version,
 	    b.architecture AS architecture
     FROM binaries AS b
     LEFT OUTER join suite_binaries AS s
     ON (s.binary_package = b.binary_package AND
         s.binary_version = b.binary_version AND
 	 s.architecture = b.architecture)
     WHERE s.binary_package IS NULL);

     IF found THEN
        GET DIAGNOSTICS deleted = ROW_COUNT;
     END IF;

     RETURN deleted;
END;
$$
LANGUAGE plpgsql
EOS

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION clean_sources()
RETURNS integer AS
$$
DECLARE
    deleted integer := 0;
BEGIN

    DELETE FROM sources
    WHERE (source_package, source_version) IN
    (SELECT s.source_package AS source_package,
            s.source_version AS source_version
     FROM sources AS s
     LEFT OUTER join binaries AS b
     ON (s.source_package = b.source_package AND
         s.source_version = b.source_version)
     WHERE b.source_package IS NULL);

     IF found THEN
        GET DIAGNOSTICS deleted = ROW_COUNT;
     END IF;

     RETURN deleted;
END;
$$
LANGUAGE plpgsql
EOS



# Triggers to insert missing sections and priorities

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION source_fkey_deps () RETURNS trigger AS $fkey_deps$
BEGIN
    IF NEW.component IS NOT NULL THEN
        PERFORM merge_component(NEW.component);
    END IF;
    IF NEW.section IS NOT NULL THEN
        PERFORM merge_package_section(NEW.section);
    END IF;
    IF NEW.priority IS NOT NULL THEN
        PERFORM merge_package_priority(NEW.priority);
    END IF;
    RETURN NEW;
END;
$fkey_deps$ LANGUAGE plpgsql
EOS

     $conn->do("COMMENT ON FUNCTION source_fkey_deps () IS 'Check foreign key references exist'");

     $conn->do("CREATE TRIGGER source_fkey_deps BEFORE INSERT OR UPDATE ON sources FOR EACH ROW EXECUTE PROCEDURE source_fkey_deps()");
     $conn->do("COMMENT ON TRIGGER source_fkey_deps ON sources IS 'Check foreign key references exist'");

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION source_package_architecture_fkey_deps () RETURNS trigger AS $fkey_deps$
BEGIN
    IF NEW.architecture IS NOT NULL THEN
        PERFORM merge_source_architecture(NEW.architecture);
    END IF;
    RETURN NEW;
END;
$fkey_deps$ LANGUAGE plpgsql
EOS

     $conn->do("COMMENT ON FUNCTION source_package_architecture_fkey_deps () IS 'Check foreign key references exist'");

     $conn->do("CREATE TRIGGER source_package_architecture_fkey_deps BEFORE INSERT OR UPDATE ON sources FOR EACH ROW EXECUTE PROCEDURE source_package_architecture_fkey_deps()");
     $conn->do("COMMENT ON TRIGGER source_package_architecture_fkey_deps ON sources IS 'Check foreign key references exist'");

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION binary_fkey_deps () RETURNS trigger AS $fkey_deps$
BEGIN
    IF NEW.source_package IS NOT NULL AND NEW.source_version IS NOT NULL THEN
        PERFORM merge_dummy_source(NEW.source_package, NEW.source_version);
    END IF;
    IF NEW.architecture IS NOT NULL THEN
        PERFORM merge_binary_architecture(NEW.architecture);
    END IF;
    IF NEW.section IS NOT NULL THEN
    PERFORM merge_package_section(NEW.section);
    END IF;
    IF NEW.type IS NOT NULL THEN
        PERFORM merge_package_type(NEW.type);
    END IF;
    IF NEW.priority IS NOT NULL THEN
        PERFORM merge_package_priority(NEW.priority);
    END IF;
    RETURN NEW;
END;
$fkey_deps$ LANGUAGE plpgsql
EOS

     $conn->do("COMMENT ON FUNCTION binary_fkey_deps () IS 'Check foreign key references exist'");

     $conn->do("CREATE TRIGGER binary_fkey_deps BEFORE INSERT OR UPDATE ON binaries FOR EACH ROW EXECUTE PROCEDURE binary_fkey_deps()");
     $conn->do("COMMENT ON TRIGGER binary_fkey_deps ON binaries IS 'Check foreign key references exist'");

# Triggers to insert missing package architectures

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION package_check_arch() RETURNS trigger AS $package_check_arch$
BEGIN
  PERFORM arch FROM package_architectures WHERE (arch = NEW.arch);
  IF FOUND = 'f' THEN
    INSERT INTO package_architectures (arch) VALUES (NEW.arch);
  END IF;
  RETURN NEW;
END;
$package_check_arch$ LANGUAGE plpgsql
EOS

     $conn->do("COMMENT ON FUNCTION package_check_arch () IS 'Insert missing values into package_architectures (from NEW.arch)'");

     $conn->do("CREATE TRIGGER check_arch BEFORE INSERT OR UPDATE ON source_architectures FOR EACH ROW EXECUTE PROCEDURE package_check_arch()");
     $conn->do("COMMENT ON TRIGGER check_arch ON source_architectures IS 'Ensure foreign key references (arch) exist'");

     $conn->do("CREATE TRIGGER check_arch BEFORE INSERT OR UPDATE ON binaries FOR EACH ROW EXECUTE PROCEDURE package_check_arch()");
     $conn->do("COMMENT ON TRIGGER check_arch ON binaries IS 'Ensure foreign key references (arch) exist'");

# Triggers on build_status:
# - unconditionally update ctime
# - verify bin_nmu is a positive integer (and change 0 to NULL)
# - insert a record into status_history for every change in build_status

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION set_ctime()
RETURNS trigger AS $set_ctime$
BEGIN
  NEW.ctime = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$set_ctime$ LANGUAGE plpgsql
EOS

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION check_bin_nmu_number()
RETURNS trigger AS $check_bin_nmu_number$
BEGIN
  IF NEW.bin_nmu = 0 THEN
    NEW.bin_nmu = NULL; -- Avoid two values with same meaning
  ELSIF NEW.bin_nmu < 0 THEN
    RAISE EXCEPTION 'Invalid value for "bin_nmu" column: %', NEW.bin_nmu;
  END IF;
  RETURN NEW;
END;
$check_bin_nmu_number$ LANGUAGE plpgsql
EOS

     $conn->do("CREATE TRIGGER check_bin_nmu BEFORE INSERT OR UPDATE ON build_status FOR EACH ROW EXECUTE PROCEDURE check_bin_nmu_number()");
     $conn->do("COMMENT ON TRIGGER check_bin_nmu ON build_status IS 'Ensure \"bin_nmu\" is a positive integer, or set it to NULL if 0'");

     $conn->do("CREATE TRIGGER set_or_update_ctime BEFORE INSERT OR UPDATE ON build_status FOR EACH ROW EXECUTE PROCEDURE set_ctime()");
     $conn->do("COMMENT ON TRIGGER set_or_update_ctime ON build_status IS 'Set or update the \"ctime\" column to now()'");

     $conn->do(<<'EOS');
CREATE OR REPLACE FUNCTION update_status_history()
RETURNS trigger AS $update_status_history$
BEGIN
  INSERT INTO build_status_history
    (source_package, source_version, arch, suite,
     bin_nmu, user_name, builder, status, ctime)
    VALUES
      (NEW.source_package, NEW.source_version, NEW.arch, NEW.suite,
       NEW.bin_nmu, NEW.user_name, NEW.builder, NEW.status, NEW.ctime);
  RETURN NULL;
END;
$update_status_history$ LANGUAGE plpgsql
EOS

     $conn->do("CREATE TRIGGER update_history AFTER INSERT OR UPDATE ON build_status FOR EACH ROW EXECUTE PROCEDURE update_status_history()");
     $conn->do("COMMENT ON TRIGGER update_history ON build_status IS 'Insert a record of the status change into build_status_history'");

     $conn->do(<<'EOS');
INSERT INTO package_states (name) VALUES
  ('build-attempted'),
  ('building'),
  ('built'),
  ('dep-wait'),
  ('dep-wait-removed'),
  ('failed'),
  ('failed-removed'),
  ('install-wait'),
  ('installed'),
  ('needs-build'),
  ('not-for-us'),
  ('old-failed'),
  ('reupload-wait'),
  ('state'),
  ('uploaded')
EOS

     $conn->do(<<'EOS');
INSERT INTO build_log_result (result, is_success) VALUES
  ('maybe-failed', 'f'),
  ('maybe-successful', 't'),
  ('skipped', 'f')
EOS

    $conn->commit();
}

1;
