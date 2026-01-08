O objetivo deste desafio é avaliar algumas competências técnicas consideradas fundamentais para candidatos ao cargo de DBA na Maior Plataforma de Educação do Brasil.

Será solicitado ao candidato que realize algumas tarefas baseadas em estrutura incompleta de tabelas relacionadas neste documento. Considere o PostgreSQL como SGDB ao aplicar conceitos e validações.

Contexto
Você está lidando com um banco de dados multi-tenant que armazena informações acadêmicas sobre pessoas, instituições, cursos e matrículas de diferentes clientes (tenants). Sua tarefa será estruturar as tabelas, criar chaves primárias e estrangeiras, otimizar consultas, entre outras atividades. O desafio também envolve manipulação de dados em formato jsonb, com a necessidade implícita de construir índices apropriados.

Estrutura das Tabelas

1. Tabela tenant
Representa diferentes clientes que utilizam o sistema. Pode ter cerca de 100 registros.

CREATE TABLE tenant (
    id SERIAL,
    name VARCHAR(100),
    description VARCHAR(255)
);

2. Tabela person
Contém informações sobre indivíduos. Esta tabela não está associada diretamente a um tenant. Estima-se ter 5.000.000 registros.

CREATE TABLE person (
    id SERIAL,
    name VARCHAR(100),
    birth_date DATE,
    metadata JSONB
);

3. Tabela institution
Armazena detalhes sobre instituições associadas a diferentes tenants. Esta tabela terá aproximadamente 1.000 registros.

CREATE TABLE institution (
    id SERIAL,
    tenant_id INTEGER,
    name VARCHAR(100),
    location VARCHAR(100),
    details JSONB
);

4. Tabela course
Contém informações sobre cursos oferecidos por instituições, também associadas a um tenant. Deve ter cerca de 5.000 registros.

CREATE TABLE course (
    id SERIAL,
    tenant_id INTEGER,
    institution_id INTEGER,
    name VARCHAR(100),
    duration INTEGER,
    details JSONB
);

5. Tabela enrollment
Armazena informações de matrículas, associadas a um tenant. Esta é a tabela com maior volume de dados, com cerca de 100.000.000 registros.

CREATE TABLE enrollment (
    id SERIAL,
    tenant_id INTEGER,
    institution_id INTEGER,
    person_id INTEGER,
    enrollment_date DATE,
    status VARCHAR(20)
);

Tarefas

Nota Técnica

O minimundo apresenta informações relevantes para a construção de uma base de dados concisa, eficiente e eficaz. À luz das informações previamente fornecidas, o resultado obtido está em conformidade com as boas práticas de modelagem, especialmente no que se refere à aplicação das Formas Normais em bases de dados relacionais.
A transformação de uma base de dados acadêmica em um modelo consistente, desenvolvido para PostgreSQL, fundamenta-se em dois pilares centrais: multi-tenant e volumetria. Essas características demandaram — de forma positiva sob a ótica da avaliação — a adoção de novos tipos de dados, a redefinição de relacionamentos visando maior integridade referencial e a criação de índices adicionais voltados à otimização de desempenho.
Em decorrência desses novos componentes incorporados à base, as consultas tornaram-se mais detalhadas, ao mesmo tempo em que passaram a apresentar tempos de resposta significativamente mais eficientes.


1) Identifique as chaves primárias e estrangeiras necessárias para garantir a integridade referencial. Defina-as corretamente.

-- 1) TENANT
CREATE TABLE tenant (
    id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    description VARCHAR(255)
);

-- 2) PERSON (sem tenant) - muito grande
CREATE TABLE person (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    birth_date DATE,
    metadata   JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- 3) INSTITUTION (scoped por tenant)
CREATE TABLE institution (
    id        INTEGER GENERATED ALWAYS AS IDENTITY,
    tenant_id INTEGER NOT NULL,
    name      VARCHAR(100) NOT NULL,
    location  VARCHAR(100),
    details   JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT pk_institution PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_institution_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenant(id) ON DELETE RESTRICT
);

-- 4) COURSE (scoped por tenant e vinculado a institution do mesmo tenant)
CREATE TABLE course (
    id             INTEGER GENERATED ALWAYS AS IDENTITY,
    tenant_id      INTEGER NOT NULL,
    institution_id INTEGER NOT NULL,
    name           VARCHAR(100) NOT NULL,
    duration       INTEGER,
    details        JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT pk_course PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_course_institution FOREIGN KEY (tenant_id, institution_id)
        REFERENCES institution(tenant_id, id) ON DELETE RESTRICT
);

