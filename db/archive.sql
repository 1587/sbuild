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
	validuntil timestamp with time zone NOT NULL,
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
LANGUAGE plpgsql;


CREATE TABLE architectures (
	architecture text
	  CONSTRAINT arch_pkey PRIMARY KEY
);

COMMENT ON TABLE architectures IS 'Architectures in use';
COMMENT ON COLUMN architectures.architecture IS 'Architecture name';

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
LANGUAGE plpgsql;


CREATE TABLE components (
	component text
	  CONSTRAINT components_pkey PRIMARY KEY
);

COMMENT ON TABLE components IS 'Archive components in use';
COMMENT ON COLUMN components.component IS 'Component name';

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
LANGUAGE plpgsql;

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
LANGUAGE plpgsql;

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
LANGUAGE plpgsql;


CREATE TABLE suite_detail (
	suitenick text
	  NOT NULL,
	architecture text
	  NOT NULL,
	component text
	  NOT NULL,
	build bool
	  NOT NULL
	  DEFAULT false,
	CONSTRAINT suite_detail_pkey
	  PRIMARY KEY (suitenick, architecture, component),
	CONSTRAINT suite_detail_arch_fkey FOREIGN KEY (suitenick, architecture)
	  REFERENCES suite_architectures (suitenick, architecture),
	CONSTRAINT suite_detail_component_fkey FOREIGN KEY (suitenick, component)
	  REFERENCES suite_components (suitenick, component)
);

COMMENT ON TABLE suite_detail IS 'List of architectures in each suite';
COMMENT ON COLUMN suite_detail.suitenick IS 'Suite name (nickname)';
COMMENT ON COLUMN suite_detail.architecture IS 'Architecture name';
COMMENT ON COLUMN suite_detail.component IS 'Component name';
COMMENT ON COLUMN suite_detail.build IS 'Build packages from this suite/architecture/component?';

