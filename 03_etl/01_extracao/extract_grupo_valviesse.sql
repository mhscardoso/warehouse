-- =============================================================================
-- Arquivo  : 03_etl/01_extracao/extract_grupo_valviesse.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Extração do OLTP do Grupo Valviesse para o schema staging.
--            Cada tabela staging recebe um SELECT direto do schema fonte
--            (valviesse.*) sem transformação de negócio.
--
-- Cron recomendado: 0 4 * * *  (diário, às 04h00)
-- Justificativa: Idêntico aos demais grupos (alinhamento da janela de carga).
--   O schema valviesse é o mais completo dos quatro: tem movimentacao_patio
--   explícita, id_patio_devolucao_real separado e estado em cliente — portanto
--   não há derivações complexas aqui, apenas SELECTs diretos.
--
-- Pré-requisito: tabelas OLTP carregadas no schema 'valviesse' da mesma
--   instância PostgreSQL onde reside o DW.
--   Atenção: DDL fonte usa nomes em MAIÚSCULAS; PostgreSQL normaliza para
--   minúsculas sem aspas — queries usam nomes em minúsculas.
--
-- Peculiaridades do schema valviesse tratadas aqui:
--   * Cliente   → tabela unificada com tipo_cliente, cidade e estado diretamente
--   * Veículo   → mecanizacao 'MANUAL'|'AUTOMATICO' (já no formato DW)
--   * Pátio     → localizacao disponível; sem campo cidade isolado
--   * Reserva   → id_patio_devolucao_previsto (não id_patio_devolucao)
--   * Locação   → valor_previsto (total) e valor_final (total real); sem valor_diaria
--                  id_patio_devolucao_real separado de id_patio_devolucao_previsto
--   * Moviment. → tabela movimentacao_patio com pátios diretos (sem camada Vaga)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- =============================================================================
-- 1. stg_valv_patio
-- =============================================================================
-- Fonte: valviesse.patio
-- localizacao disponível diretamente. Sem campo cidade isolado.
-- Ambiguidade: localizacao (VARCHAR 150) contém o endereço completo; cidade
-- não está isolada. Decisão conservadora: cidade = NULL, localizacao = localizacao.

CREATE TABLE IF NOT EXISTS staging.stg_valv_patio (
    id_patio_origem   VARCHAR(50)  NOT NULL,
    nome_patio        VARCHAR(100) NOT NULL,
    cidade            VARCHAR(100),          -- NULL: ausente como campo isolado
    localizacao       VARCHAR(300),          -- localizacao do OLTP (endereço completo)
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_VALVIESSE',
    CONSTRAINT pk_stg_valv_patio PRIMARY KEY (id_patio_origem)
);

INSERT INTO staging.stg_valv_patio
    (id_patio_origem, nome_patio, cidade, localizacao, id_sistema_origem)
SELECT
    p.id_patio::VARCHAR  AS id_patio_origem,
    p.nome_patio,
    NULL::VARCHAR        AS cidade,      -- não existe campo cidade isolado em valviesse.patio
    p.localizacao,
    'GRUPO_VALVIESSE'
FROM valviesse.patio p
ON CONFLICT (id_patio_origem) DO NOTHING;

-- =============================================================================
-- 2. stg_valv_cliente
-- =============================================================================
-- Fonte: valviesse.cliente
-- Schema mais completo para cliente: tipo_cliente, cidade e estado disponíveis.
-- nome_razao_social mapeado para nome_cliente (cobre PF e PJ no mesmo campo).

CREATE TABLE IF NOT EXISTS staging.stg_valv_cliente (
    id_cliente_origem VARCHAR(50)  NOT NULL,
    tipo_cliente      CHAR(2)      NOT NULL,
    nome_cliente      VARCHAR(255) NOT NULL,
    cidade_origem     VARCHAR(100),
    estado_origem     CHAR(2),
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_VALVIESSE',
    CONSTRAINT pk_stg_valv_cliente PRIMARY KEY (id_cliente_origem),
    CONSTRAINT chk_stg_valv_cli_tipo CHECK (tipo_cliente IN ('PF','PJ'))
);

INSERT INTO staging.stg_valv_cliente
    (id_cliente_origem, tipo_cliente, nome_cliente,
     cidade_origem, estado_origem, id_sistema_origem)
SELECT
    c.id_cliente::VARCHAR   AS id_cliente_origem,
    c.tipo_cliente,                          -- 'PF'|'PJ' (mapeamento direto)
    c.nome_razao_social     AS nome_cliente, -- unifica nome PF e razão social PJ
    c.cidade                AS cidade_origem,
    c.estado                AS estado_origem, -- CHAR(2) disponível diretamente
    'GRUPO_VALVIESSE'
FROM valviesse.cliente c
ON CONFLICT (id_cliente_origem) DO NOTHING;

