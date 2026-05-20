-- =============================================================================
-- Arquivo  : 03_etl/01_extracao/extract_grupo_gupessanha.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Extração do OLTP do Grupo Gupessanha para o schema staging.
--            Cada tabela staging recebe um SELECT direto do schema fonte
--            (gupessanha.*) sem transformação de negócio — exceto stg_gupe_movimentacao,
--            que é DERIVADA de locacao (schema gupessanha não tem tabela de movimentação).
--
-- Cron recomendado: 0 4 * * *  (diário, às 04h00)
-- Justificativa: Mesmo raciocínio dos demais grupos. Destaque: a derivação de
--   stg_gupe_movimentacao a partir de locacao exige que a locacao do dia anterior
--   esteja completamente registrada antes da extração — 04h00 garante isso com
--   margem confortável.
--
-- Pré-requisito: tabelas OLTP carregadas no schema 'gupessanha' da mesma
--   instância PostgreSQL onde reside o DW.
--
-- Peculiaridades do schema gupessanha tratadas aqui:
--   * Cliente    → tabela unificada com subclasses (cliente_pf, cliente_pj); sem estado
--   * Veículo    → mecanizacao 'MANUAL'|'AUTOMATICA' (termina em A — normalizar em transform)
--   * Pátio      → campo endereco (texto livre) mapeado para localizacao
--   * Reserva    → estrutura direta (sem peculiaridades); estado ≠ status
--   * Locação    → patio_devolucao_id NOT NULL; pode ser planejado ≠ real para em_andamento
--   * Moviment.  → INEXISTENTE no schema; derivada de locacao CONCLUIDA (patio_ret → patio_dev)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- =============================================================================
-- 1. stg_gupe_patio
-- =============================================================================
-- Fonte: gupessanha.patio
-- Campo endereco (VARCHAR 200) mapeado para localizacao; sem cidade separada.
-- Ambiguidade: endereco contém o endereço completo mas não há cidade isolada.
-- Decisão conservadora: cidade = NULL, localizacao = endereco (preserva dado bruto).

CREATE TABLE IF NOT EXISTS staging.stg_gupe_patio (
    id_patio_origem   VARCHAR(50)  NOT NULL,
    nome_patio        VARCHAR(100) NOT NULL,
    cidade            VARCHAR(100),          -- NULL: não existe campo cidade isolado
    localizacao       VARCHAR(300),          -- endereco (texto livre do OLTP)
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_GUPESSANHA',
    CONSTRAINT pk_stg_gupe_patio PRIMARY KEY (id_patio_origem)
);

INSERT INTO staging.stg_gupe_patio
    (id_patio_origem, nome_patio, cidade, localizacao, id_sistema_origem)
SELECT
    p.id_patio::VARCHAR  AS id_patio_origem,
    p.nome               AS nome_patio,
    NULL::VARCHAR        AS cidade,       -- campo cidade inexistente; só endereco livre
    p.endereco           AS localizacao,
    'GRUPO_GUPESSANHA'
FROM gupessanha.patio p
ON CONFLICT (id_patio_origem) DO NOTHING;

-- =============================================================================
-- 2. stg_gupe_cliente
-- =============================================================================
-- Fonte: gupessanha.cliente
-- tipo_pessoa IN ('PF','PJ') mapeado para tipo_cliente.
-- cidade_origem disponível diretamente. Estado não existe no schema.

CREATE TABLE IF NOT EXISTS staging.stg_gupe_cliente (
    id_cliente_origem VARCHAR(50)  NOT NULL,
    tipo_cliente      CHAR(2)      NOT NULL,
    nome_cliente      VARCHAR(255) NOT NULL,
    cidade_origem     VARCHAR(100),
    estado_origem     CHAR(2),              -- NULL: ausente no schema gupessanha
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_GUPESSANHA',
    CONSTRAINT pk_stg_gupe_cliente PRIMARY KEY (id_cliente_origem),
    CONSTRAINT chk_stg_gupe_cli_tipo CHECK (tipo_cliente IN ('PF','PJ'))
);

INSERT INTO staging.stg_gupe_cliente
    (id_cliente_origem, tipo_cliente, nome_cliente,
     cidade_origem, estado_origem, id_sistema_origem)
SELECT
    c.id_cliente::VARCHAR  AS id_cliente_origem,
    c.tipo_pessoa          AS tipo_cliente,    -- 'PF'|'PJ' (mapeamento direto)
    c.nome                 AS nome_cliente,
    c.cidade_origem,
    NULL::CHAR(2)          AS estado_origem,   -- ausente no schema gupessanha
    'GRUPO_GUPESSANHA'
FROM gupessanha.cliente c
ON CONFLICT (id_cliente_origem) DO NOTHING;

-- =============================================================================
-- 3. stg_gupe_veiculo
-- =============================================================================
-- Fonte: gupessanha.veiculo JOIN gupessanha.grupo
-- Peculiaridades:
--   * mecanizacao → CHECK ('MANUAL','AUTOMATICA') — sufixo 'A'; normalizar em transform
--   * nome_grupo  → grupo.nome
--   * ano         → ano_fabricacao (campo disponível)
--   * ar_condicionado → tem_ar_condicionado (campo booleano)

