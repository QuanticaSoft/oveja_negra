-- Funciones comunes. migrate.sh fija el search_path: nada aquí nombra el schema.

CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END
$$;

-- Defensa en la BD de la regla "los históricos no se borran": aunque un bug en la API
-- intente un DELETE, Postgres lo rechaza.
CREATE FUNCTION forbid_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'No se permite borrar filas de %: anular con estado y reverso.', TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation';
END
$$;

-- Para registros que son libros contables (movimientos, transacciones, auditoría):
-- ni UPDATE ni DELETE; las correcciones son filas nuevas de reverso.
CREATE FUNCTION forbid_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'La tabla % es de solo inserción: corregir con una fila de reverso.', TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation';
END
$$;

CREATE PROCEDURE add_updated_at_trigger(tbl text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
        'trg_' || tbl || '_updated_at', tbl);
END
$$;

CREATE PROCEDURE add_no_delete_trigger(tbl text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format(
        'CREATE TRIGGER %I BEFORE DELETE ON %I FOR EACH ROW EXECUTE FUNCTION forbid_delete()',
        'trg_' || tbl || '_no_delete', tbl);
END
$$;

CREATE PROCEDURE add_append_only_trigger(tbl text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION forbid_change()',
        'trg_' || tbl || '_append_only', tbl);
END
$$;

-- Día operativo en La Paz: lo ocurrido antes de la hora de corte cuenta para el día anterior
-- (una venta a la 01:30 es de la jornada que empezó el día previo).
CREATE FUNCTION business_date_of(ts timestamptz, cutoff interval DEFAULT interval '4 hours') RETURNS date
LANGUAGE sql IMMUTABLE AS $$
    SELECT ((ts AT TIME ZONE 'America/La_Paz') - cutoff)::date
$$;