-- 5) ENROLLMENT (maior volume) - incluo course_id (necessário p/ tarefas 5 e 6)
CREATE TABLE enrollment (
    id              BIGINT GENERATED ALWAYS AS IDENTITY,
    tenant_id       INTEGER NOT NULL,
    institution_id  INTEGER NULL,
    course_id       INTEGER NOT NULL,
    person_id       BIGINT  NOT NULL,
    enrollment_date DATE    NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20) NOT NULL,

    -- Exclusão lógica (detalhada na tarefa 4)
    deleted_at      TIMESTAMPTZ NULL,

    CONSTRAINT pk_enrollment PRIMARY KEY (tenant_id, id),

    CONSTRAINT fk_enrollment_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenant(id) ON DELETE RESTRICT,

    -- institution_id é opcional: FK permite NULL
    CONSTRAINT fk_enrollment_institution FOREIGN KEY (tenant_id, institution_id)
        REFERENCES institution(tenant_id, id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_course FOREIGN KEY (tenant_id, course_id)
        REFERENCES course(tenant_id, id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_person FOREIGN KEY (person_id)
        REFERENCES person(id) ON DELETE RESTRICT
);

Observação 1: Alguns campos tiveram seus nomes e tipos de dados revisados com o objetivo de assegurar maior qualidade no armazenamento, integridade dos dados e suporte adequado à volumetria. Em especial, campos utilizados como chaves primárias e estrangeiras tiveram seus tipos ajustados de SERIAL para INTEGER ou BIGINT, com a adoção do mecanismo GENERATED ALWAYS AS IDENTITY, alinhando o modelo às práticas modernas recomendadas pelo PostgreSQL.
Observação 2: Campos considerados essenciais ao domínio do negócio passaram a possuir a restrição NOT NULL, garantindo a obrigatoriedade de preenchimento e reduzindo a possibilidade de inconsistências lógicas e registros incompletos na base de dados.
Observação 3: Foram definidos índices adicionais, incluindo índices compostos e índices específicos para campos do tipo jsonb, com o objetivo de otimizar consultas recorrentes e cenários de alto volume de dados. A estratégia de indexação considerou padrões de acesso, filtros mais utilizados e a segregação lógica por tenant, contribuindo para ganhos significativos de desempenho sem comprometer a flexibilidade do modelo.

2) Construa índices que consideras essenciais para operações básicas do banco e de consultas possíveis para a estrutura sugerida.

-- TENANT: já tem PK

-- PERSON: busca por JSONB (ver também tsvector abaixo)
CREATE INDEX ix_person_metadata_gin ON person USING GIN (metadata);

-- Opcional e muito útil p/ "full search" textual (ver tarefa 5):
-- Indexa um tsvector gerado a partir do JSONB (busca por termos).
ALTER TABLE person
ADD COLUMN metadata_tsv tsvector
GENERATED ALWAYS AS (to_tsvector('simple', coalesce(metadata::text, ''))) STORED;

CREATE INDEX ix_person_metadata_tsv_gin ON person USING GIN (metadata_tsv);

-- INSTITUTION
CREATE INDEX ix_institution_name ON institution (tenant_id, name);

-- COURSE
CREATE INDEX ix_course_lookup ON course (tenant_id, institution_id, name);

-- ENROLLMENT: principais caminhos de consulta (sempre filtrando por tenant)
-- Listagem/contagem por curso + instituição
CREATE INDEX ix_enrollment_tenant_inst_course_active
ON enrollment (tenant_id, institution_id, course_id)
WHERE deleted_at IS NULL;

-- Listagem de alunos (paginada) por curso, instituição, tenant
-- Incluo (tenant_id, institution_id, course_id, id) para paginação keyset.
CREATE INDEX ix_enrollment_list_active
ON enrollment (tenant_id, institution_id, course_id, id)
INCLUDE (person_id, enrollment_date, status)
WHERE deleted_at IS NULL;

-- Caso consulte por pessoa (histórico, validação etc.)
CREATE INDEX ix_enrollment_person_active
ON enrollment (tenant_id, person_id, id)
WHERE deleted_at IS NULL;

-- Se status é filtro frequente
CREATE INDEX ix_enrollment_status_active
ON enrollment (tenant_id, status, institution_id, course_id)
WHERE deleted_at IS NULL;

Observação: Aprsentamos índices para acelerar joins/FKs, filtramos por tenant/institution/course e suportamos busca eficiente em jsonb.

