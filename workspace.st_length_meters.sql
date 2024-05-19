-- FUNCTION: workspace.st_length_meters(geometry)

-- DROP FUNCTION workspace.st_length_meters(geometry);

CREATE OR REPLACE FUNCTION workspace.st_length_meters(
	geometry)
    RETURNS double precision
    LANGUAGE 'plpgsql'

    COST 100
    IMMUTABLE 
AS $BODY$

DECLARE
orig_srid int;
utm_srid int;
 
BEGIN
orig_srid:= ST_SRID($1);
utm_srid:= workspace.utmzone(ST_Centroid($1));
 
RETURN ST_Length(ST_transform($1, utm_srid));
END;

$BODY$;

ALTER FUNCTION workspace.st_length_meters(geometry)
    OWNER TO postgres;
