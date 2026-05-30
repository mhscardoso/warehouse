-- =============================================================================
-- Trabalho desenvolvido pelos alunos da UFRJ.
-- Período: 2026.1
-- Cadeira: BigData
-- Integrantes:                                    
-- 
--           Lucas Garcia Santiago de Abreu          - DRE: 121039536
--           Matheus Henrique Sant’ Anna Cardoso     - DRE: 121073530
--           Patrick Mucio Rodrigues Pereira         - DRE: 120055979
-- =============================================================================

-- =============================================================================
-- Arquivo  : 03_etl/01_extracao/extract_grupo_tadeupires.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Extração do OLTP do Grupo Tadeupires para o schema staging.
--            Cada tabela staging recebe um SELECT direto do schema fonte
--            (tadeupires.*) sem transformação de negócio.
--
-- Cron recomendado: 0 4 * * *  (diário, às 04h00)
-- Justificativa: Mesmo raciocínio do mhscardoso — pico de transações entre
--   07h e 22h; janela de 04h garante captura do dia anterior. Os outros
--   grupos usam o mesmo horário para manter consistência na janela de
--   carga do DW (todos os staging devem estar prontos antes do transform).
--
-- Pré-requisito: tabelas OLTP carregadas no schema 'tadeupires' da mesma
--   instância PostgreSQL onde reside o DW.
--
-- Peculiaridades do schema tadeupires tratadas aqui:
--   * Cliente   → tabela unificada (tipo 'PF'|'PJ'); sem campo estado
--   * Veículo   → sem campo ano; mecanizacao em minúsculas ('manual'|'automatico')
--   * Pátio     → sem campo localizacao (apenas nome e cidade)
--   * Reserva   → sem data_reserva; data_inicio=retirada prevista, data_fim=devolucao prevista
--   * Locação   → sem valor_diaria; id_cliente via condutor→cliente (reserva_id nullable)
--                  patio_devolucao_id presente mesmo para locações em aberto (planejado ≠ real)
--   * Moviment. → tabela movimentacao_patio com pátios diretos (sem camada Vaga)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- =============================================================================
-- 1. stg_tade_patio
-- =============================================================================
-- Fonte: tadeupires.patio
-- Pátio tem apenas nome e cidade — localizacao não está disponível neste schema.

CREATE TABLE IF NOT EXISTS staging.stg_tade_patio (
    id_patio_origem   VARCHAR(50)  NOT NULL,
    nome_patio        VARCHAR(100) NOT NULL,
    cidade            VARCHAR(100),
    localizacao       VARCHAR(300),           -- NULL: ausente no schema tadeupires
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_TADEUPIRES',
    CONSTRAINT pk_stg_tade_patio PRIMARY KEY (id_patio_origem)
);

INSERT INTO staging.stg_tade_patio
    (id_patio_origem, nome_patio, cidade, localizacao, id_sistema_origem)
SELECT
    p.id::VARCHAR     AS id_patio_origem,
    p.nome            AS nome_patio,
    p.cidade,
    NULL::VARCHAR     AS localizacao,  -- ausente no schema tadeupires
    'GRUPO_TADEUPIRES'
FROM tadeupires.patio p
ON CONFLICT (id_patio_origem) DO NOTHING;

-- =============================================================================
-- 2. stg_tade_cliente
-- =============================================================================
-- Fonte: tadeupires.cliente
-- Tipo já vem como 'PF'|'PJ' (CHECK no OLTP). Sem campo estado — apenas cidade.

CREATE TABLE IF NOT EXISTS staging.stg_tade_cliente (
    id_cliente_origem VARCHAR(50)  NOT NULL,
    tipo_cliente      CHAR(2)      NOT NULL,
    nome_cliente      VARCHAR(255) NOT NULL,
    cidade_origem     VARCHAR(100),
    estado_origem     CHAR(2),              -- NULL: ausente no schema tadeupires
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_TADEUPIRES',
    CONSTRAINT pk_stg_tade_cliente PRIMARY KEY (id_cliente_origem),
    CONSTRAINT chk_stg_tade_cli_tipo CHECK (tipo_cliente IN ('PF','PJ'))
);

INSERT INTO staging.stg_tade_cliente
    (id_cliente_origem, tipo_cliente, nome_cliente,
     cidade_origem, estado_origem, id_sistema_origem)
SELECT
    c.id::VARCHAR    AS id_cliente_origem,
    c.tipo           AS tipo_cliente,
    c.nome           AS nome_cliente,
    c.cidade         AS cidade_origem,
    NULL::CHAR(2)    AS estado_origem,  -- ausente no schema tadeupires
    'GRUPO_TADEUPIRES'
FROM tadeupires.cliente c
ON CONFLICT (id_cliente_origem) DO NOTHING;

-- =============================================================================
-- 3. stg_tade_veiculo
-- =============================================================================
-- Fonte: tadeupires.veiculo JOIN tadeupires.grupo_veiculo
-- Peculiaridades:
--   * ano       → NULL (campo ausente em tadeupires.veiculo)
--   * mecanizacao → valores 'manual'|'automatico' (minúsculas); normalização no transform
--   * nome_grupo  → grupo_veiculo.nome