3) Considere que em enollment só pode existir um único person_id por tenant e institution. Mas institution poderá ser nulo. Como garantir a integridade desta regra?

-- Caso 1: institution_id NÃO é NULL -> único por (tenant, institution, person)
CREATE UNIQUE INDEX ux_enrollment_one_person_per_tenant_institution_active
ON enrollment (tenant_id, institution_id, person_id)
WHERE institution_id IS NOT NULL
  AND deleted_at IS NULL;

-- Caso 2: institution_id é NULL -> único por (tenant, person)
CREATE UNIQUE INDEX ux_enrollment_one_person_per_tenant_when_institution_null_active
ON enrollment (tenant_id, person_id)
WHERE institution_id IS NULL
  AND deleted_at IS NULL;

Observação: A regra é clara! Em enrollment só pode existir um único person_id por tenant e institution; institution pode ser nulo. O UNIQUE padrão não resolve bem “NULL = igual”, então fisemos uso de índices únicos parciais para cobrir os dois casos (institution preenchido e institution nulo). Um mesmo person_id não pode aparecer mais de uma vez para o mesmo tenant + institution (e quando institution_id for NULL, vale a regra por tenant apenas).

4) Caso eu queira incluir conceitos de exclusão lógica na tabela enrollment. Como eu poderia fazer? Quais as alterações necessárias nas definições anteriores?

ALTER TABLE enrollment ADD COLUMN deleted_at TIMESTAMPTZ NULL;

As consultas válidas devem usar WHERE e.deleted_at IS NULL

UPDATE enrollment
SET deleted_at = now()
WHERE tenant_id = $1 AND id = $2 AND deleted_at IS NULL;

Observação 1: Optamos por utilizar "exclusões lógicas" conforme solicitado, utilizando UPDATE no lugar do DELETE, face ao respeito as boas práticas, bem como a historicidade da base de dados;
Observação 2: Adicionamos deleted_at e ajustamos índices únicos e consultas para ignorar registros excluídos

5) Construa uma consulta que retorne o número de matrículas por curso em uma determinada instituição.Filtre por tenant_id e institution_id obrigatoriamente. Filtre também por uma busca qualquer -full search - no campo metadata da tabela person que contém informações adicionais no formato JSONB. Considere aqui também a exclusão lógica e exiba somente registros válidos.

-- Parâmetros:
-- $1 = tenant_id
-- $2 = institution_id
-- $3 = termo de busca (ex: 'silva engenharia "rio de janeiro"')

SELECT
    c.id   AS course_id,
    c.name AS course_name,
    COUNT(*) AS enrollments
FROM enrollment e
JOIN course c
  ON c.tenant_id = e.tenant_id
 AND c.id        = e.course_id
JOIN person p
  ON p.id = e.person_id
WHERE e.tenant_id = $1
  AND e.institution_id = $2
  AND e.deleted_at IS NULL
  AND p.metadata_tsv @@ websearch_to_tsquery('simple', $3)
GROUP BY c.id, c.name
ORDER BY enrollments DESC;

Observação: Filtramos por tenant/institution (reduz cardinalidade), aplicamos exclusão lógica, e usamos tsvector para busca textual no JSONB sem varrer 5 milhões de pessoas.

6) Construa uma consulta que retorne os alunos de um curso em uma tenant e institution específicos. Esta é uma consulta para atender a requisição que tem por objetivo alimentar uma listagem de alunos em determinado curso. Tenha em mente que poderá retornar um número grande de registros por se tratar de um curso EAD. Use boas práticas. Considere aqui também a exclusão lógica e exiba somente registros válidos.

-- Parâmetros:
-- $1 = tenant_id
-- $2 = institution_id
-- $3 = course_id
-- $4 = last_seen_enrollment_id (BIGINT) ou NULL na 1ª página
-- $5 = page_size

SELECT
    e.id            AS enrollment_id,
    e.enrollment_date,
    e.status,
    p.id            AS person_id,
    p.name          AS person_name
FROM enrollment e
JOIN person p ON p.id = e.person_id
WHERE e.tenant_id = $1
  AND e.institution_id = $2
  AND e.course_id = $3
  AND e.deleted_at IS NULL
  AND ($4 IS NULL OR e.id > $4)
ORDER BY e.id
LIMIT $5;

Observação: Usamos paginação keyset (não OFFSET), índice compatível e retorno minimalista para UI (lista). OFFSET degrada linearmente com páginas profundas; keyset mantém latência estável usando o índice ix_enrollment_list_active.