CREATE TABLE IF NOT EXISTS staging.stg_gupe_veiculo (
    id_veiculo_origem VARCHAR(50)  NOT NULL,
    placa             VARCHAR(10)  NOT NULL,
    chassi            VARCHAR(30),
    marca             VARCHAR(50),
    modelo            VARCHAR(100) NOT NULL,
    ano               INT,
    cor               VARCHAR(30),
    ar_condicionado   BOOLEAN,
    nome_grupo        VARCHAR(100),
    mecanizacao       VARCHAR(20),  -- 'MANUAL'|'AUTOMATICA' — normalizar 'AUTOMATICA'→'AUTOMATICO' em transform
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_GUPESSANHA',
    CONSTRAINT pk_stg_gupe_veiculo PRIMARY KEY (id_veiculo_origem)
);

INSERT INTO staging.stg_gupe_veiculo
    (id_veiculo_origem, placa, chassi, marca, modelo, ano, cor,
     ar_condicionado, nome_grupo, mecanizacao, id_sistema_origem)
SELECT
    v.id_veiculo::VARCHAR   AS id_veiculo_origem,
    v.placa,
    v.chassi,
    v.marca,
    v.modelo,
    v.ano_fabricacao        AS ano,
    v.cor,
    v.tem_ar_condicionado   AS ar_condicionado,
    g.nome                  AS nome_grupo,
    v.mecanizacao,          -- 'MANUAL'|'AUTOMATICA'
    'GRUPO_GUPESSANHA'
FROM gupessanha.veiculo v
JOIN gupessanha.grupo   g ON g.id_grupo = v.grupo_id
ON CONFLICT (id_veiculo_origem) DO NOTHING;

-- =============================================================================
-- 4. stg_gupe_reserva
-- =============================================================================
-- Fonte: gupessanha.reserva
-- Schema mais completo: tem data_reserva, grupo_id, patio_retirada_id,
-- patio_devolucao_id e data_devolucao_prevista. Sem qt_veiculos_solicitados
-- (uma reserva = um veículo por design).
-- Campo estado (não status) com valores: 'CONFIRMADA','EM_FILA_ESPERA','CANCELADA','CONCRETIZADA'

CREATE TABLE IF NOT EXISTS staging.stg_gupe_reserva (
    id_reserva_origem          VARCHAR(50)  NOT NULL,
    id_cliente_origem          VARCHAR(50)  NOT NULL,
    id_grupo_origem            VARCHAR(50),
    id_patio_retirada_origem   VARCHAR(50),
    id_patio_devolucao_origem  VARCHAR(50),
    dt_reserva                 TIMESTAMP    NOT NULL,
    dt_retirada_prevista       TIMESTAMP    NOT NULL,
    dt_devolucao_prevista      TIMESTAMP    NOT NULL,
    qt_veiculos_solicitados    INT,                  -- NULL: uma reserva = um veículo (implícito)
    status                     VARCHAR(30)  NOT NULL, -- conteúdo: 'CONFIRMADA'|'EM_FILA_ESPERA'|...
    id_sistema_origem          VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_GUPESSANHA',
    CONSTRAINT pk_stg_gupe_reserva PRIMARY KEY (id_reserva_origem)
);

INSERT INTO staging.stg_gupe_reserva
    (id_reserva_origem, id_cliente_origem, id_grupo_origem,
     id_patio_retirada_origem, id_patio_devolucao_origem,
     dt_reserva, dt_retirada_prevista, dt_devolucao_prevista,
     qt_veiculos_solicitados, status, id_sistema_origem)
SELECT
    r.id_reserva::VARCHAR            AS id_reserva_origem,
    r.cliente_id::VARCHAR            AS id_cliente_origem,
    r.grupo_id::VARCHAR              AS id_grupo_origem,
    r.patio_retirada_id::VARCHAR     AS id_patio_retirada_origem,
    r.patio_devolucao_id::VARCHAR    AS id_patio_devolucao_origem,
    r.data_reserva,
    r.data_retirada_prevista         AS dt_retirada_prevista,
    r.data_devolucao_prevista        AS dt_devolucao_prevista,
    NULL::INT                        AS qt_veiculos_solicitados,  -- implícito: 1
    r.estado                         AS status,  -- campo chama-se 'estado' no OLTP
    'GRUPO_GUPESSANHA'
FROM gupessanha.reserva r
ON CONFLICT (id_reserva_origem) DO NOTHING;

-- =============================================================================
-- 5. stg_gupe_locacao
-- =============================================================================
-- Fonte: gupessanha.locacao
-- patio_devolucao_id NOT NULL: representa tanto o pátio planejado quanto o real.
-- Para locações 'EM_ANDAMENTO', é apenas planejado; para 'CONCLUIDA', é o real.
-- Ambiguidade documentada; o transform pode filtrar por status para usar o campo
-- apenas quando locacao.status = 'CONCLUIDA'.
-- valor_diaria_aplicada disponível diretamente.

