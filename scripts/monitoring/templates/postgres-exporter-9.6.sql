\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION __tmp_create_monitoring_user() RETURNS void AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_user WHERE usename = 'prometheus_exporter'
  ) THEN
    CREATE USER prometheus_exporter;
  END IF;
END;
$$ LANGUAGE plpgsql;

SELECT __tmp_create_monitoring_user();
DROP FUNCTION __tmp_create_monitoring_user();

ALTER USER prometheus_exporter WITH
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION
  PASSWORD '__POSTGRES_EXPORTER_PASSWORD__';
ALTER USER prometheus_exporter
  SET SEARCH_PATH TO postgres_exporter,pg_catalog;
GRANT CONNECT ON DATABASE postgres TO prometheus_exporter;

CREATE SCHEMA IF NOT EXISTS postgres_exporter;
REVOKE ALL ON SCHEMA postgres_exporter FROM PUBLIC;
GRANT USAGE ON SCHEMA postgres_exporter TO prometheus_exporter;

CREATE OR REPLACE FUNCTION postgres_exporter.get_pg_stat_activity()
RETURNS SETOF pg_catalog.pg_stat_activity AS $$
  SELECT * FROM pg_catalog.pg_stat_activity;
$$ LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp;
REVOKE EXECUTE ON FUNCTION postgres_exporter.get_pg_stat_activity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION postgres_exporter.get_pg_stat_activity() TO prometheus_exporter;

CREATE OR REPLACE VIEW postgres_exporter.pg_stat_activity AS
  SELECT * FROM postgres_exporter.get_pg_stat_activity();
REVOKE ALL ON postgres_exporter.pg_stat_activity FROM PUBLIC;
GRANT SELECT ON postgres_exporter.pg_stat_activity TO prometheus_exporter;

CREATE OR REPLACE FUNCTION postgres_exporter.get_pg_stat_replication()
RETURNS SETOF pg_catalog.pg_stat_replication AS $$
  SELECT * FROM pg_catalog.pg_stat_replication;
$$ LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp;
REVOKE EXECUTE ON FUNCTION postgres_exporter.get_pg_stat_replication() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION postgres_exporter.get_pg_stat_replication() TO prometheus_exporter;

CREATE OR REPLACE VIEW postgres_exporter.pg_stat_replication AS
  SELECT * FROM postgres_exporter.get_pg_stat_replication();
REVOKE ALL ON postgres_exporter.pg_stat_replication FROM PUBLIC;
GRANT SELECT ON postgres_exporter.pg_stat_replication TO prometheus_exporter;