CREATE TABLE IF NOT EXISTS staging.stg_tade_veiculo (
    id_veiculo_origem VARCHAR(50)  NOT NULL,
    placa             VARCHAR(10)  NOT NULL,
    chassi            VARCHAR(30),
    marca             VARCHAR(50),
    modelo            VARCHAR(100) NOT NULL,
    ano               INT,                  -- NULL: ausente no schema tadeupires
    cor               VARCHAR(30),
    ar_condicionado   BOOLEAN,
    nome_grupo        VARCHAR(100),
    mecanizacao       VARCHAR(20),          -- 'manual'|'automatico' — normalizar em transform
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_TADEUPIRES',
    CONSTRAINT pk_stg_tade_veiculo PRIMARY KEY (id_veiculo_origem)
);

INSERT INTO staging.stg_tade_veiculo
    (id_veiculo_origem, placa, chassi, marca, modelo, ano, cor,
     ar_condicionado, nome_grupo, mecanizacao, id_sistema_origem)
SELECT
    v.id::VARCHAR          AS id_veiculo_origem,
    v.placa,
    v.chassi,
    v.marca,
    v.modelo,
    NULL::INT              AS ano,         -- ausente no schema tadeupires
    v.cor,
    v.ar_condicionado,
    gv.nome                AS nome_grupo,
    v.tipo_mecanizacao     AS mecanizacao, -- 'manual'|'automatico' (minúsculas)
    'GRUPO_TADEUPIRES'
FROM tadeupires.veiculo     v
JOIN tadeupires.grupo_veiculo gv ON gv.id = v.grupo_id
ON CONFLICT (id_veiculo_origem) DO NOTHING;

-- =============================================================================
-- 4. stg_tade_reserva
-- =============================================================================
-- Fonte: tadeupires.reserva
-- Peculiaridades:
--   * dt_reserva (quando a reserva foi criada) → NULL (campo ausente; só há
--     data_inicio=retirada prevista e data_fim=devolucao prevista)
--   * id_patio_devolucao_origem → presente (patio_devolucao_id na reserva)
--   * qt_veiculos_solicitados → NULL (campo ausente; tadeupires reserva é por veículo)

CREATE TABLE IF NOT EXISTS staging.stg_tade_reserva (
    id_reserva_origem          VARCHAR(50)  NOT NULL,
    id_cliente_origem          VARCHAR(50)  NOT NULL,
    id_grupo_origem            VARCHAR(50),
    id_patio_retirada_origem   VARCHAR(50),
    id_patio_devolucao_origem  VARCHAR(50),
    dt_reserva                 TIMESTAMP,           -- NULL: data de criação ausente no schema
    dt_retirada_prevista       TIMESTAMP    NOT NULL,
    dt_devolucao_prevista      TIMESTAMP    NOT NULL,
    qt_veiculos_solicitados    INT,                 -- NULL: campo ausente (reserva por veículo)
    status                     VARCHAR(30)  NOT NULL,
    id_sistema_origem          VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_TADEUPIRES',
    CONSTRAINT pk_stg_tade_reserva PRIMARY KEY (id_reserva_origem)
);

INSERT INTO staging.stg_tade_reserva
    (id_reserva_origem, id_cliente_origem, id_grupo_origem,
     id_patio_retirada_origem, id_patio_devolucao_origem,
     dt_reserva, dt_retirada_prevista, dt_devolucao_prevista,
     qt_veiculos_solicitados, status, id_sistema_origem)
SELECT
    r.id::VARCHAR                 AS id_reserva_origem,
    r.cliente_id::VARCHAR         AS id_cliente_origem,
    r.grupo_id::VARCHAR           AS id_grupo_origem,
    r.patio_retirada_id::VARCHAR  AS id_patio_retirada_origem,
    r.patio_devolucao_id::VARCHAR AS id_patio_devolucao_origem,
    NULL::TIMESTAMP               AS dt_reserva,              -- data de criação ausente
    r.data_inicio::TIMESTAMP      AS dt_retirada_prevista,    -- data_inicio = retirada planejada
    r.data_fim::TIMESTAMP         AS dt_devolucao_prevista,   -- data_fim = devolucao planejada
    NULL::INT                     AS qt_veiculos_solicitados, -- não se aplica (reserva por veículo)
    r.status,
    'GRUPO_TADEUPIRES'
FROM tadeupires.reserva r
ON CONFLICT (id_reserva_origem) DO NOTHING;

-- =============================================================================
-- 5. stg_tade_locacao
-- =============================================================================
-- Fonte: tadeupires.locacao
--        JOIN tadeupires.condutor → tadeupires.cliente (para resolver id_cliente)
--        LEFT JOIN tadeupires.cobranca (para obter valor total — sem valor_diaria no OLTP)
-- Peculiaridades:
--   * id_cliente_origem → via condutor.cliente_id (condutor_id é NOT NULL em locacao;
--     reserva_id é nullable e não pode ser usado como caminho primário)
--   * valor_diaria → ausente; incluído como valor_total de cobranca (LEFT JOIN, nullable)
--   * patio_devolucao_id → NOT NULL mesmo para locações em aberto; representa pátio
--     planejado. Para status='concluida', equivale ao pátio real de devolução.
--     Ambiguidade registrada; normalização de real vs planejado no transform.
--   * dt_retirada → data_retirada_realizada (nullable: NULL se ainda não retirado)