CREATE TABLE IF NOT EXISTS staging.stg_gupe_locacao (
    id_locacao_origem          VARCHAR(50)   NOT NULL,
    id_reserva_origem          VARCHAR(50),            -- NULL para locações sem reserva
    id_cliente_origem          VARCHAR(50)   NOT NULL,
    id_veiculo_origem          VARCHAR(50)   NOT NULL,
    id_patio_retirada_origem   VARCHAR(50)   NOT NULL,
    id_patio_devolucao_origem  VARCHAR(50)   NOT NULL,  -- planejado (ou real se CONCLUIDA)
    dt_retirada                TIMESTAMP     NOT NULL,
    dt_devolucao_real          TIMESTAMP,               -- NULL se locação em andamento
    valor_diaria               NUMERIC(10,2) NOT NULL,
    id_sistema_origem          VARCHAR(50)   NOT NULL DEFAULT 'GRUPO_GUPESSANHA',
    CONSTRAINT pk_stg_gupe_locacao PRIMARY KEY (id_locacao_origem)
);

INSERT INTO staging.stg_gupe_locacao
    (id_locacao_origem, id_reserva_origem, id_cliente_origem,
     id_veiculo_origem, id_patio_retirada_origem, id_patio_devolucao_origem,
     dt_retirada, dt_devolucao_real, valor_diaria, id_sistema_origem)
SELECT
    l.id_locacao::VARCHAR           AS id_locacao_origem,
    l.reserva_id::VARCHAR           AS id_reserva_origem,
    l.cliente_id::VARCHAR           AS id_cliente_origem,
    l.veiculo_id::VARCHAR           AS id_veiculo_origem,
    l.patio_retirada_id::VARCHAR    AS id_patio_retirada_origem,
    l.patio_devolucao_id::VARCHAR   AS id_patio_devolucao_origem,
    l.data_retirada_real            AS dt_retirada,
    l.data_devolucao_real           AS dt_devolucao_real,
    l.valor_diaria_aplicada         AS valor_diaria,
    'GRUPO_GUPESSANHA'
FROM gupessanha.locacao l
ON CONFLICT (id_locacao_origem) DO NOTHING;

-- =============================================================================
-- 6. stg_gupe_movimentacao  [DERIVADA DE LOCACAO]
-- =============================================================================
-- Fonte: gupessanha.locacao (não existe tabela movimentacao_patio)
-- Derivação: cada locação CONCLUÍDA com data_devolucao_real preenchida representa
-- uma movimentação patio_retirada_id → patio_devolucao_id.
-- Referência: vw_movimentacao_patio definida no schema gupessanha usa este mesmo
-- critério (status = 'CONCLUIDA').
-- id_movimentacao_origem = 'LOC-' || id_locacao (prefixo para distinguir de IDs
-- de movimentação real de outros grupos).
-- dt_saida_origem = data_retirada_real (veículo saiu do pátio de retirada).
-- dt_chegada_destino = data_devolucao_real (veículo chegou ao pátio de devolução).

CREATE TABLE IF NOT EXISTS staging.stg_gupe_movimentacao (
    id_movimentacao_origem    VARCHAR(50)  NOT NULL,  -- 'LOC-{id_locacao}'
    id_veiculo_origem         VARCHAR(50)  NOT NULL,
    id_patio_origem_origem    VARCHAR(50)  NOT NULL,
    id_patio_destino_origem   VARCHAR(50)  NOT NULL,
    dt_saida_origem           TIMESTAMP    NOT NULL,
    dt_chegada_destino        TIMESTAMP    NOT NULL,
    id_sistema_origem         VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_GUPESSANHA',
    CONSTRAINT pk_stg_gupe_movimentacao PRIMARY KEY (id_movimentacao_origem)
);

INSERT INTO staging.stg_gupe_movimentacao
    (id_movimentacao_origem, id_veiculo_origem,
     id_patio_origem_origem, id_patio_destino_origem,
     dt_saida_origem, dt_chegada_destino, id_sistema_origem)
SELECT
    'LOC-' || l.id_locacao::VARCHAR   AS id_movimentacao_origem,
    l.veiculo_id::VARCHAR             AS id_veiculo_origem,
    l.patio_retirada_id::VARCHAR      AS id_patio_origem_origem,
    l.patio_devolucao_id::VARCHAR     AS id_patio_destino_origem,
    l.data_retirada_real              AS dt_saida_origem,
    l.data_devolucao_real             AS dt_chegada_destino
    -- id_sistema_origem usa DEFAULT
FROM gupessanha.locacao l
WHERE l.status = 'CONCLUIDA'
  AND l.data_devolucao_real IS NOT NULL
  AND l.patio_retirada_id <> l.patio_devolucao_id  -- exclui devoluções no mesmo pátio
ON CONFLICT (id_movimentacao_origem) DO NOTHING;
