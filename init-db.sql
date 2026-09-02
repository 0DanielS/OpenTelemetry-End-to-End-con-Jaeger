CREATE DATABASE inventory;
CREATE USER inventory WITH PASSWORD 'inventory';
ALTER DATABASE inventory OWNER TO inventory;
CREATE USER dataservice WITH PASSWORD 'dataservice';
GRANT CONNECT ON DATABASE orders TO dataservice;
GRANT USAGE ON SCHEMA public TO dataservice;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dataservice;
ALTER DEFAULT PRIVILEGES FOR ROLE orders IN SCHEMA public GRANT SELECT ON TABLES TO dataservice;
