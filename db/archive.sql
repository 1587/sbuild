--- Debian Source Builder: Database Schema for PostgreSQL            -*- sql -*-
---
--- Copyright © 2008-2009 Roger Leigh <rleigh@debian.org>
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
	uri text NOT NULL,
	distribution text NOT NULL
);

COMMENT ON TABLE suites IS 'Valid suites';
COMMENT ON COLUMN suites.suitenick IS 'Name used to reference a suite (nickname)';
COMMENT ON COLUMN suites.uri IS 'URI to fetch from';
COMMENT ON COLUMN suites.distribution IS 'Distribution name (used in combinatino
 with URI)';

CREATE TABLE suite_release (
        suitenick text
	  CONSTRAINT suite_release_suitenick_fkey
	  REFERENCES suites(suitenick)
	    ON DELETE CASCADE,
	suite text NOT NULL,
	codename text NOT NULL,
	version debversion,
	origin text NOT NULL,
	label text NOT NULL,
	date timestamp with time zone NOT NULL,
	validuntil timestamp with time zone NOT NULL,
-- Old wanna-build options
	priority integer
	  DEFAULT 10,
	depwait boolean
	  DEFAULT 't',
	hidden boolean
	  DEFAULT 'f'
);

COMMENT ON TABLE suite_release IS 'Suite release details';
COMMENT ON COLUMN suite_release.suitenick IS 'Suite name (nickname)';
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

CREATE TABLE suite_detail (
	suitenick text
	  NOT NULL
	  CONSTRAINT suite_detail_suite_fkey
	  REFERENCES suites(suitenick)
	    ON DELETE CASCADE,
	architecture text
	  NOT NULL
	  CONSTRAINT suite_detail_architecture_fkey
	    REFERENCES architectures(architecture),
	component text
	  NOT NULL
	  CONSTRAINT suite_detail_component_fkey
	    REFERENCES components(component),
	CONSTRAINT suite_detail_pkey
	  PRIMARY KEY (suite, architecture, component),
	build bool
	  NOT NULL
	  DEFAULT false
);

COMMENT ON TABLE suite_detail IS 'List of architectures in each suite';
COMMENT ON COLUMN suite_detail.suitenick IS 'Suite name (nickname)';
COMMENT ON COLUMN suite_detail.architecture IS 'Architecture name';
COMMENT ON COLUMN suite_detail.component IS 'Component name';
COMMENT ON COLUMN suite_detail.build IS 'Build packages from this suite/architecture/component?';

CREATE TABLE package_types (
	type text
	  CONSTRAINT pkg_tpe_pkey PRIMARY KEY
);

COMMENT ON TABLE package_types IS 'Valid types for binary packages';
COMMENT ON COLUMN package_types.type IS 'Type name';

CREATE TABLE package_architectures (
	arch text
	  CONSTRAINT pkg_arch_pkey PRIMARY KEY
);

COMMENT ON TABLE package_architectures IS 'Possible values for the Architecture field';
COMMENT ON COLUMN package_architectures.arch IS 'Architecture name';

CREATE TABLE package_priorities (
	pkg_prio text
	  CONSTRAINT pkg_pri_pkey PRIMARY KEY,
	prio_val integer
	  DEFAULT 0
);

COMMENT ON TABLE package_priorities IS 'Valid package priorities';
COMMENT ON COLUMN package_priorities.pkg_prio IS 'Priority name';
COMMENT ON COLUMN package_priorities.prio_val IS 'Integer value for sorting priorities';

CREATE TABLE package_sections (
        section text
          CONSTRAINT pkg_sect_pkey PRIMARY KEY
);

COMMENT ON TABLE package_sections IS 'Valid package sections';
COMMENT ON COLUMN package_sections.section IS 'Section name';

CREATE TABLE sources (
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	component text
	  CONSTRAINT source_comp_fkey REFERENCES components(component)
	  ON DELETE CASCADE
	  NOT NULL,
	section text
	  CONSTRAINT source_section_fkey REFERENCES package_sections(section)
	  NOT NULL,
	pkg_prio text
	  CONSTRAINT source_pkg_prio_fkey REFERENCES package_priorities(pkg_prio)
	  NOT NULL,
	maintainer text NOT NULL,
	build_dep text,
	build_dep_indep text,
	build_confl text,
	build_confl_indep text,
	stdver text,
	CONSTRAINT sources_pkey PRIMARY KEY (source, source_version)
);

CREATE INDEX sources_pkg_idx ON sources (source);

COMMENT ON TABLE sources IS 'Source packages common to all architectures (from Sources)';
COMMENT ON COLUMN sources.source IS 'Package name';
COMMENT ON COLUMN sources.source_version IS 'Package version number';
COMMENT ON COLUMN sources.component IS 'Archive component';
COMMENT ON COLUMN sources.section IS 'Package section';
COMMENT ON COLUMN sources.pkg_prio IS 'Package priority';
COMMENT ON COLUMN sources.maintainer IS 'Package maintainer name';
COMMENT ON COLUMN sources.build_dep IS 'Package build dependencies (architecture dependent)';
COMMENT ON COLUMN sources.build_dep_indep IS 'Package build dependencies (architecture independent)';
COMMENT ON COLUMN sources.build_confl IS 'Package build conflicts (architecture dependent)';
COMMENT ON COLUMN sources.build_confl_indep IS 'Package build conflicts (architecture independent)';
COMMENT ON COLUMN sources.stdver IS 'Debian Standards (policy) version number';

