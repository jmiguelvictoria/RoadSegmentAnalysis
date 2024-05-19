-- FUNCTION: workspace.calculate_adminzones_for_intersections(text)

-- DROP FUNCTION workspace.calculate_adminzones_for_intersections(text);

CREATE OR REPLACE FUNCTION workspace.calculate_adminzones_for_intersections(
    country text)
    RETURNS boolean
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE STRICT
AS $BODY$

DECLARE  
    rol boolean;
    nbRow int;

    tables CURSOR FOR
        SELECT ic.ogc_fid
        FROM public.intersections ic
        WHERE ic.country IS NULL
        ORDER BY ic.ogc_fid;

BEGIN
    COMMENT ON FUNCTION workspace.calculate_adminzones_for_intersections IS 'Esta funcion calcula el pais y el nivel administrativo despues del pais para los puntos de interseccion';

    -- select workspace.calculate_adminzones_for_intersections('COL');

    rol := false;

    FOR table_record IN tables LOOP
        -- RAISE NOTICE '%', table_record.ogc_fid;
        
        EXECUTE 'UPDATE public.intersections SET 
                    with_name = true, 
                    country = resp.country,
                    name_admin1 = resp.name1 
                FROM (SELECT 
                        i.ogc_fid AS ogc_fid_inter, 
                        admin1.iso AS country, 
                        admin1.name_1 AS name1 
                      FROM 
                        public.intersections i, 
                        public.countries_admin1 AS admin1
                      WHERE 
                        i.ogc_fid = ' || table_record.ogc_fid || '
                        AND ST_DWithin(i.wkb_geometry, admin1.wkb_geometry, 0.000005) 
                        AND ST_Intersects(i.wkb_geometry, admin1.wkb_geometry) 
                        AND (ST_GeometryType(i.wkb_geometry) = ''ST_Point'' OR ST_GeometryType(i.wkb_geometry) = ''ST_MultiPoint'')
                        AND i.ogc_fid = ' || table_record.ogc_fid || ') AS resp 
                WHERE public.intersections.ogc_fid = resp.ogc_fid_inter;';
        
        rol := true;
    END LOOP;

    RETURN rol;    
END;

$BODY$;

ALTER FUNCTION workspace.calculate_adminzones_for_intersections(text)
    OWNER TO postgres;
