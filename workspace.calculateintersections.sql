-- FUNCTION: workspace.calculateintersections(text, text)

-- DROP FUNCTION workspace.calculateintersections(text, text);

CREATE OR REPLACE FUNCTION workspace.calculateintersections(
    countryname text,
    inputlayername text)
RETURNS boolean
LANGUAGE 'plpgsql'
COST 100
VOLATILE STRICT 
AS $BODY$
DECLARE  
    rol boolean;
    upd1_count integer;
    upd2_count integer; 
    segmentsNumber integer;
    numbersCities integer;
    tables CURSOR FOR
        SELECT ic.tid 
        FROM workspace.populatedcenters ic 
        WHERE ic.country = upper(cast(countryName as text))
        ORDER BY ic.tid; -- limit 100000;
BEGIN
    --select workspace.calculateintersections('col', 'nom_vial_urbana');
    --select count(*) from nom_vial_urbana

    -- Se crea la tabla que almacena los caminos por segmentos 
    DROP TABLE IF EXISTS workspace.segmentedroads;
    CREATE TABLE workspace.segmentedroads(
        id serial, 
        name character varying, 
        wkb_geometry geometry
    );

    -- Se crean los respectivos índices para mejorar el rendimiento en las consultas
    CREATE INDEX ON workspace.segmentedroads USING gist(wkb_geometry);
    CREATE INDEX roadseg_pkey ON workspace.segmentedroads USING btree(id);

    -- Inserta segmentos viales de interés en la nueva tabla
    EXECUTE 'INSERT INTO workspace.segmentedroads(name, wkb_geometry) 
             SELECT r.name, r.wkb_geometry
             FROM public.' || lower(cast(inputLayerName as text)) || ' r 
             INNER JOIN workspace.populatedcenters p
             ON st_intersects(r.wkb_geometry, p.wkb_geometry) 
             AND ST_DWithin(r.wkb_geometry, p.wkb_geometry, 0.000001) 
             AND r.new_pointsinter = 1 
             LIMIT 50';

    -- Actualiza la geometría de los segmentos
    UPDATE workspace.segmentedroads 
    SET wkb_geometry = ST_LineMerge(ST_SnapToGrid(wkb_geometry, 0.0000001));

    -- Calcula la orientación de la vía
    ALTER TABLE workspace.segmentedroads ADD COLUMN azimuth numeric;
    UPDATE workspace.segmentedroads 
    SET azimuth = round(degrees(ST_Azimuth(st_startpoint(wkb_geometry), st_endpoint(wkb_geometry)))::numeric, 3);

    -- Crea los campos que almacenarán los nombres al 25% y 75% del camino
    ALTER TABLE workspace.segmentedroads ADD COLUMN name_to_i25 character varying;
    ALTER TABLE workspace.segmentedroads ADD COLUMN name_to_i75 character varying;

    rol := true;

    -- Recorre cada centro poblado
    FOR table_record IN tables LOOP
        RAISE NOTICE '%', table_record.tid;

        -- Actualiza el nombre de la vía teniendo en cuenta el nombre de vía y su respectiva interceptora
        UPDATE workspace.segmentedroads t1 
        SET 
            name_to_i25 = upper((SELECT cast(countryName as text) || ' - ' || p.mpio_cnmbr || '(' || p.dpto_abrev || ') - ' || t1.name || ' CON ' || t2.name as namefull
                                FROM workspace.segmentedroads t2, workspace.populatedcenters p
                                WHERE t2.id <> t1.id 
                                  AND ST_DWithin(t2.wkb_geometry, st_startpoint(t1.wkb_geometry), 0.001)
                                  AND abs(t1.azimuth - t2.azimuth) > 30 
                                  AND st_intersects(t2.wkb_geometry, p.wkb_geometry)
                                  AND t2.name IS NOT NULL
                                  AND p.tid = table_record.tid
                                ORDER BY ST_Distance(st_centroid(t2.wkb_geometry), st_startpoint(t1.wkb_geometry)) 
                                LIMIT 1)),
            name_to_i75 = upper((SELECT cast(countryName as text) || ' - ' || p.mpio_cnmbr || '(' || p.dpto_abrev || ') - ' || t1.name || ' CON ' || t2.name as namefull
                                FROM workspace.segmentedroads t2, workspace.populatedcenters p 
                                WHERE t2.id <> t1.id 
                                  AND ST_DWithin(t2.wkb_geometry, st_endpoint(t1.wkb_geometry), 0.001)
                                  AND abs(t1.azimuth - t2.azimuth) > 30 
                                  AND st_intersects(t2.wkb_geometry, p.wkb_geometry)
                                  AND t2.name IS NOT NULL  
                                  AND p.tid = table_record.tid
                                ORDER BY ST_Distance(st_centroid(t2.wkb_geometry), st_endpoint(t1.wkb_geometry)) 
                                LIMIT 1))
        WHERE name_to_i25 IS NULL AND name_to_i75 IS NULL;

        GET DIAGNOSTICS upd1_count = ROW_COUNT;

        -- Actualiza el nombre de la vía teniendo en cuenta solo el nombre de la vía (caso en que no se encuentra vía interceptora)
        UPDATE workspace.segmentedroads t1 
        SET 
            name_to_i25 = upper(cast(countryName as text) || ' - ' || r.populatedname || ' - ' || t1.name),   
            name_to_i75 = upper(cast(countryName as text) || ' - ' || r.populatedname || ' - ' || t1.name)   
        FROM
        (SELECT t2.id, p.nom_cpob AS populatedname   
         FROM workspace.segmentedroads t2, workspace.populatedcenters p 
         WHERE st_intersects(t2.wkb_geometry, p.wkb_geometry)
           AND t2.name IS NOT NULL  
           AND p.tid = table_record.tid
        ) r
        WHERE (t1.name_to_i25 IS NULL OR t1.name_to_i75 IS NULL) AND t1.id = r.id;

        GET DIAGNOSTICS upd2_count = ROW_COUNT;

        RAISE NOTICE 'The rows affected by A=% and B=%', upd1_count, upd2_count;
    END LOOP;

    -- Se crea una tabla que almacena intersecciones para las áreas geográficas o centros poblados ingresados
    DROP TABLE IF EXISTS workspace.intersections;
    CREATE TABLE workspace.intersections(
        id serial, 
        wkb_geometry geometry, 
        name character varying
    ); 

    CREATE INDEX ON workspace.intersections USING gist(wkb_geometry);

    INSERT INTO workspace.intersections(wkb_geometry, name)
    SELECT ST_LineInterpolatePoint(wkb_geometry, 0.25) AS geom, name_to_i25
    FROM workspace.segmentedroads
    UNION
    SELECT ST_LineInterpolatePoint(wkb_geometry, 0.75), name_to_i75
    FROM workspace.segmentedroads;

    RETURN rol;
END;
$BODY$;

ALTER FUNCTION workspace.calculateintersections(text, text)
    OWNER TO postgres;
