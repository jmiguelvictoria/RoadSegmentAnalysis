-- FUNCTION: workspace.calculamileagepoint(text, text, text)

-- DROP FUNCTION workspace.calculamileagepoint(text, text, text);

CREATE OR REPLACE FUNCTION workspace.calculamileagepoint(
    distance text,
    mileagepointtype text,
    countryname text
)
    RETURNS boolean
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE STRICT 
AS $BODY$

DECLARE  
    rol boolean;
    segmentsNumber integer;
    roadCount integer;
BEGIN

    -- select workspace.calculamileagepoint('200', 'mileagepointNew','MEX');

    /**
    Se crea la tabla que almacena la nube de puntos de kilometraje 
    */
    DROP TABLE IF EXISTS workspace.mileagepoint;
    CREATE TABLE workspace.mileagepoint(
        gid serial primary key,
        road_gid integer,
        wkb_geometry geometry, 
        name character varying(500),
        lat double precision,
        lon double precision
    );

    -- creo indice espacial para mejorar el rendimiento de procesamiento en los calculos posteriores
    CREATE INDEX mileagepoint_gix ON workspace.mileagepoint USING GIST (wkb_geometry);

    -- inserto el primer punto de kilometraje para cada segmento de linea o ruta
    INSERT INTO workspace.mileagepoint (road_gid, wkb_geometry, lat, lon, name) 
    SELECT ogc_fid, st_startpoint(wkb_geometry), 
           st_y(st_startpoint(wkb_geometry)), 
           st_x(st_startpoint(wkb_geometry)), 
           regexp_replace(
               replace(
                   upper(
                       cast(countryname as text) || ' - ' || centropoblado1 || ' - ' || centropoblado2 ||
                       CASE 
                           WHEN mileagepointtype = 'mileagepointOld' THEN ' KM ( 1 - ' || long_km - 1 || ' )'
                           ELSE ' Km ( 0 - ' || long_km || ' )' 
                       END
                   ),
                   '  ', ' '
               ), 
               E'[\\n\\r]+', ' ', 'g'
           ) as name
    FROM workspace.layerofinterest;

    rol := true;
    roadCount := (SELECT count(id_wt) FROM workspace.layerofinterest);

    FOR k IN 1..roadCount LOOP  
        RAISE NOTICE '%', roadCount;
        segmentsNumber := (SELECT countpoints FROM workspace.layerofinterest WHERE id_wt = k);
        RAISE NOTICE '%', segmentsNumber;

        FOR i IN 1..segmentsNumber LOOP
            RAISE NOTICE '%', segmentsNumber;

            INSERT INTO workspace.mileagepoint (road_gid, wkb_geometry, lat, lon, name) (
                SELECT ogc_fid, 
                       ST_LineInterpolatePoint(ST_LineMerge(ST_SnapToGrid(wkb_geometry, 0.00001)), (cast(distance as integer) / workspace.ST_Length_Meters(wkb_geometry)) * i) as geom,
                       st_y(ST_LineInterpolatePoint(ST_LineMerge(ST_SnapToGrid(wkb_geometry, 0.00001)), (cast(distance as integer) / workspace.ST_Length_Meters(wkb_geometry)) * i)) as latitude,
                       st_x(ST_LineInterpolatePoint(ST_LineMerge(ST_SnapToGrid(wkb_geometry, 0.00001)), (cast(distance as integer) / workspace.ST_Length_Meters(wkb_geometry)) * i)) as longitude,            
                       regexp_replace(
                           replace(
                               upper(
                                   cast(countryname as text) || ' - ' || centropoblado1 || ' - ' || centropoblado2 || 
                                   CASE 
                                       WHEN mileagepointtype = 'mileagepointOld' THEN
                                           ' Km ( ' ||
                                           CASE 
                                               WHEN 1 + (cast(distance as integer) * i / 1000) > long_km THEN long_km
                                               ELSE 1 + (cast(distance as integer) * i / 1000) 
                                           END ||
                                           ' - ' ||
                                           CASE 
                                               WHEN (floor(((long_km) - (cast(distance as integer)) * i / 1000)::double precision) - 1) < 0 THEN '0'
                                               ELSE (floor(((long_km) - (cast(distance as integer)) * i / 1000)::double precision) - 1) 
                                           END || ' )'
                                       ELSE
                                           ' Km ( ' || (cast(distance as double precision) * i) / 1000 || ' - ' || round(((long_km) - (cast(distance as double precision) * i) / 1000)::numeric, 2) || ' )' 
                                   END
                               ),
                               '  ', ' '
                           ), 
                           E'[\\n\\r]+', ' ', 'g'
                       ) as name
                FROM workspace.layerofinterest 
                WHERE id_wt = k
            );
        END LOOP;
    END LOOP;

    RETURN rol;    
END;                 

$BODY$;

ALTER FUNCTION workspace.calculamileagepoint(text, text, text)
    OWNER TO postgres;