CREATE TABLE source_architectures (
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	arch text
	  CONSTRAINT source_arch_arch_fkey
	  REFERENCES package_architectures(arch)
	  ON DELETE CASCADE
	  NOT NULL,
	UNIQUE (source, source_version, arch),
	CONSTRAINT source_arch_source_fkey FOREIGN KEY (source, source_version)
	  REFERENCES sources (source, source_version)
	  ON DELETE CASCADE
);

COMMENT ON TABLE source_architectures IS 'Source package architectures (from Sources)';
COMMENT ON COLUMN source_architectures.source IS 'Package name';
COMMENT ON COLUMN source_architectures.source_version IS 'Package version number';
COMMENT ON COLUMN source_architectures.arch IS 'Architecture name';

CREATE TABLE uploaders (
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	uploader text
	  NOT NULL,
	UNIQUE (source, source_version, uploader),
	CONSTRAINT uploader_source_fkey FOREIGN KEY (source, source_version)
	  REFERENCES sources (source, source_version)
	  ON DELETE CASCADE
);

COMMENT ON TABLE uploaders IS 'Uploader names for source packages';
COMMENT ON COLUMN uploaders.source IS 'Package name';
COMMENT ON COLUMN uploaders.source_version IS 'Package version number';
COMMENT ON COLUMN uploaders.uploader IS 'Uploader name and address';

CREATE TABLE binaries (
	-- PostgreSQL won't allow "binary" as column name
	package text NOT NULL,
	version debversion NOT NULL,
	arch text
	  CONSTRAINT bin_arch_fkey REFERENCES package_architectures(arch)
	  ON DELETE CASCADE
	  NOT NULL,
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	section text
	  CONSTRAINT bin_section_fkey REFERENCES package_sections(section)
	  NOT NULL,
	type text
	  CONSTRAINT bin_pkg_type_fkey REFERENCES package_types(type)
	  NOT NULL,
	pkg_prio text
	  CONSTRAINT bin_pkg_prio_fkey REFERENCES package_priorities(pkg_prio)
	  NOT NULL,
	CONSTRAINT bin_pkey PRIMARY KEY (package, version, arch),
	CONSTRAINT bin_src_fkey FOREIGN KEY (source, source_version)
	  REFERENCES sources (source, source_version)
	  ON DELETE CASCADE
);

COMMENT ON TABLE binaries IS 'Binary packages specific to single architectures (from Packages)';
COMMENT ON COLUMN binaries.package IS 'Binary package name';
COMMENT ON COLUMN binaries.version IS 'Binary package version number';
COMMENT ON COLUMN binaries.arch IS 'Architecture name';
COMMENT ON COLUMN binaries.source IS 'Source package name';
COMMENT ON COLUMN binaries.source_version IS 'Source package version number';
COMMENT ON COLUMN binaries.section IS 'Package section';
COMMENT ON COLUMN binaries.pkg_prio IS 'Package priority';

CREATE TABLE suite_sources (
	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	suite text
	  CONSTRAINT suite_sources_suite_fkey REFERENCES suites(suite)
	  ON DELETE CASCADE
	  NOT NULL,
	CONSTRAINT suite_sources_pkey PRIMARY KEY (source, suite),
	CONSTRAINT suite_sources_src_fkey FOREIGN KEY (source, source_version)
	  REFERENCES sources (source, source_version)
	  ON DELETE CASCADE
);

CREATE INDEX suite_sources_src_ver_idx ON suite_sources (source, source_version);

COMMENT ON TABLE suite_sources IS 'Source packages contained within a suite';
COMMENT ON COLUMN suite_sources.source IS 'Source package name';
COMMENT ON COLUMN suite_sources.source_version IS 'Source package version number';
COMMENT ON COLUMN suite_sources.suite IS 'Suite name';

CREATE TABLE suite_binaries (
	package text
	  NOT NULL,
	version debversion
	  NOT NULL,
	arch text
	  CONSTRAINT suite_bin_arch_fkey REFERENCES package_architectures(arch)
          ON DELETE CASCADE
	  NOT NULL,
	suite text
	  CONSTRAINT suite_bin_suite_fkey REFERENCES suites(suite)
          ON DELETE CASCADE
	  NOT NULL,
	CONSTRAINT suite_bin_pkey PRIMARY KEY (package, arch, suite),
	CONSTRAINT suite_bin_bin_fkey FOREIGN KEY (package, version, arch)
	  REFERENCES binaries (package, version, arch)
	  ON DELETE CASCADE,
	CONSTRAINT suite_bin_suite_arch_fkey FOREIGN KEY (suite, arch)
	  REFERENCES suite_arches (suite, arch)
	  ON DELETE CASCADE
);

CREATE INDEX suite_binaries_pkg_ver_idx ON suite_binaries (package, version);

COMMENT ON TABLE suite_binaries IS 'Binary packages contained within a suite';
COMMENT ON COLUMN suite_binaries.package IS 'Binary package name';
COMMENT ON COLUMN suite_binaries.version IS 'Binary package version number';
COMMENT ON COLUMN suite_binaries.arch IS 'Architecture name';
COMMENT ON COLUMN suite_binaries.suite IS 'Suite name';
