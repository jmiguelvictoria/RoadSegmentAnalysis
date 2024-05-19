-- FUNCTION: workspace.utmzone(geometry)

-- DROP FUNCTION workspace.utmzone(geometry);

CREATE OR REPLACE FUNCTION workspace.utmzone(
	geometry)
    RETURNS integer
    LANGUAGE 'plpgsql'

    COST 100
    IMMUTABLE 
AS $BODY$

DECLARE
geomgeog geometry;
zone int;
pref int;
 
BEGIN
geomgeog:= ST_Transform($1,4326);
 
IF (ST_Y(geomgeog))>0 THEN
pref:=32600;
ELSE
pref:=32700;
END IF;
 
zone:=floor((ST_X(geomgeog)+180)/6)+1;
 
RETURN zone+pref;
END;

$BODY$;

ALTER FUNCTION workspace.utmzone(geometry)
    OWNER TO postgres;