-- =============================================================================
-- 3. stg_valv_veiculo
-- =============================================================================
-- Fonte: valviesse.veiculo JOIN valviesse.grupo_veiculo
-- Todos os campos relevantes disponíveis. mecanizacao já em formato DW ('MANUAL'|'AUTOMATICO').
-- Ambiguidade: veiculo não tem campo ano (ano_fabricacao). Registrado como NULL.

CREATE TABLE IF NOT EXISTS staging.stg_valv_veiculo (
    id_veiculo_origem VARCHAR(50)  NOT NULL,
    placa             VARCHAR(10)  NOT NULL,
    chassi            VARCHAR(50),          -- VARCHAR(50) no OLTP valviesse
    marca             VARCHAR(50),
    modelo            VARCHAR(100) NOT NULL,
    ano               INT,                  -- NULL: campo ausente em valviesse.veiculo
    cor               VARCHAR(30),
    ar_condicionado   BOOLEAN,
    nome_grupo        VARCHAR(100),
    mecanizacao       VARCHAR(20),          -- 'MANUAL'|'AUTOMATICO' (já no formato DW)
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_VALVIESSE',
    CONSTRAINT pk_stg_valv_veiculo PRIMARY KEY (id_veiculo_origem)
);

INSERT INTO staging.stg_valv_veiculo
    (id_veiculo_origem, placa, chassi, marca, modelo, ano, cor,
     ar_condicionado, nome_grupo, mecanizacao, id_sistema_origem)
SELECT
    v.id_veiculo::VARCHAR   AS id_veiculo_origem,
    v.placa,
    v.chassi,
    v.marca,
    v.modelo,
    NULL::INT               AS ano,        -- ausente em valviesse.veiculo
    v.cor,
    v.ar_condicionado,
    gv.nome_grupo,
    v.mecanizacao,                         -- 'MANUAL'|'AUTOMATICO'
    'GRUPO_VALVIESSE'
FROM valviesse.veiculo       v
JOIN valviesse.grupo_veiculo gv ON gv.id_grupo = v.id_grupo
ON CONFLICT (id_veiculo_origem) DO NOTHING;

-- =============================================================================
-- 4. stg_valv_reserva
-- =============================================================================
-- Fonte: valviesse.reserva
-- Schema completo: data_reserva, grupo, patio_retirada e patio_devolucao_previsto.
-- Nota: coluna chama-se id_patio_devolucao_previsto (não id_patio_devolucao).
--       Mapeado para id_patio_devolucao_origem na staging.
-- status_reserva (campo no OLTP) mapeado para status.
-- CHECK no OLTP: status_reserva IN ('ATIVA','CANCELADA','CONVERTIDA')

CREATE TABLE IF NOT EXISTS staging.stg_valv_reserva (
    id_reserva_origem          VARCHAR(50)  NOT NULL,
    id_cliente_origem          VARCHAR(50)  NOT NULL,
    id_grupo_origem            VARCHAR(50),
    id_patio_retirada_origem   VARCHAR(50),
    id_patio_devolucao_origem  VARCHAR(50),           -- id_patio_devolucao_previsto do OLTP
    dt_reserva                 TIMESTAMP    NOT NULL,
    dt_retirada_prevista       TIMESTAMP    NOT NULL,
    dt_devolucao_prevista      TIMESTAMP    NOT NULL,
    qt_veiculos_solicitados    INT,                   -- NULL: uma reserva = um veículo
    status                     VARCHAR(30)  NOT NULL,
    id_sistema_origem          VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_VALVIESSE',
    CONSTRAINT pk_stg_valv_reserva PRIMARY KEY (id_reserva_origem)
);

INSERT INTO staging.stg_valv_reserva
    (id_reserva_origem, id_cliente_origem, id_grupo_origem,
     id_patio_retirada_origem, id_patio_devolucao_origem,
     dt_reserva, dt_retirada_prevista, dt_devolucao_prevista,
     qt_veiculos_solicitados, status, id_sistema_origem)
SELECT
    r.id_reserva::VARCHAR                 AS id_reserva_origem,
    r.id_cliente::VARCHAR                 AS id_cliente_origem,
    r.id_grupo::VARCHAR                   AS id_grupo_origem,
    r.id_patio_retirada::VARCHAR          AS id_patio_retirada_origem,
    r.id_patio_devolucao_previsto::VARCHAR AS id_patio_devolucao_origem,
    r.data_reserva::TIMESTAMP             AS dt_reserva,
    r.data_prev_retirada::TIMESTAMP       AS dt_retirada_prevista,
    r.data_prev_devolucao::TIMESTAMP      AS dt_devolucao_prevista,
    NULL::INT                             AS qt_veiculos_solicitados, -- implícito: 1
    r.status_reserva                      AS status,
    'GRUPO_VALVIESSE'
FROM valviesse.reserva r
ON CONFLICT (id_reserva_origem) DO NOTHING;