CREATE OR REPLACE FUNCTION merge_suite_detail(nsuitenick text,
                                              narchitecture text,
					      ncomponent text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        PERFORM merge_suite_architecture(nsuitenick, narchitecture);
	PERFORM merge_suite_component(nsuitenick, ncomponent);

        -- first try to update the key
        PERFORM suitenick, architecture, component FROM suite_detail WHERE suitenick = nsuitenick AND architecture = narchitecture AND component = ncomponent;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO suite_detail (suitenick, architecture, component) VALUES (nsuitenick, narchitecture, ncomponent);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;

CREATE TABLE package_types (
	type text
	  CONSTRAINT pkg_tpe_pkey PRIMARY KEY
);

COMMENT ON TABLE package_types IS 'Valid types for binary packages';
COMMENT ON COLUMN package_types.type IS 'Type name';


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
LANGUAGE plpgsql;


CREATE TABLE binary_architectures (
	architecture text
	  CONSTRAINT binary_arch_pkey PRIMARY KEY
);

COMMENT ON TABLE binary_architectures IS 'Possible values for the Architecture field in binary packages';
COMMENT ON COLUMN binary_architectures.arch IS 'Architecture name';

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
LANGUAGE plpgsql;

CREATE TABLE package_priorities (
	priority text
	  CONSTRAINT pkg_priority_pkey PRIMARY KEY,
	priority_value integer
	  DEFAULT 0
);

COMMENT ON TABLE package_priorities IS 'Valid package priorities';
COMMENT ON COLUMN package_priorities.priority IS 'Priority name';
COMMENT ON COLUMN package_priorities.priority_value IS 'Integer value for sorting priorities';

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
LANGUAGE plpgsql;

CREATE TABLE package_sections (
        section text
          CONSTRAINT pkg_sect_pkey PRIMARY KEY
);

COMMENT ON TABLE package_sections IS 'Valid package sections';
COMMENT ON COLUMN package_sections.section IS 'Section name';

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
LANGUAGE plpgsql;

CREATE TABLE sources (
	source text
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
	CONSTRAINT sources_pkey PRIMARY KEY (source, source_version)
);

CREATE INDEX sources_pkg_idx ON sources (source);

COMMENT ON TABLE sources IS 'Source packages common to all architectures (from Sources)';
COMMENT ON COLUMN sources.source IS 'Package name';
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

CREATE OR REPLACE FUNCTION merge_sources(nsuite text,
					 ncomponent text)
RETURNS VOID AS
$$
BEGIN
    CREATE TEMPORARY TABLE tmp_sources (LIKE sources);

    INSERT INTO tmp_sources
    SELECT * FROM new_sources;

    -- Move into main table.
    INSERT INTO sources
    SELECT * FROM tmp_sources
    WHERE (source,source_version) IN
      (SELECT source, source_version FROM tmp_sources AS s
       EXCEPT
       SELECT source, source_version FROM sources AS s);

    --  Remove old suite-source mappings.
    DELETE FROM suite_sources AS s
    WHERE s.suite = nsuite and s.component = ncomponent;

    -- Create new suite-source mappings.
    INSERT INTO suite_sources (source, source_version, suite, component)
    SELECT s.source, s.source_version, nsuite AS suite, ncomponent AS component
    FROM tmp_sources AS s;

    DELETE FROM tmp_sources
    WHERE (source, source_version) IN
      (SELECT source, source_version FROM tmp_sources AS s
       EXCEPT
       SELECT source, source_version FROM sources AS s);

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
    WHERE s.source=n.source AND s.source_version=n.source_version;

    DROP TABLE tmp_sources;
EXCEPTION
    DROP TABLE tmp_sources;
END;
$$
LANGUAGE plpgsql;

-- Add dummy source package for binaries lacking sources.
CREATE OR REPLACE FUNCTION merge_dummy_source(nsource text,
                                              nsource_version debversion)
RETURNS VOID AS
$$
BEGIN
    LOOP
        -- first try to update the key
        PERFORM source, source_version FROM sources
	WHERE source=nsource AND source_version=nsource_version;

        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO sources (source, source_version, component, section, priority, maintainer) VALUES (nsource, nsource_version, 'INVALID', 'INVALID', 'INVALID', 'INVALID');
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;

CREATE TABLE source_architectures (
	arch text
	  CONSTRAINT source_arch_pkey PRIMARY KEY
);

COMMENT ON TABLE source_architectures IS 'Possible values for the Architecture field in sources';
COMMENT ON COLUMN source_architectures.arch IS 'Architecture name';

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
LANGUAGE plpgsql;

CREATE TABLE source_package_architectures (
       	source text
	  NOT NULL,
	source_version debversion
	  NOT NULL,
	arch text
	  CONSTRAINT source_arch_arch_fkey
	  REFERENCES source_architectures(arch)
	  NOT NULL,
	UNIQUE (source, source_version, arch),
	CONSTRAINT source_arch_source_fkey FOREIGN KEY (source, source_version)
	  REFERENCES sources (source, source_version)
	  ON DELETE CASCADE
);

COMMENT ON TABLE source_package_architectures IS 'Source package architectures (from Sources)';
COMMENT ON COLUMN source_package_architectures.source IS 'Package name';
COMMENT ON COLUMN source_package_architectures.source_version IS 'Package version number';
COMMENT ON COLUMN source_package_architectures.arch IS 'Architecture name';

CREATE TABLE binaries (
	-- PostgreSQL won't allow "binary" as column name
	package text NOT NULL,
	version debversion NOT NULL,
	arch text
	  CONSTRAINT bin_arch_fkey REFERENCES binary_architectures(architecture)
	  NOT NULL,
	source text
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
	CONSTRAINT binaries_pkey PRIMARY KEY (package, version, arch),
	CONSTRAINT binaries_source_fkey FOREIGN KEY (source, source_version)
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

CREATE OR REPLACE FUNCTION merge_binary(npackage text,
                                        nversion debversion,
					narchitecture text,
					nsource text,
					nsource_version debversion,
					nsection text,
					ntype text,
					npriority text,
					ninstalled_size integer,
					nmulti_arch text,
					nessential boolean,
					nbuild_essential boolean,
					npre_depends text,
					ndepends text,
					nrecommends text,
					nsuggests text,
					nconflicts text,
					nbreaks text,
					nenhances text,
					nreplaces text,
					nprovides text)
RETURNS VOID AS
$$
BEGIN
    LOOP
        PERFORM merge_dummy_source(nsource, nsource_version);
        PERFORM merge_architecture(narchitecture);
        PERFORM merge_package_section(nsection);
        PERFORM merge_package_type(ntype);
        IF npriority IS NOT NULL THEN
            PERFORM merge_package_priority(npriority);
	END IF;

        -- first try to update the key
        UPDATE binaries
	SET arch=narchitecture,
	    source=nsource,
	    source_version=nsource_version,
	    section=nsection,
	    type=ntype,
	    priority=npriority,
	    installed_size=ninstalled_size,
	    multi_arch=nmulti_arch,
	    essential=nessential,
	    build_essential=nbuild_essential,
	    pre_depends=npre_depends,
	    depends=ndepends,
	    recommends=nrecommends,
	    suggests=nsuggests,
	    conflicts=nconflicts,
	    breaks=nbreaks,
	    enhances=nenhances,
	    replaces=nreplaces,
	    provides=nprovides
	WHERE package=npackage AND version=version;

        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
	    INSERT INTO binaries (
	        package,
		version,
		arch,
	    	source,
	    	source_version,
	    	section,
	    	type,
	    	priority,
	    	installed_size,
	    	multi_arch,
	    	essential,
	    	build_essential,
	    	pre_depends,
	    	depends,
	    	recommends,
	    	suggests,
	    	conflicts,
	    	breaks,
	    	enhances,
	    	replaces,
	    	provides)
	    VALUES (
	        npackage,
		nversion,
	        narchitecture,
		nsource,
		nsource_version,
		nsection,
		ntype,
		npriority,
		ninstalled_size,
		nmulti_arch,
		nessential,
		nbuild_essential,
		npre_depends,
		ndepends,
		nrecommends,
		nsuggests,
		nconflicts,
		nbreaks,
		nenhances,
		nreplaces,
		nprovides);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;

CREATE TABLE suite_sources (
	source text
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
	CONSTRAINT suite_sources_pkey PRIMARY KEY (source, suite, component),
	CONSTRAINT suite_sources_src_fkey FOREIGN KEY (source, source_version)
	  REFERENCES sources (source, source_version)
	  ON DELETE CASCADE,
	CONSTRAINT suite_sources_suitecomp_fkey FOREIGN KEY (suite, component)
	  REFERENCES suite_components (suitenick, component)
	  ON DELETE CASCADE
);

CREATE INDEX suite_sources_src_ver_idx ON suite_sources (source, source_version);

COMMENT ON TABLE suite_sources IS 'Source packages contained within a suite';
COMMENT ON COLUMN suite_sources.source IS 'Source package name';
COMMENT ON COLUMN suite_sources.source_version IS 'Source package version number';
COMMENT ON COLUMN suite_sources.suite IS 'Suite name';
COMMENT ON COLUMN suite_sources.component IS 'Suite component';

CREATE TABLE suite_binaries (
	package text
	  NOT NULL,
	version debversion
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
	CONSTRAINT suite_bin_pkey PRIMARY KEY (package, architecture, suite),
	CONSTRAINT suite_bin_bin_fkey FOREIGN KEY (package, version, architecture)
	  REFERENCES binaries (package, version, architecture)
	  ON DELETE CASCADE,
	CONSTRAINT suite_bin_suite_arch_fkey FOREIGN KEY (suite, architecture)
	  REFERENCES suite_arches (suite, architecture)
	  ON DELETE CASCADE
);

CREATE INDEX suite_binaries_pkg_ver_idx ON suite_binaries (package, version);

COMMENT ON TABLE suite_binaries IS 'Binary packages contained within a suite';
COMMENT ON COLUMN suite_binaries.package IS 'Binary package name';
COMMENT ON COLUMN suite_binaries.version IS 'Binary package version number';
COMMENT ON COLUMN suite_binaries.architecture IS 'Architecture name';
COMMENT ON COLUMN suite_binaries.suite IS 'Suite name';
COMMENT ON COLUMN suite_binaries.component IS 'Suite component';