CREATE TABLE IF NOT EXISTS staging.stg_tade_locacao (
    id_locacao_origem          VARCHAR(50)   NOT NULL,
    id_reserva_origem          VARCHAR(50),           -- NULL para walk-in (sem reserva)
    id_cliente_origem          VARCHAR(50)   NOT NULL,
    id_veiculo_origem          VARCHAR(50)   NOT NULL,
    id_patio_retirada_origem   VARCHAR(50)   NOT NULL,
    id_patio_devolucao_origem  VARCHAR(50)   NOT NULL, -- planejado (ou real, se concluída)
    dt_retirada                TIMESTAMP,              -- NULL se locação ainda não iniciada
    dt_devolucao_real          TIMESTAMP,              -- NULL se locação em aberto
    valor_total                NUMERIC(10,2),          -- de cobranca; NULL se sem cobrança
    id_sistema_origem          VARCHAR(50)   NOT NULL DEFAULT 'GRUPO_TADEUPIRES',
    CONSTRAINT pk_stg_tade_locacao PRIMARY KEY (id_locacao_origem)
);

INSERT INTO staging.stg_tade_locacao
    (id_locacao_origem, id_reserva_origem, id_cliente_origem,
     id_veiculo_origem, id_patio_retirada_origem, id_patio_devolucao_origem,
     dt_retirada, dt_devolucao_real, valor_total, id_sistema_origem)
SELECT
    l.id::VARCHAR                    AS id_locacao_origem,
    l.reserva_id::VARCHAR            AS id_reserva_origem,      -- NULL para walk-in
    cd.cliente_id::VARCHAR           AS id_cliente_origem,      -- locacao→condutor→cliente
    l.veiculo_id::VARCHAR            AS id_veiculo_origem,
    l.patio_retirada_id::VARCHAR     AS id_patio_retirada_origem,
    l.patio_devolucao_id::VARCHAR    AS id_patio_devolucao_origem,
    l.data_retirada_realizada        AS dt_retirada,            -- NULL se não retirado ainda
    l.data_devolucao_realizada       AS dt_devolucao_real,
    cb.valor                         AS valor_total,            -- NULL se sem cobrança registrada
    'GRUPO_TADEUPIRES'
FROM tadeupires.locacao     l
JOIN tadeupires.condutor    cd ON cd.id       = l.condutor_id
LEFT JOIN tadeupires.cobranca cb ON cb.locacao_id = l.id
ON CONFLICT (id_locacao_origem) DO NOTHING;

-- =============================================================================
-- 6. stg_tade_movimentacao
-- =============================================================================
-- Fonte: tadeupires.movimentacao_patio
-- Pátios referenciados diretamente (sem camada Vaga).
-- Ambos os campos de pátio são NOT NULL na fonte.
-- dt_saida_origem ≈ data_movimentacao (ponto único de registro temporal).

CREATE TABLE IF NOT EXISTS staging.stg_tade_movimentacao (
    id_movimentacao_origem    VARCHAR(50)  NOT NULL,
    id_veiculo_origem         VARCHAR(50)  NOT NULL,
    id_patio_origem_origem    VARCHAR(50)  NOT NULL,
    id_patio_destino_origem   VARCHAR(50)  NOT NULL,
    dt_saida_origem           TIMESTAMP    NOT NULL,  -- data_movimentacao
    dt_chegada_destino        TIMESTAMP,              -- NULL: sem campo separado no schema
    id_sistema_origem         VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_TADEUPIRES',
    CONSTRAINT pk_stg_tade_movimentacao PRIMARY KEY (id_movimentacao_origem)
);

-- Ambiguidade: movimentacao_patio tem apenas data_movimentacao (um único timestamp);
-- não há distinção entre saída e chegada. Registrado como dt_saida_origem;
-- dt_chegada_destino fica NULL. A normalização no transform pode duplicar
-- o valor se necessário.
INSERT INTO staging.stg_tade_movimentacao
    (id_movimentacao_origem, id_veiculo_origem,
     id_patio_origem_origem, id_patio_destino_origem,
     dt_saida_origem, dt_chegada_destino, id_sistema_origem)
SELECT
    mp.id::VARCHAR                AS id_movimentacao_origem,
    mp.veiculo_id::VARCHAR        AS id_veiculo_origem,
    mp.origem_patio_id::VARCHAR   AS id_patio_origem_origem,
    mp.destino_patio_id::VARCHAR  AS id_patio_destino_origem,
    mp.data_movimentacao          AS dt_saida_origem,
    NULL::TIMESTAMP               AS dt_chegada_destino,  -- campo único no schema tadeupires
    'GRUPO_TADEUPIRES'
FROM tadeupires.movimentacao_patio mp
ON CONFLICT (id_movimentacao_origem) DO NOTHING;
