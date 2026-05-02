-- chalona-erp-clients schema standalone
--
-- Crea las tablas y funciones mínimas para alojar:
--   - Scripts VFP descargables por cliente Fox (data.fox_cliente_script)
--   - Bytecode Dart descargable por cliente Dart  (data.dart_cliente_driver)
--   - Ensamblados .NET descargables por cliente C# (data.cs_cliente_driver)
--
-- Patrón: cada cliente envía su versión local en cada request. El servidor
-- compara con la versión activa; si difieren, responde "version_desactualizada"
-- y el cliente baja la nueva versión y reintenta. Sin polling, sin push.
--
-- Aplicar:
--   psql -h localhost -U postgres -d <basedatos> -v ON_ERROR_STOP=1 -f schema.sql

CREATE SCHEMA IF NOT EXISTS data;
CREATE SCHEMA IF NOT EXISTS fn;
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- digest() para verificar sha256

-- =============================================================================
-- Cliente Fox (.prg compilado on-the-fly por VFP en el cliente)
-- =============================================================================

CREATE TABLE IF NOT EXISTS data.fox_cliente_script (
  id          serial PRIMARY KEY,
  entorno     varchar(20)  NOT NULL CHECK (entorno IN ('produccion', 'test')),
  version     integer      NOT NULL,
  script      text         NOT NULL,
  creado_en   timestamptz  NOT NULL DEFAULT now(),
  activo      boolean      NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS fox_cliente_script_activo_idx
  ON data.fox_cliente_script (entorno) WHERE activo = true;

CREATE UNIQUE INDEX IF NOT EXISTS fox_cliente_script_entorno_version_idx
  ON data.fox_cliente_script (entorno, version);

COMMENT ON TABLE data.fox_cliente_script IS
  'Scripts VFP descargados por el cliente Fox en runtime. Una versión activa por entorno.';

-- Lookup: devuelve script activo del entorno
CREATE OR REPLACE FUNCTION fn.fox_cliente_script(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in text;
  rec        data.fox_cliente_script;
BEGIN
  entorno_in := trim(coalesce(param->>'entorno', 'produccion'));
  IF entorno_in NOT IN ('produccion', 'test') THEN
    entorno_in := 'produccion';
  END IF;

  SELECT * INTO rec
  FROM data.fox_cliente_script
  WHERE entorno = entorno_in AND activo = true;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'fox_cliente.script_no_disponible'::text, '{}'::jsonb;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'version', rec.version,
    'script',  rec.script
  );
END;
$$;

-- Publica nueva versión (atómico: desactiva la anterior, activa la nueva)
CREATE OR REPLACE FUNCTION fn.fox_cliente_script_publicar(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in text;
  script_in  text;
  nueva_ver  integer;
  nuevo_id   integer;
BEGIN
  entorno_in := trim(coalesce(param->>'entorno', ''));
  script_in  := coalesce(param->>'script', '');

  IF entorno_in NOT IN ('produccion', 'test') THEN
    RETURN QUERY SELECT false,
      'err.fox_cliente_script_publicar.entorno_invalido'::text, '{}'::jsonb;
    RETURN;
  END IF;
  IF script_in = '' THEN
    RETURN QUERY SELECT false,
      'err.fox_cliente_script_publicar.script_vacio'::text, '{}'::jsonb;
    RETURN;
  END IF;

  SELECT coalesce(max(version), 0) + 1 INTO nueva_ver
  FROM data.fox_cliente_script WHERE entorno = entorno_in;

  UPDATE data.fox_cliente_script SET activo = false
  WHERE entorno = entorno_in AND activo = true;

  INSERT INTO data.fox_cliente_script (entorno, version, script, activo)
  VALUES (entorno_in, nueva_ver, script_in, true)
  RETURNING id INTO nuevo_id;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'id', nuevo_id, 'version', nueva_ver, 'entorno', entorno_in
  );
END;
$$;

-- =============================================================================
-- Cliente Dart (.evc bytecode generado por dart_eval)
-- =============================================================================

CREATE TABLE IF NOT EXISTS data.dart_cliente_driver (
  id          serial PRIMARY KEY,
  entorno     varchar(20)  NOT NULL CHECK (entorno IN ('produccion', 'test')),
  version     integer      NOT NULL,
  bytes       bytea        NOT NULL,
  hash_sha256 char(64)     NOT NULL,
  notas       text,
  creado_en   timestamptz  NOT NULL DEFAULT now(),
  activo      boolean      NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS dart_cliente_driver_activo_idx
  ON data.dart_cliente_driver (entorno) WHERE activo = true;

CREATE UNIQUE INDEX IF NOT EXISTS dart_cliente_driver_entorno_version_idx
  ON data.dart_cliente_driver (entorno, version);

COMMENT ON TABLE data.dart_cliente_driver IS
  'Bytecode .evc descargado por clientes Dart en runtime (dart_eval). Una versión activa por entorno.';

-- Lookup: solo metadata. Cliente lo llama en cada request — debe ser barato.
CREATE OR REPLACE FUNCTION fn.dart_cliente_driver_lookup(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in text;
  rec        data.dart_cliente_driver;
BEGIN
  entorno_in := trim(coalesce(param->>'entorno', 'produccion'));
  IF entorno_in NOT IN ('produccion', 'test') THEN
    entorno_in := 'produccion';
  END IF;

  SELECT * INTO rec
  FROM data.dart_cliente_driver
  WHERE entorno = entorno_in AND activo = true;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'dart_cliente_driver.no_disponible'::text, '{}'::jsonb;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'version',     rec.version,
    'entorno',     rec.entorno,
    'hash_sha256', rec.hash_sha256,
    'tamano',      length(rec.bytes),
    'creado_en',   rec.creado_en
  );
END;
$$;

-- Descarga bytes en base64. Cliente solo la llama cuando lookup detectó cambio.
CREATE OR REPLACE FUNCTION fn.dart_cliente_driver_descargar(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in text;
  version_in integer;
  rec        data.dart_cliente_driver;
BEGIN
  entorno_in := trim(coalesce(param->>'entorno', 'produccion'));
  version_in := nullif(param->>'version', '')::integer;

  IF entorno_in NOT IN ('produccion', 'test') THEN
    entorno_in := 'produccion';
  END IF;

  IF version_in IS NULL THEN
    SELECT * INTO rec FROM data.dart_cliente_driver
    WHERE entorno = entorno_in AND activo = true;
  ELSE
    SELECT * INTO rec FROM data.dart_cliente_driver
    WHERE entorno = entorno_in AND version = version_in;
  END IF;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'dart_cliente_driver.version_no_existe'::text, '{}'::jsonb;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'version',     rec.version,
    'entorno',     rec.entorno,
    'hash_sha256', rec.hash_sha256,
    'bytes_b64',   encode(rec.bytes, 'base64')
  );
END;
$$;

-- Publica nueva versión. Verifica hash sha256 contra los bytes.
CREATE OR REPLACE FUNCTION fn.dart_cliente_driver_publicar(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in   text;
  bytes_b64_in text;
  hash_in      text;
  notas_in     text;
  bytes_bin    bytea;
  nueva_ver    integer;
  nuevo_id     integer;
BEGIN
  entorno_in   := trim(coalesce(param->>'entorno', ''));
  bytes_b64_in := coalesce(param->>'bytes_b64', '');
  hash_in      := lower(trim(coalesce(param->>'hash_sha256', '')));
  notas_in     := nullif(trim(coalesce(param->>'notas', '')), '');

  IF entorno_in NOT IN ('produccion', 'test') THEN
    RETURN QUERY SELECT false,
      'err.dart_cliente_driver_publicar.entorno_invalido'::text, '{}'::jsonb;
    RETURN;
  END IF;
  IF bytes_b64_in = '' THEN
    RETURN QUERY SELECT false,
      'err.dart_cliente_driver_publicar.bytes_vacio'::text, '{}'::jsonb;
    RETURN;
  END IF;
  IF hash_in !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT false,
      'err.dart_cliente_driver_publicar.hash_invalido'::text, '{}'::jsonb;
    RETURN;
  END IF;

  bytes_bin := decode(bytes_b64_in, 'base64');

  IF encode(digest(bytes_bin, 'sha256'), 'hex') <> hash_in THEN
    RETURN QUERY SELECT false,
      'err.dart_cliente_driver_publicar.hash_invalido'::text,
      jsonb_build_object('hash_recibido',  hash_in,
                         'hash_calculado', encode(digest(bytes_bin, 'sha256'), 'hex'));
    RETURN;
  END IF;

  SELECT coalesce(max(version), 0) + 1 INTO nueva_ver
  FROM data.dart_cliente_driver WHERE entorno = entorno_in;

  UPDATE data.dart_cliente_driver SET activo = false
  WHERE entorno = entorno_in AND activo = true;

  INSERT INTO data.dart_cliente_driver
    (entorno, version, bytes, hash_sha256, notas, activo)
  VALUES
    (entorno_in, nueva_ver, bytes_bin, hash_in, notas_in, true)
  RETURNING id INTO nuevo_id;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'id',          nuevo_id,
    'version',     nueva_ver,
    'entorno',     entorno_in,
    'tamano',      length(bytes_bin),
    'hash_sha256', hash_in
  );
END;
$$;

-- =============================================================================
-- Cliente C# (.dll IL bytes generado por Roslyn)
-- =============================================================================

CREATE TABLE IF NOT EXISTS data.cs_cliente_driver (
  id          serial PRIMARY KEY,
  entorno     varchar(20)  NOT NULL CHECK (entorno IN ('produccion', 'test')),
  version     integer      NOT NULL,
  bytes       bytea        NOT NULL,
  hash_sha256 char(64)     NOT NULL,
  notas       text,
  creado_en   timestamptz  NOT NULL DEFAULT now(),
  activo      boolean      NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS cs_cliente_driver_activo_idx
  ON data.cs_cliente_driver (entorno) WHERE activo = true;

CREATE UNIQUE INDEX IF NOT EXISTS cs_cliente_driver_entorno_version_idx
  ON data.cs_cliente_driver (entorno, version);

COMMENT ON TABLE data.cs_cliente_driver IS
  'Ensamblados .NET descargados por clientes C# en runtime (AssemblyLoadContext). Una versión activa por entorno.';

CREATE OR REPLACE FUNCTION fn.cs_cliente_driver_lookup(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in text;
  rec        data.cs_cliente_driver;
BEGIN
  entorno_in := trim(coalesce(param->>'entorno', 'produccion'));
  IF entorno_in NOT IN ('produccion', 'test') THEN
    entorno_in := 'produccion';
  END IF;

  SELECT * INTO rec FROM data.cs_cliente_driver
  WHERE entorno = entorno_in AND activo = true;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'cs_cliente_driver.no_disponible'::text, '{}'::jsonb;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'version',     rec.version,
    'entorno',     rec.entorno,
    'hash_sha256', rec.hash_sha256,
    'tamano',      length(rec.bytes),
    'creado_en',   rec.creado_en
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn.cs_cliente_driver_descargar(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in text;
  version_in integer;
  rec        data.cs_cliente_driver;
BEGIN
  entorno_in := trim(coalesce(param->>'entorno', 'produccion'));
  version_in := nullif(param->>'version', '')::integer;

  IF entorno_in NOT IN ('produccion', 'test') THEN
    entorno_in := 'produccion';
  END IF;

  IF version_in IS NULL THEN
    SELECT * INTO rec FROM data.cs_cliente_driver
    WHERE entorno = entorno_in AND activo = true;
  ELSE
    SELECT * INTO rec FROM data.cs_cliente_driver
    WHERE entorno = entorno_in AND version = version_in;
  END IF;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'cs_cliente_driver.version_no_existe'::text, '{}'::jsonb;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'version',     rec.version,
    'entorno',     rec.entorno,
    'hash_sha256', rec.hash_sha256,
    'bytes_b64',   encode(rec.bytes, 'base64')
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn.cs_cliente_driver_publicar(param jsonb)
RETURNS TABLE(ok boolean, message text, data jsonb)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  entorno_in   text;
  bytes_b64_in text;
  hash_in      text;
  notas_in     text;
  bytes_bin    bytea;
  nuevo_id     integer;
  nueva_ver    integer;
BEGIN
  entorno_in   := trim(coalesce(param->>'entorno', ''));
  bytes_b64_in := coalesce(param->>'bytes_b64', '');
  hash_in      := lower(trim(coalesce(param->>'hash_sha256', '')));
  notas_in     := nullif(trim(coalesce(param->>'notas', '')), '');

  IF entorno_in NOT IN ('produccion', 'test') THEN
    RETURN QUERY SELECT false,
      'err.cs_cliente_driver_publicar.entorno_invalido'::text, '{}'::jsonb;
    RETURN;
  END IF;
  IF bytes_b64_in = '' THEN
    RETURN QUERY SELECT false,
      'err.cs_cliente_driver_publicar.bytes_vacio'::text, '{}'::jsonb;
    RETURN;
  END IF;
  IF hash_in !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT false,
      'err.cs_cliente_driver_publicar.hash_invalido'::text, '{}'::jsonb;
    RETURN;
  END IF;

  bytes_bin := decode(bytes_b64_in, 'base64');

  IF encode(digest(bytes_bin, 'sha256'), 'hex') <> hash_in THEN
    RETURN QUERY SELECT false,
      'err.cs_cliente_driver_publicar.hash_invalido'::text,
      jsonb_build_object('hash_recibido',  hash_in,
                         'hash_calculado', encode(digest(bytes_bin, 'sha256'), 'hex'));
    RETURN;
  END IF;

  SELECT coalesce(max(version), 0) + 1 INTO nueva_ver
  FROM data.cs_cliente_driver WHERE entorno = entorno_in;

  UPDATE data.cs_cliente_driver SET activo = false
  WHERE entorno = entorno_in AND activo = true;

  INSERT INTO data.cs_cliente_driver
    (entorno, version, bytes, hash_sha256, notas, activo)
  VALUES
    (entorno_in, nueva_ver, bytes_bin, hash_in, notas_in, true)
  RETURNING id INTO nuevo_id;

  RETURN QUERY SELECT true, 'ok'::text, jsonb_build_object(
    'id',          nuevo_id,
    'version',     nueva_ver,
    'entorno',     entorno_in,
    'tamano',      length(bytes_bin),
    'hash_sha256', hash_in
  );
END;
$$;