-- =============================================================================
-- 5. stg_valv_locacao
-- =============================================================================
-- Fonte: valviesse.locacao
-- Peculiaridades:
--   * id_patio_devolucao_real separado de id_patio_devolucao_previsto →
--     id_patio_devolucao_origem = id_patio_devolucao_real (NULL se em aberto)
--   * Sem valor_diaria: schema tem valor_previsto (total previsto) e valor_final
--     (total real); ambos incluídos como colunas separadas.
--   * data_hora_retirada = DT real de retirada (NOT NULL).
--   * data_hora_real_devolucao = DT real de devolução (NULL se em aberto).

CREATE TABLE IF NOT EXISTS staging.stg_valv_locacao (
    id_locacao_origem          VARCHAR(50)   NOT NULL,
    id_reserva_origem          VARCHAR(50),            -- NULL para walk-in
    id_cliente_origem          VARCHAR(50)   NOT NULL,
    id_veiculo_origem          VARCHAR(50)   NOT NULL,
    id_patio_retirada_origem   VARCHAR(50)   NOT NULL,
    id_patio_devolucao_origem  VARCHAR(50),            -- id_patio_devolucao_real (NULL se em aberto)
    dt_retirada                TIMESTAMP     NOT NULL,
    dt_devolucao_real          TIMESTAMP,              -- NULL se locação em aberto
    valor_previsto             NUMERIC(10,2) NOT NULL, -- total previsto (sem valor_diaria)
    valor_final                NUMERIC(10,2),          -- total real (NULL se em aberto)
    id_sistema_origem          VARCHAR(50)   NOT NULL DEFAULT 'GRUPO_VALVIESSE',
    CONSTRAINT pk_stg_valv_locacao PRIMARY KEY (id_locacao_origem)
);

INSERT INTO staging.stg_valv_locacao
    (id_locacao_origem, id_reserva_origem, id_cliente_origem,
     id_veiculo_origem, id_patio_retirada_origem, id_patio_devolucao_origem,
     dt_retirada, dt_devolucao_real, valor_previsto, valor_final, id_sistema_origem)
SELECT
    l.id_locacao::VARCHAR                 AS id_locacao_origem,
    l.id_reserva::VARCHAR                 AS id_reserva_origem,
    l.id_cliente::VARCHAR                 AS id_cliente_origem,
    l.id_veiculo::VARCHAR                 AS id_veiculo_origem,
    l.id_patio_retirada::VARCHAR          AS id_patio_retirada_origem,
    l.id_patio_devolucao_real::VARCHAR    AS id_patio_devolucao_origem, -- real (NULL se em aberto)
    l.data_hora_retirada                  AS dt_retirada,
    l.data_hora_real_devolucao            AS dt_devolucao_real,
    l.valor_previsto,
    l.valor_final,
    'GRUPO_VALVIESSE'
FROM valviesse.locacao l
ON CONFLICT (id_locacao_origem) DO NOTHING;

-- =============================================================================
-- 6. stg_valv_movimentacao
-- =============================================================================
-- Fonte: valviesse.movimentacao_patio
-- Pátios referenciados diretamente (id_patio_origem, id_patio_destino).
-- data_hora_movimentacao = timestamp único (sem separação saída/chegada como mhscardoso).
-- Mesmo padrão que tadeupires: dt_saida_origem = data_hora_movimentacao,
-- dt_chegada_destino = NULL (campo ausente).
-- motivo_movimentacao mapeado para coluna motivo no DW (via load_fatos.sql).

CREATE TABLE IF NOT EXISTS staging.stg_valv_movimentacao (
    id_movimentacao_origem    VARCHAR(50)  NOT NULL,
    id_veiculo_origem         VARCHAR(50)  NOT NULL,
    id_patio_origem_origem    VARCHAR(50)  NOT NULL,
    id_patio_destino_origem   VARCHAR(50)  NOT NULL,
    dt_saida_origem           TIMESTAMP    NOT NULL,  -- data_hora_movimentacao
    dt_chegada_destino        TIMESTAMP,              -- NULL: campo único no schema valviesse
    motivo                    VARCHAR(100),
    id_sistema_origem         VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_VALVIESSE',
    CONSTRAINT pk_stg_valv_movimentacao PRIMARY KEY (id_movimentacao_origem)
);

INSERT INTO staging.stg_valv_movimentacao
    (id_movimentacao_origem, id_veiculo_origem,
     id_patio_origem_origem, id_patio_destino_origem,
     dt_saida_origem, dt_chegada_destino, motivo, id_sistema_origem)
SELECT
    mp.id_movimentacao::VARCHAR     AS id_movimentacao_origem,
    mp.id_veiculo::VARCHAR          AS id_veiculo_origem,
    mp.id_patio_origem::VARCHAR     AS id_patio_origem_origem,
    mp.id_patio_destino::VARCHAR    AS id_patio_destino_origem,
    mp.data_hora_movimentacao       AS dt_saida_origem,
    NULL::TIMESTAMP                 AS dt_chegada_destino, -- campo único no schema valviesse
    mp.motivo_movimentacao          AS motivo,
    'GRUPO_VALVIESSE'
FROM valviesse.movimentacao_patio mp
ON CONFLICT (id_movimentacao_origem) DO NOTHING;
