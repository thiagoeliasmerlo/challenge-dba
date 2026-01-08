/* ============================================================================
   IDP: Multi-tenant Academic DB (PostgreSQL)
   - Drops em ordem correta
   - Creates com IF NOT EXISTS
   - Enrollment particionada por tenant_id (LIST)
   - Índices essenciais + JSONB full search + exclusão lógica
   ============================================================================ */

BEGIN;

-- Opcional: colocar tudo em um schema dedicado
-- CREATE SCHEMA IF NOT EXISTS academic;
-- SET search_path TO academic, public;

-- ----------------------------------------------------------------------------
-- 0) DROPS (ordem correta: filhos -> pais)
-- ----------------------------------------------------------------------------

-- Partições (se existirem)
DROP TABLE IF EXISTS enrollment_default;
-- Caso você crie partições específicas, adicione-as aqui:
-- DROP TABLE IF EXISTS enrollment_tenant_1;
-- DROP TABLE IF EXISTS enrollment_tenant_2;

-- Tabela pai particionada (remove também índices locais/constraints associadas)
DROP TABLE IF EXISTS enrollment;

DROP TABLE IF EXISTS course;
DROP TABLE IF EXISTS institution;
DROP TABLE IF EXISTS person;
DROP TABLE IF EXISTS tenant;

-- ----------------------------------------------------------------------------
-- 1) CREATES: TENANT
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenant (
    id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    description VARCHAR(255)
);

-- ----------------------------------------------------------------------------
-- 2) CREATES: PERSON
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS person (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    birth_date   DATE,
    metadata     JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Full search no JSONB via tsvector (generated stored)
-- (Se a tabela já existisse em outro cenário, este ALTER garantiria a coluna)
ALTER TABLE person
ADD COLUMN IF NOT EXISTS metadata_tsv tsvector
GENERATED ALWAYS AS (to_tsvector('simple', coalesce(metadata::text, ''))) STORED;

-- ----------------------------------------------------------------------------
-- 3) CREATES: INSTITUTION
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS institution (
    id        INTEGER GENERATED ALWAYS AS IDENTITY,
    tenant_id INTEGER NOT NULL,
    name      VARCHAR(100) NOT NULL,
    location  VARCHAR(100),
    details   JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT pk_institution PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_institution_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenant(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 4) CREATES: COURSE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS course (
    id             INTEGER GENERATED ALWAYS AS IDENTITY,
    tenant_id      INTEGER NOT NULL,
    institution_id INTEGER NOT NULL,
    name           VARCHAR(100) NOT NULL,
    duration       INTEGER,
    details        JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT pk_course PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_course_institution
        FOREIGN KEY (tenant_id, institution_id)
        REFERENCES institution(tenant_id, id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 5) CREATES: ENROLLMENT (PARTITIONED)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS enrollment (
    id              BIGINT GENERATED ALWAYS AS IDENTITY,
    tenant_id       INTEGER NOT NULL,
    institution_id  INTEGER NULL,
    course_id       INTEGER NOT NULL,
    person_id       BIGINT  NOT NULL,
    enrollment_date DATE    NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20) NOT NULL,
    deleted_at      TIMESTAMPTZ NULL,

    CONSTRAINT pk_enrollment PRIMARY KEY (tenant_id, id),

    CONSTRAINT fk_enrollment_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenant(id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_institution
        FOREIGN KEY (tenant_id, institution_id)
        REFERENCES institution(tenant_id, id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_course
        FOREIGN KEY (tenant_id, course_id)
        REFERENCES course(tenant_id, id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_person
        FOREIGN KEY (person_id) REFERENCES person(id) ON DELETE RESTRICT,

    CONSTRAINT ck_enrollment_status
        CHECK (status IN ('ACTIVE','CANCELED','FINISHED','SUSPENDED','PENDING'))
)
PARTITION BY LIST (tenant_id);

-- Partição DEFAULT (idempotente pelo DROP anterior)
CREATE TABLE IF NOT EXISTS enrollment_default
PARTITION OF enrollment DEFAULT;

-- Se você quiser criar partições explícitas por tenant (exemplos):
-- CREATE TABLE IF NOT EXISTS enrollment_tenant_1 PARTITION OF enrollment FOR VALUES IN (1);
-- CREATE TABLE IF NOT EXISTS enrollment_tenant_2 PARTITION OF enrollment FOR VALUES IN (2);

-- ----------------------------------------------------------------------------
-- 6) ÍNDICES (inclui JSONB e parciais para exclusão lógica)
-- ----------------------------------------------------------------------------

-- PERSON: JSONB GIN (útil para queries jsonb @> ... etc.)
CREATE INDEX IF NOT EXISTS ix_person_metadata_gin
ON person USING GIN (metadata);

-- PERSON: Full search no JSONB (tsvector) via GIN
CREATE INDEX IF NOT EXISTS ix_person_metadata_tsv_gin
ON person USING GIN (metadata_tsv);

-- INSTITUTION
CREATE INDEX IF NOT EXISTS ix_institution_name
ON institution (tenant_id, name);

-- COURSE
CREATE INDEX IF NOT EXISTS ix_course_lookup
ON course (tenant_id, institution_id, name);

-- ENROLLMENT: principais caminhos de acesso (criados no pai e propagados às partições)
CREATE INDEX IF NOT EXISTS ix_enrollment_tenant_inst_course_active
ON enrollment (tenant_id, institution_id, course_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_enrollment_list_active
ON enrollment (tenant_id, institution_id, course_id, id)
INCLUDE (person_id, enrollment_date, status)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_enrollment_person_active
ON enrollment (tenant_id, person_id, id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_enrollment_status_active
ON enrollment (tenant_id, status, institution_id, course_id)
WHERE deleted_at IS NULL;

-- ----------------------------------------------------------------------------
-- 7) REGRA: um único person por (tenant, institution) e institution pode ser NULL
--    (usando índices únicos parciais e considerando exclusão lógica)
-- ----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS ux_enrollment_one_person_per_tenant_institution_active
ON enrollment (tenant_id, institution_id, person_id)
WHERE institution_id IS NOT NULL
  AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_enrollment_one_person_per_tenant_when_institution_null_active
ON enrollment (tenant_id, person_id)
WHERE institution_id IS NULL
  AND deleted_at IS NULL;

COMMIT;