7) Suponha que decidimos particionar a tabela enrollment. Desenvolva esta ideia. Reescreva a definição da tabela por algum critério que julgues adequado. Faça todos os ajustes necessários e comente-os.

-- Tabela particionada (estrutura base)
CREATE TABLE enrollment (
    id              BIGINT GENERATED ALWAYS AS IDENTITY,
    tenant_id       INTEGER NOT NULL,
    institution_id  INTEGER NULL,
    course_id       INTEGER NOT NULL,
    person_id       BIGINT  NOT NULL,
    enrollment_date DATE    NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20) NOT NULL,
    deleted_at      TIMESTAMPTZ NULL,

    CONSTRAINT pk_enrollment PRIMARY KEY (tenant_id, id),

    CONSTRAINT fk_enrollment_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenant(id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_institution FOREIGN KEY (tenant_id, institution_id)
        REFERENCES institution(tenant_id, id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_course FOREIGN KEY (tenant_id, course_id)
        REFERENCES course(tenant_id, id) ON DELETE RESTRICT,

    CONSTRAINT fk_enrollment_person FOREIGN KEY (person_id)
        REFERENCES person(id) ON DELETE RESTRICT
)
PARTITION BY LIST (tenant_id);

-- Exemplo de criação de partições por tenant
CREATE TABLE enrollment_tenant_1 PARTITION OF enrollment FOR VALUES IN (1);
CREATE TABLE enrollment_tenant_2 PARTITION OF enrollment FOR VALUES IN (2);

-- Partição default para tenants novos (evita erro em inserts)
CREATE TABLE enrollment_default PARTITION OF enrollment DEFAULT;

Observação 1: A explicação mais simples é geramente a melhor exemplicação! Com 100 mil linhas, particionar reduz I/O, melhora manutenção (VACUUM/REINDEX), e permite “pruning” por filtros frequentes. Como o filtro sempre inclui tenant_id, particionar por tenant_id é natural.
Observação 2: PARTITION BY LIST (tenant_id): bom para para aproximadamente 100 tenants.
Observação 3: A PK precisa incluir a chave de partição: (tenant_id, id)
Observação 4: Em PostgreSQL, índices “globais” não existem como em alguns SGBDs; Criamos índices na tabela particionada e o PostgreSQL cria índices nas partições (ou você cria localmente).
Os índices únicos (regra da tarefa 3) precisam existir de forma compatível com partição — como já incluem tenant_id, eles funcionam bem. Veja abaixo:

CREATE INDEX ix_enrollment_list_active
ON enrollment (tenant_id, institution_id, course_id, id)
INCLUDE (person_id, enrollment_date, status)
WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX ux_enrollment_one_person_per_tenant_institution_active
ON enrollment (tenant_id, institution_id, person_id)
WHERE institution_id IS NOT NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX ux_enrollment_one_person_per_tenant_when_institution_null_active
ON enrollment (tenant_id, person_id)
WHERE institution_id IS NULL AND deleted_at IS NULL;

8) Sinta-se a vontade para sugerir e aplicar qualquer ajuste que achares relevante. Comente-os

8.1) Normalização do status

ALTER TABLE enrollment
ADD CONSTRAINT ck_enrollment_status
CHECK (status IN ('ACTIVE','CANCELED','FINISHED','SUSPENDED','PENDING'));

8.2) Consistência “course pertence à institution”

O enrollment tem institution_id e course_id. Como course já aponta para institution, você pode:

- remover institution_id de enrollment e derivar via join em course; ou
- manter e garantir consistência via trigger (porque FK direta cruzada com 3 colunas pode ficar rígida).

Sugestão mais limpa (recomendável): remover institution_id de enrollment e usar apenas course_id (e o tenant).

8.3) Estatísticas e manutenção (alto volume)

Ajuste de autovacuum por tabela/partição e fillfactor em enrollment pode ajudar em workloads de UPDATE (exclusão lógica).

ALTER TABLE enrollment SET (fillfactor = 90);

8.4) JSONB: se existirem chaves muito consultadas, indexe-as por expressão

CREATE INDEX ix_person_cpf ON person ((metadata->>'cpf'));

Observação 1: Faça uso das boas práticas para criação completa desta base de dados orientada, repetindo, para PostgreSQL;
Observação 2: Apresente as respostas ordenadas pelas tarefas;
Observação 3: Toda alteração, sugestão, correção e aplicação do script deve esrar munido de uma explicação curta e simples;