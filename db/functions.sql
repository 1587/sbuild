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
LANGUAGE plpgsql;

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
LANGUAGE plpgsql;


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


CREATE OR REPLACE FUNCTION merge_sources(nsuite text,
					 ncomponent text,
					 nsha256 text)
RETURNS VOID AS
$$
BEGIN
    CREATE TEMPORARY TABLE tmp_sources (LIKE sources);

    INSERT INTO tmp_sources
    SELECT * FROM new_sources;

    -- Move into main table.
    INSERT INTO sources
    SELECT * FROM tmp_sources
    WHERE (source, source_version) IN
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


CREATE OR REPLACE FUNCTION merge_binaries(nsuite text,
					  ncomponent text,
					  narchitecture text,
					  nsha256 text)
RETURNS VOID AS
$$
BEGIN
    CREATE TEMPORARY TABLE tmp_binaries (LIKE binaries);

    INSERT INTO tmp_binaries
    SELECT * FROM new_binaries;

    -- Move into main table.
    INSERT INTO binaries
    SELECT * FROM tmp_binaries
    WHERE (package, version) IN
      (SELECT package, version FROM tmp_binaries AS s
         WHERE (s.architecture = narchitecture OR
	        s.architecture = 'all')
       EXCEPT
       SELECT package, version FROM binaries AS s
         WHERE (s.architecture = narchitecture OR
	        s.architecture = 'all'));

    --  Remove old suite-binary mappings.
    DELETE FROM suite_binaries AS s
    WHERE s.suite = nsuite AND s.component = ncomponent AND (s.architecture = narchitecture OR s.architecture = 'all');

    -- Create new suite-binary mappings.
    INSERT INTO suite_binaries (package, version, suite, component, architecture)
    SELECT s.package AS package, s.version AS version, nsuite AS suite, ncomponent AS component, s.architecture AS architecture
    FROM tmp_binaries AS s;

    DELETE FROM tmp_binaries
    WHERE (package, version) IN
      (SELECT package, version FROM tmp_binaries AS s
       EXCEPT
       SELECT package, version FROM binaries AS s);

    UPDATE binaries AS s
    SET
      source=n.source,
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
    WHERE s.package=n.package AND s.version=n.version AND s.architecture=n.architecture;

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
LANGUAGE plpgsql;


--
-- Triggers to insert missing sections and priorities
--

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
$fkey_deps$ LANGUAGE plpgsql;
COMMENT ON FUNCTION source_fkey_deps ()
  IS 'Check foreign key references exist';

CREATE TRIGGER source_fkey_deps BEFORE INSERT OR UPDATE ON sources
  FOR EACH ROW EXECUTE PROCEDURE source_fkey_deps();
COMMENT ON TRIGGER source_fkey_deps ON sources
  IS 'Check foreign key references exist';

CREATE OR REPLACE FUNCTION binary_fkey_deps () RETURNS trigger AS $fkey_deps$
BEGIN
    IF NEW.source IS NOT NULL AND NEW.source_version IS NOT NULL THEN
        PERFORM merge_dummy_source(NEW.source, NEW.source_version);
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
$fkey_deps$ LANGUAGE plpgsql;
COMMENT ON FUNCTION binary_fkey_deps ()
  IS 'Check foreign key references exist';

CREATE TRIGGER binary_fkey_deps BEFORE INSERT OR UPDATE ON binaries
  FOR EACH ROW EXECUTE PROCEDURE binary_fkey_deps();
COMMENT ON TRIGGER binary_fkey_deps ON binaries
  IS 'Check foreign key references exist';




--
-- Triggers to insert missing package architectures
--

CREATE OR REPLACE FUNCTION package_check_arch() RETURNS trigger AS $package_check_arch$
BEGIN
  PERFORM arch FROM package_architectures WHERE (arch = NEW.arch);
  IF FOUND = 'f' THEN
    INSERT INTO package_architectures (arch) VALUES (NEW.arch);
  END IF;
  RETURN NEW;
END;
$package_check_arch$ LANGUAGE plpgsql;

COMMENT ON FUNCTION package_check_arch ()
  IS 'Insert missing values into package_architectures (from NEW.arch)';

CREATE TRIGGER check_arch BEFORE INSERT OR UPDATE ON source_architectures
  FOR EACH ROW EXECUTE PROCEDURE package_check_arch();
COMMENT ON TRIGGER check_arch ON source_architectures
  IS 'Ensure foreign key references (arch) exist';

CREATE TRIGGER check_arch BEFORE INSERT OR UPDATE ON binaries
  FOR EACH ROW EXECUTE PROCEDURE package_check_arch();
COMMENT ON TRIGGER check_arch ON binaries
  IS 'Ensure foreign key references (arch) exist';

-- Triggers on build_status:
--   - unconditionally update ctime
--   - verify bin_nmu is a positive integer (and change 0 to NULL)
--   - insert a record into status_history for every change in build_status

CREATE OR REPLACE FUNCTION set_ctime()
RETURNS trigger AS $set_ctime$
BEGIN
  NEW.ctime = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$set_ctime$ LANGUAGE plpgsql;

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
$check_bin_nmu_number$ LANGUAGE plpgsql;

CREATE TRIGGER check_bin_nmu BEFORE INSERT OR UPDATE ON build_status
  FOR EACH ROW EXECUTE PROCEDURE check_bin_nmu_number();
COMMENT ON TRIGGER check_bin_nmu ON build_status
  IS 'Ensure "bin_nmu" is a positive integer, or set it to NULL if 0';

CREATE TRIGGER set_or_update_ctime BEFORE INSERT OR UPDATE ON build_status
  FOR EACH ROW EXECUTE PROCEDURE set_ctime();
COMMENT ON TRIGGER set_or_update_ctime ON build_status
  IS 'Set or update the "ctime" column to now()';

CREATE OR REPLACE FUNCTION update_status_history()
RETURNS trigger AS $update_status_history$
BEGIN
  INSERT INTO build_status_history
    (source, source_version, arch, suite,
     bin_nmu, user_name, builder, status, ctime)
    VALUES
      (NEW.source, NEW.source_version, NEW.arch, NEW.suite,
       NEW.bin_nmu, NEW.user_name, NEW.builder, NEW.status, NEW.ctime);
  RETURN NULL;
END;
$update_status_history$ LANGUAGE plpgsql;

CREATE TRIGGER update_history AFTER INSERT OR UPDATE ON build_status
  FOR EACH ROW EXECUTE PROCEDURE update_status_history();
COMMENT ON TRIGGER update_history ON build_status
  IS 'Insert a record of the status change into build_status_history';
