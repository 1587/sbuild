--- Debian Source Builder: Database Schema for PostgreSQL            -*- sql -*-
---
--- Copyright © 2008-2011 Roger Leigh <rleigh@debian.org>
--- Copyright © 2008-2009 Marc 'HE' Brockschmidt <he@debian.org>
--- Copyright © 2008-2009 Adeodato Simó <adeodato@debian.org>
---
--- This program is free software: you can redistribute it and/or modify
--- it under the terms of the GNU General Public License as published by
--- the Free Software Foundation, either version 2 of the License, or
--- (at your option) any later version.
---
--- This program is distributed in the hope that it will be useful, but
--- WITHOUT ANY WARRANTY; without even the implied warranty of
--- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
--- General Public License for more details.
---
--- You should have received a copy of the GNU General Public License
--- along with this program.  If not, see
--- <http://www.gnu.org/licenses/>.

CREATE TABLE keys (
       name text CONSTRAINT keys_pkey PRIMARY KEY,
       key bytea NOT NULL
);

COMMENT ON TABLE keys IS 'GPG keys used to sign Release files';
COMMENT ON COLUMN keys.name IS 'Name used to reference a key';
COMMENT ON COLUMN keys.key IS 'GPG key as exported ASCII armoured text';

CREATE TABLE suites (
	suitenick text CONSTRAINT suites_pkey PRIMARY KEY,
	key text NOT NULL
	  CONSTRAINT suites_key_fkey REFERENCES keys(name),
	uri text NOT NULL,
	distribution text NOT NULL
);

COMMENT ON TABLE suites IS 'Valid suites';
COMMENT ON COLUMN suites.suitenick IS 'Name used to reference a suite (nickname)';
COMMENT ON COLUMN suites.key IS 'GPG key name for validation';
COMMENT ON COLUMN suites.uri IS 'URI to fetch from';
COMMENT ON COLUMN suites.distribution IS 'Distribution name (used in combination with URI)';

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
	validuntil timestamp with time zone, -- old suites don't support it
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
);

COMMENT ON TABLE suite_release IS 'Suite release details';
COMMENT ON COLUMN suite_release.suitenick IS 'Suite name (nickname)';
COMMENT ON COLUMN suite_release.fetched IS 'Date on which the Release file was fetched from the archive';
COMMENT ON COLUMN suite_release.suite IS 'Suite name';
COMMENT ON COLUMN suite_release.codename IS 'Suite codename';
COMMENT ON COLUMN suite_release.version IS 'Suite release version (if applicable)';
COMMENT ON COLUMN suite_release.origin IS 'Suite origin';
COMMENT ON COLUMN suite_release.label IS 'Suite label';
COMMENT ON COLUMN suite_release.date IS 'Date on which the Release file was generated';
COMMENT ON COLUMN suite_release.validuntil IS 'Date after which the data expires';
COMMENT ON COLUMN suite_release.priority IS 'Sorting order (lower is higher priority)';
COMMENT ON COLUMN suite_release.depwait IS 'Automatically wait on dependencies?';
COMMENT ON COLUMN suite_release.hidden IS 'Hide suite from public view?  (e.g. for -security)';


CREATE TABLE architectures (
	architecture text
	  CONSTRAINT arch_pkey PRIMARY KEY
);

COMMENT ON TABLE architectures IS 'Architectures in use';
COMMENT ON COLUMN architectures.architecture IS 'Architecture name';


CREATE TABLE components (
	component text
	  CONSTRAINT components_pkey PRIMARY KEY
);

COMMENT ON TABLE components IS 'Archive components in use';
COMMENT ON COLUMN components.component IS 'Component name';


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
);

COMMENT ON TABLE suite_architectures IS 'Archive components in use by suite';
COMMENT ON COLUMN suite_architectures.suitenick IS 'Suite name (nickname)';
COMMENT ON COLUMN suite_architectures.architecture IS 'Architecture name';


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
);

COMMENT ON TABLE suite_components IS 'Archive components in use by suite';
COMMENT ON COLUMN suite_components.suitenick IS 'Suite name (nickname)';
COMMENT ON COLUMN suite_components.component IS 'Component name';


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
);

COMMENT ON TABLE suite_source_detail IS 'List of architectures in each suite';
COMMENT ON COLUMN suite_source_detail.suitenick IS 'Suite name (nickname)';
COMMENT ON COLUMN suite_source_detail.component IS 'Component name';
COMMENT ON COLUMN suite_source_detail.build IS 'Fetch sources from this suite/component?';
COMMENT ON COLUMN suite_source_detail.sha256 IS 'SHA256 of latest Sources merge';


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
);

COMMENT ON TABLE suite_binary_detail IS 'List of architectures in each suite';
COMMENT ON COLUMN suite_binary_detail.suitenick IS 'Suite name (nickname)';
COMMENT ON COLUMN suite_binary_detail.architecture IS 'Architecture name';
COMMENT ON COLUMN suite_binary_detail.component IS 'Component name';
COMMENT ON COLUMN suite_binary_detail.build IS 'Build packages from this suite/architecture/component?';
COMMENT ON COLUMN suite_binary_detail.sha256 IS 'SHA256 of latest Packages merge';


CREATE TABLE package_types (
	type text
	  CONSTRAINT pkg_tpe_pkey PRIMARY KEY
);

COMMENT ON TABLE package_types IS 'Valid types for binary packages';
COMMENT ON COLUMN package_types.type IS 'Type name';


CREATE TABLE binary_architectures (
	architecture text
	  CONSTRAINT binary_arch_pkey PRIMARY KEY
);

