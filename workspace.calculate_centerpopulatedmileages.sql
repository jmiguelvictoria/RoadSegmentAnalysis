-- FUNCTION: workspace.calculate_centerpopulatedmileages(text)

-- DROP FUNCTION workspace.calculate_centerpopulatedmileages(text);

CREATE OR REPLACE FUNCTION workspace.calculate_centerpopulatedmileages(
    countryname text)
    RETURNS boolean
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE STRICT
AS $BODY$

DECLARE  
    rol boolean;
BEGIN
    -- Verifica si pasar solo las líneas de kilometraje al cálculo si y solo si no tienen nombres
    EXECUTE 'UPDATE workspace.mileageline 
             SET calculated = false 
             WHERE st_geometrytype(wkb_geometry) = ''ST_LineString'' 
             AND (name IS NULL OR name = '''')';

    /* Obtiene el centro poblado de inicio de la ruta */
    EXECUTE 'UPDATE workspace.mileageline 
             SET name = resp.nom_cpob || '' ('' || resp.dpto_abrev || '') - '' 
             FROM (
                 SELECT c.nom_cpob, c.dpto_abrev, ml.ogc_fid 
                 FROM ' || cast(countryname as text) || '.populatedcenters c,
                      workspace.mileageline ml 
                 WHERE ST_DWithin(c.wkb_geometry, st_startpoint(ml.wkb_geometry), 0.005)
                 AND st_intersects(c.wkb_geometry, st_buffer(st_startpoint(ml.wkb_geometry), 0.003)) 
                 AND st_geometrytype(ml.wkb_geometry) = ''ST_LineString'' 
                 AND ml.calculated = false
                 AND (ml.name IS NULL OR ml.name = '''')
                 ORDER BY st_distance(ST_PointOnSurface(c.wkb_geometry), st_startpoint(ml.wkb_geometry)) ASC
             ) resp
             WHERE resp.ogc_fid = workspace.mileageline.ogc_fid 
             AND workspace.mileageline.calculated = false';

    /* Obtiene el centro poblado más cercano al inicio de la ruta (para líneas tipo cruce) */
    EXECUTE 'UPDATE workspace.mileageline 
             SET NAME = ''CRUCE '' || COALESCE(NULLIF(resp.namepoblado, NULL), ''NN'') || '' ('' || COALESCE(NULLIF(resp.dpto_abrev, NULL), ''NN'') || '') - '' 
             FROM (
                 SELECT DISTINCT(l.ogc_fid), (
                     SELECT (
                         SELECT c.nom_cpob
                         FROM (
                             SELECT cp.nom_cpob, cp.centroidgeom, cp.dpto_abrev, cp.wkb_geometry 
                             FROM ' || cast(countryname as text) || '.populatedcenters cp, workspace.mileageline lz 
                             WHERE l.ogc_fid <> lz.ogc_fid 
                             AND ST_DWithin(l.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(st_startpoint(l.wkb_geometry), 0.003))
                             AND ST_DWithin(cp.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(cp.wkb_geometry, 0.0009))
                         ) c  
                         ORDER BY st_startpoint(l.wkb_geometry) <#> c.centroidgeom LIMIT 1
                     )
                 ) namepoblado, (
                     SELECT (
                         SELECT c.dpto_abrev
                         FROM (
                             SELECT cp.dpto_abrev, cp.centroidgeom 
                             FROM ' || cast(countryname as text) || '.populatedcenters cp, workspace.mileageline lz 
                             WHERE l.ogc_fid <> lz.ogc_fid 
                             AND ST_DWithin(l.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(st_startpoint(l.wkb_geometry), 0.003))
                             AND ST_DWithin(cp.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(cp.wkb_geometry, 0.0009))
                         ) c 
                         ORDER BY st_startpoint(l.wkb_geometry) <#> c.centroidgeom LIMIT 1
                     )
                 ) dpto_abrev 
                 FROM (SELECT ogc_fid, wkb_geometry, name FROM workspace.mileageline 
                       WHERE st_geometrytype(wkb_geometry) = ''ST_LineString'' 
                       AND calculated = false
                       AND (name IS NULL OR name = '''')
                 ) l
             ) resp 
             WHERE resp.ogc_fid = workspace.mileageline.ogc_fid 
             AND workspace.mileageline.calculated = false';

    /* Obtiene el centro poblado de fin de la ruta */
    EXECUTE 'UPDATE workspace.mileageline 
             SET name = name || resp.nom_cpob || '' ('' || resp.dpto_abrev || '')'' 
             FROM (
                 SELECT c.nom_cpob, c.dpto_abrev, ml.ogc_fid 
                 FROM ' || cast(countryname as text) || '.populatedcenters c,
                      workspace.mileageline ml 
                 WHERE ST_DWithin(c.wkb_geometry, st_endpoint(ml.wkb_geometry), 0.005)            
                 AND st_intersects(c.wkb_geometry, st_buffer(st_endpoint(ml.wkb_geometry), 0.003))
                 AND st_geometrytype(ml.wkb_geometry) = ''ST_LineString'' 
                 AND ml.calculated = false 
                 AND ml.name ILIKE ''% - '' 
                 ORDER BY st_distance(ST_PointOnSurface(c.wkb_geometry), st_endpoint(ml.wkb_geometry)) ASC
             ) resp
             WHERE resp.ogc_fid = workspace.mileageline.ogc_fid 
             AND workspace.mileageline.calculated = false';

    /* Obtiene el centro poblado más cercano al fin de la ruta (para líneas tipo cruce) */
    EXECUTE 'UPDATE workspace.mileageline 
             SET NAME = name || ''CRUCE '' || COALESCE(NULLIF(resp.namepoblado, NULL), ''NN'') || '' ('' || COALESCE(NULLIF(resp.dpto_abrev, NULL), ''NN'') || '')''  
             FROM (
                 SELECT DISTINCT(l.ogc_fid), (
                     SELECT (
                         SELECT c.nom_cpob
                         FROM (
                             SELECT cp.nom_cpob, cp.centroidgeom 
                             FROM ' || cast(countryname as text) || '.populatedcenters cp, workspace.mileageline lz 
                             WHERE l.ogc_fid <> lz.ogc_fid 
                             AND ST_DWithin(l.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(st_endpoint(l.wkb_geometry), 0.003))
                             AND ST_DWithin(cp.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(cp.wkb_geometry, 0.0009))
                         ) c  
                         ORDER BY st_endpoint(l.wkb_geometry) <#> c.centroidgeom LIMIT 1
                     )
                 ) namepoblado, (
                     SELECT (
                         SELECT c.dpto_abrev
                         FROM (
                             SELECT cp.dpto_abrev, cp.centroidgeom 
                             FROM ' || cast(countryname as text) || '.populatedcenters cp, workspace.mileageline lz 
                             WHERE l.ogc_fid <> lz.ogc_fid 
                             AND ST_DWithin(l.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(st_endpoint(l.wkb_geometry), 0.003))
                             AND ST_DWithin(cp.wkb_geometry, lz.wkb_geometry, 0.005)
                             AND st_intersects(lz.wkb_geometry, st_buffer(cp.wkb_geometry, 0.0009))
                         ) c 
                         ORDER BY st_endpoint(l.wkb_geometry) <#> c.centroidgeom LIMIT 1
                     )
                 ) dpto_abrev 
                 FROM (SELECT ogc_fid, wkb_geometry, name FROM workspace.mileageline 
                       WHERE name ILIKE ''% - CRUCE NN (NN)'' 
                       AND st_geometrytype(wkb_geometry) = ''ST_LineString''
                       AND calculated = false 
                 ) l
             ) resp
             WHERE resp.ogc_fid = workspace.mileageline.ogc_fid 
             AND workspace.mileageline.calculated = false';

    /* Calcula centros poblados para ruta con base a capa multipoint (inicio de ruta) (CASO México) */
    EXECUTE 'UPDATE workspace.mileageline 
             SET name = REPLACE(name, ''CRUCE NN (NN) - '', resp.nom_loc || '' ('' || resp.dpto_abrev || '') - '')
             FROM (
                 SELECT DISTINCT(ml.ogc_fid) ogc_fid, loc.nom_loc, loc.nom_cpob, loc.dpto_abrev,
                        st_distance(loc.wkb_geometry, st_startpoint(ml.wkb_geometry))        
                 FROM ' || cast(countryname as text) || '.populatedcenters c,
                      mex.localities as loc,
                      workspace.mileageline ml 
                 WHERE ml.name ILIKE ''CRUCE NN (NN) - %''
                 AND ST_DWithin(st_startpoint(ml.wkb_geometry), loc.wkb_geometry, 0.025) 
                 AND st_intersects(c.wkb_geometry, loc.wkb_geometry
