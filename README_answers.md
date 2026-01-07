
+A Educação - Desafio PostgreSQL
===================

[![N|Solid](https://maisaedu.com.br/hubfs/site-grupo-a/logo-mais-a-educacao.svg)](https://maisaedu.com.br/) 

O objetivo deste desafio é avaliar algumas competências técnicas consideradas fundamentais para candidatos ao cargo de DBA na Maior Plataforma de Educação do Brasil.

Será solicitado ao candidato que realize algumas tarefas baseadas em estrutura incompleta de tabelas relacionadas neste documento. Considere o PostgreSQL como SGDB ao aplicar conceitos e validações.

## Contexto

Você está lidando com um banco de dados multi-tenant que armazena informações acadêmicas sobre pessoas, instituições, cursos e matrículas de diferentes clientes (tenants). Sua tarefa será estruturar as tabelas, criar chaves primárias e estrangeiras, otimizar consultas, entre outras atividades. O desafio também envolve manipulação de dados em formato `jsonb`, com a necessidade implícita de construir índices apropriados.

## Estrutura das Tabelas

### 1. Tabela `tenant`
Representa diferentes clientes que utilizam o sistema. Pode ter cerca de 100 registros.

```sql
CREATE TABLE tenant (
    id SERIAL,
    name VARCHAR(100),
    description VARCHAR(255)
);
```
### 2.	Tabela `person` 
Contém informações sobre indivíduos. Esta tabela não está associada diretamente a um tenant. Estima-se ter 5.000.000 registros.

```sql
CREATE TABLE person (
    id SERIAL,
    name VARCHAR(100),
    birth_date DATE,
    metadata JSONB
);
```
### 3.	Tabela `institution`
Armazena detalhes sobre instituições associadas a diferentes tenants. Esta tabela terá aproximadamente 1.000 registros.

```sql
CREATE TABLE institution (
    id SERIAL,
    tenant_id INTEGER,
    name VARCHAR(100),
    location VARCHAR(100),
    details JSONB
);
```
### 4.	Tabela `course` 
Contém informações sobre cursos oferecidos por instituições, também associadas a um tenant. Deve ter cerca de 5.000 registros.

```sql
CREATE TABLE course (
    id SERIAL,
    tenant_id INTEGER,
    institution_id INTEGER,
    name VARCHAR(100),
    duration INTEGER,
    details JSONB
);
```

### 5.	Tabela `enrollment`
Armazena informações de matrículas, associadas a um tenant. Esta é a tabela com maior volume de dados, com cerca de 100.000.000 registros.

```sql
CREATE TABLE enrollment (
    id SERIAL,
    tenant_id INTEGER,
    institution_id INTEGER,
    person_id INTEGER,
    enrollment_date DATE,
    status VARCHAR(20)
);
```

## Tarefas

1. Identifique as chaves primárias e estrangeiras necessárias para garantir a integridade referencial. Defina-as corretamente.
   TESTE 
3. Construa índices que consideras essenciais para operações básicas do banco e de consultas possíveis para a estrutura sugerida.
4. Considere que em enollment só pode existir um único person_id por tenant e institution. Mas institution poderá ser nulo. Como garantir a integridade desta regra?
5. Caso eu queira incluir conceitos de exclusão lógica na tabela enrollment. Como eu poderia fazer? Quais as alterações necessárias nas definições anteriores?
6. Construa uma consulta que retorne o número de matrículas por curso em uma determinada instituição.Filtre por tenant_id e institution_id obrigatoriamente. Filtre também por uma busca qualquer -full search - no campo metadata da tabela person que contém informações adicionais no formato JSONB. Considere aqui também a exclusão lógica e exiba somente registros válidos.
7. Construa uma consulta que retorne os alunos de um curso em uma tenant e institution específicos. Esta é uma consulta para atender a requisição que tem por objetivo alimentar uma listagem de alunos em determinado curso. Tenha em mente que poderá retornar um número grande de registros por se tratar de um curso EAD. Use boas práticas. Considere aqui também a exclusão lógica e exiba somente registros válidos.
8. Suponha que decidimos particionar a tabela enrollment. Desenvolva esta ideia. Reescreva a definição da tabela por algum critério que julgues adequado. Faça todos os ajustes necessários e comente-os.
9. Sinta-se a vontade para sugerir e aplicar qualquer ajuste que achares relevante. Comente-os


## Critérios de avaliação
- Organização, clareza e lógica
- Utilização de boas práticas
- Documentação justificando o porquê das escolhas

## Instruções de entrega
1. Crie um fork do repositório no seu GitHub
2. Faça o push do código desenvolvido no seu Github
3. Informe ao recrutador quando concluir o desafio junto com o link do repositório
4. Após revisão do projeto, em conjunto com a equipe técnica, deixe seu repositório privado