COMMENT ON TABLE binary_architectures IS 'Possible values for the Architecture field in binary packages';
COMMENT ON COLUMN binary_architectures.arch IS 'Architecture name';


CREATE TABLE package_priorities (
	priority text
	  CONSTRAINT pkg_priority_pkey PRIMARY KEY,
	priority_value integer
	  DEFAULT 0
);

COMMENT ON TABLE package_priorities IS 'Valid package priorities';
COMMENT ON COLUMN package_priorities.priority IS 'Priority name';
COMMENT ON COLUMN package_priorities.priority_value IS 'Integer value for sorting priorities';


CREATE TABLE package_sections (
        section text
          CONSTRAINT pkg_sect_pkey PRIMARY KEY
);

COMMENT ON TABLE package_sections IS 'Valid package sections';
COMMENT ON COLUMN package_sections.section IS 'Section name';


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
);

CREATE INDEX sources_pkg_idx ON sources (source_package);

COMMENT ON TABLE sources IS 'Source packages common to all architectures (from Sources)';
COMMENT ON COLUMN sources.source_package IS 'Package name';
COMMENT ON COLUMN sources.source_version IS 'Package version number';
COMMENT ON COLUMN sources.component IS 'Archive component';
COMMENT ON COLUMN sources.section IS 'Package section';
COMMENT ON COLUMN sources.priority IS 'Package priority';
COMMENT ON COLUMN sources.maintainer IS 'Package maintainer';
COMMENT ON COLUMN sources.maintainer IS 'Package uploaders';
COMMENT ON COLUMN sources.build_dep IS 'Package build dependencies (architecture dependent)';
COMMENT ON COLUMN sources.build_dep_indep IS 'Package build dependencies (architecture independent)';
COMMENT ON COLUMN sources.build_confl IS 'Package build conflicts (architecture dependent)';
COMMENT ON COLUMN sources.build_confl_indep IS 'Package build conflicts (architecture independent)';
COMMENT ON COLUMN sources.stdver IS 'Debian Standards (policy) version number';


CREATE TABLE source_architectures (
	architecture text
	  CONSTRAINT source_arch_pkey PRIMARY KEY
);

COMMENT ON TABLE source_architectures IS 'Possible values for the Architecture field in sources';
COMMENT ON COLUMN source_architectures.architecture IS 'Architecture name';


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
);

COMMENT ON TABLE source_package_architectures IS 'Source package architectures (from Sources)';
COMMENT ON COLUMN source_package_architectures.source_package IS 'Package name';
COMMENT ON COLUMN source_package_architectures.source_version IS 'Package version number';
COMMENT ON COLUMN source_package_architectures.architecture IS 'Architecture name';


CREATE TABLE binaries (
	-- PostgreSQL won't allow "binary" as column name
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
);

COMMENT ON TABLE binaries IS 'Binary packages specific to single architectures (from Packages)';
COMMENT ON COLUMN binaries.binary_package IS 'Binary package name';
COMMENT ON COLUMN binaries.binary_version IS 'Binary package version number';
COMMENT ON COLUMN binaries.architecture IS 'Architecture name';
COMMENT ON COLUMN binaries.source_package IS 'Source package name';
COMMENT ON COLUMN binaries.source_version IS 'Source package version number';
COMMENT ON COLUMN binaries.section IS 'Package section';
COMMENT ON COLUMN binaries.type IS 'Package type (e.g. deb, udeb)';
COMMENT ON COLUMN binaries.priority IS 'Package priority';
COMMENT ON COLUMN binaries.installed_size IS 'Size of installed package (KiB, rounded up)';
COMMENT ON COLUMN binaries.multi_arch IS 'Multiple architecture co-installation behaviour';
COMMENT ON COLUMN binaries.essential IS 'Package is essential';
COMMENT ON COLUMN binaries.build_essential IS 'Package is essential for building';
COMMENT ON COLUMN binaries.pre_depends IS 'Package pre-dependencies';
COMMENT ON COLUMN binaries.depends IS 'Package dependencies';
COMMENT ON COLUMN binaries.recommends IS 'Package recommendations';
COMMENT ON COLUMN binaries.suggests IS 'Package suggestions';
COMMENT ON COLUMN binaries.conflicts IS 'Package conflicts with other packages';
COMMENT ON COLUMN binaries.breaks IS 'Package breaks other packages';
COMMENT ON COLUMN binaries.enhances IS 'Package enhances other packages';
COMMENT ON COLUMN binaries.replaces IS 'Package replaces other packages';
COMMENT ON COLUMN binaries.provides IS 'Package provides other packages';


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
);

CREATE INDEX suite_sources_src_ver_idx ON suite_sources (source_package, source_version);

COMMENT ON TABLE suite_sources IS 'Source packages contained within a suite';
COMMENT ON COLUMN suite_sources.source_package IS 'Source package name';
COMMENT ON COLUMN suite_sources.source_version IS 'Source package version number';
COMMENT ON COLUMN suite_sources.suite IS 'Suite name';
COMMENT ON COLUMN suite_sources.component IS 'Suite component';


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
);

CREATE INDEX suite_binaries_pkg_ver_idx ON suite_binaries (binary_package, binary_version);

COMMENT ON TABLE suite_binaries IS 'Binary packages contained within a suite';
COMMENT ON COLUMN suite_binaries.binary_package IS 'Binary package name';
COMMENT ON COLUMN suite_binaries.binary_version IS 'Binary package version number';
COMMENT ON COLUMN suite_binaries.architecture IS 'Architecture name';
COMMENT ON COLUMN suite_binaries.suite IS 'Suite name';
COMMENT ON COLUMN suite_binaries.component IS 'Suite component';
