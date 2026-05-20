-- =============================================================================
-- Arquivo  : 03_etl/03_carga/load_dimensoes.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Carrega as tabelas dim_* do schema dw a partir das tabelas std_*
--            do schema staging produzidas por transform_staging.sql.
--
-- Pré-requisito: transform_staging.sql já executado (std_* populadas).
-- Cron recomendado: 0 6 * * *  (após transform das 05h00)
--
-- Ordem obrigatória (dependências entre tabelas):
--   1. dim_tempo   — sem dependências externas; base para FKs nas fatos
--   2. dim_grupo   — sem dependências externas
--   3. dim_patio   — sem dependências externas
--   4. dim_cliente — sem dependências externas
--   5. dim_veiculo — sem dependências; nome_grupo incluído na std_veiculo
--                    para uso futuro no load_fatos (não armazenado em dim)
--
-- Idempotência: ON CONFLICT DO NOTHING em todos os INSERTs.
--   dim_tempo  : conflito em (sk_tempo)         — PK = YYYYMMDD
--   dim_grupo  : conflito em (id_sistema_origem, nome_grupo)  — chave natural
--   dim_patio  : conflito em (id_sistema_origem, id_patio_origem)
--   dim_cliente: conflito em (id_sistema_origem, id_cliente_origem)
--   dim_veiculo: conflito em (placa)             — UNIQUE v2; placa é única globalmente
--
-- Constraints de unicidade para dim_grupo, dim_patio e dim_cliente não
-- existem em create_dw_v2.sql — são adicionadas aqui idempotentemente
-- via blocos DO/EXCEPTION para que o ON CONFLICT funcione.
-- =============================================================================

-- =============================================================================
-- 0. Garantir schema alvo
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS dw;

-- =============================================================================
-- 0.1 Unique constraints para chaves naturais das dimensões
-- =============================================================================
-- Necessárias para que ON CONFLICT (colunas) funcione. Blocos DO/EXCEPTION
-- garantem idempotência (constraint já existente não gera erro).

DO $$
BEGIN
    ALTER TABLE dw.dim_grupo
        ADD CONSTRAINT uq_dim_grupo_natural UNIQUE (id_sistema_origem, nome_grupo);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE dw.dim_patio
        ADD CONSTRAINT uq_dim_patio_natural UNIQUE (id_sistema_origem, id_patio_origem);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE dw.dim_cliente
        ADD CONSTRAINT uq_dim_cliente_natural UNIQUE (id_sistema_origem, id_cliente_origem);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- dim_veiculo: UNIQUE(placa) já definido em create_dw_v2.sql (alteração v2).
-- dim_tempo  : UNIQUE(dt_ref) e PK(sk_tempo) já definidos em create_dw_v2.sql.

-- =============================================================================
-- 1. dim_tempo
-- =============================================================================
-- sk_tempo: inteiro no formato YYYYMMDD (ex.: 20240101).
-- Gerado diretamente via GENERATE_SERIES sobre o intervalo de datas encontrado
-- nas tabelas std_locacao, std_reserva e std_movimentacao.
--
-- Registro sentinela (99991231 / 9999-12-31): inserido primeiro para garantir
-- que sk_tempo_devolucao_prevista=NULL na carga de fato_locacao seja mapeado
-- para um SK válido (load_fatos.sql usa COALESCE(..., 99991231)).
--
-- nome_dia / nome_mes: calculados com CASE WHEN (em português, independente
-- da locale do servidor — TO_CHAR com TM dependeria de pt_BR estar instalado).

-- 1a. Sentinela — data-futura desconhecida para NULLs de devolução prevista
INSERT INTO dw.dim_tempo
    (sk_tempo, dt_ref, dia, mes, trimestre, semestre, ano,
     dia_semana, nome_dia, nome_mes, semana_ano, is_feriado)
SELECT
    99991231,
    DATE '9999-12-31',
    31::SMALLINT,
    12::SMALLINT,
    4::SMALLINT,
    2::SMALLINT,
    9999::SMALLINT,
    EXTRACT(ISODOW FROM DATE '9999-12-31')::SMALLINT,
    CASE EXTRACT(ISODOW FROM DATE '9999-12-31')
        WHEN 1 THEN 'Segunda-Feira' WHEN 2 THEN 'Terça-Feira'
        WHEN 3 THEN 'Quarta-Feira'  WHEN 4 THEN 'Quinta-Feira'
        WHEN 5 THEN 'Sexta-Feira'   WHEN 6 THEN 'Sábado'
        WHEN 7 THEN 'Domingo'
    END,
    'Dezembro',
    EXTRACT(WEEK FROM DATE '9999-12-31')::INT,
    FALSE
ON CONFLICT (sk_tempo) DO NOTHING;

-- 1b. Range de datas presente nos dados (GENERATE_SERIES)
-- Cobre todos os timestamps de todas as entidades: retirada, devolução,
-- reserva, previsões, movimentações (saída e chegada).
WITH todas_datas AS (
    SELECT dt_retirada::DATE           AS d FROM staging.std_locacao WHERE dt_retirada IS NOT NULL
    UNION
    SELECT dt_devolucao_real::DATE        FROM staging.std_locacao WHERE dt_devolucao_real IS NOT NULL
    UNION
    SELECT dt_devolucao_prevista::DATE    FROM staging.std_locacao WHERE dt_devolucao_prevista IS NOT NULL
    UNION
    -- para tadeupires dt_reserva=NULL; usa dt_retirada_prevista como proxy (gerado no load_fatos)
    SELECT COALESCE(dt_reserva, dt_retirada_prevista)::DATE
        FROM staging.std_reserva
        WHERE COALESCE(dt_reserva, dt_retirada_prevista) IS NOT NULL
    UNION
    SELECT dt_retirada_prevista::DATE     FROM staging.std_reserva WHERE dt_retirada_prevista IS NOT NULL
    UNION
    SELECT dt_devolucao_prevista::DATE    FROM staging.std_reserva WHERE dt_devolucao_prevista IS NOT NULL
    UNION
    SELECT dt_saida_origem::DATE          FROM staging.std_movimentacao WHERE dt_saida_origem IS NOT NULL
    UNION
    SELECT dt_chegada_destino::DATE       FROM staging.std_movimentacao WHERE dt_chegada_destino IS NOT NULL
),
limites AS (
    SELECT MIN(d) AS dt_ini, MAX(d) AS dt_fim FROM todas_datas
)
INSERT INTO dw.dim_tempo
    (sk_tempo, dt_ref, dia, mes, trimestre, semestre, ano,
     dia_semana, nome_dia, nome_mes, semana_ano, is_feriado)
SELECT
    TO_CHAR(t.d::DATE, 'YYYYMMDD')::INT             AS sk_tempo,
    t.d::DATE                                        AS dt_ref,
    EXTRACT(DAY     FROM t.d)::SMALLINT              AS dia,
    EXTRACT(MONTH   FROM t.d)::SMALLINT              AS mes,
    EXTRACT(QUARTER FROM t.d)::SMALLINT              AS trimestre,
    CASE WHEN EXTRACT(MONTH FROM t.d) <= 6
         THEN 1 ELSE 2 END::SMALLINT                 AS semestre,
    EXTRACT(YEAR    FROM t.d)::SMALLINT              AS ano,
    EXTRACT(ISODOW  FROM t.d)::SMALLINT              AS dia_semana,  -- 1=Seg..7=Dom (ISO 8601)
    CASE EXTRACT(ISODOW FROM t.d)
        WHEN 1 THEN 'Segunda-Feira' WHEN 2 THEN 'Terça-Feira'
        WHEN 3 THEN 'Quarta-Feira'  WHEN 4 THEN 'Quinta-Feira'
        WHEN 5 THEN 'Sexta-Feira'   WHEN 6 THEN 'Sábado'
        WHEN 7 THEN 'Domingo'
    END                                              AS nome_dia,
    CASE EXTRACT(MONTH FROM t.d)
        WHEN  1 THEN 'Janeiro'    WHEN  2 THEN 'Fevereiro' WHEN  3 THEN 'Março'
        WHEN  4 THEN 'Abril'      WHEN  5 THEN 'Maio'      WHEN  6 THEN 'Junho'
        WHEN  7 THEN 'Julho'      WHEN  8 THEN 'Agosto'    WHEN  9 THEN 'Setembro'
        WHEN 10 THEN 'Outubro'    WHEN 11 THEN 'Novembro'  WHEN 12 THEN 'Dezembro'
    END                                              AS nome_mes,
    EXTRACT(WEEK FROM t.d)::INT                      AS semana_ano,
    FALSE                                            AS is_feriado
FROM limites
CROSS JOIN LATERAL
    GENERATE_SERIES(limites.dt_ini, limites.dt_fim, '1 day'::INTERVAL) AS t(d)
ON CONFLICT (sk_tempo) DO NOTHING;

-- =============================================================================
-- 2. dim_grupo
-- =============================================================================
-- Fonte: staging.std_grupo (DISTINCT por ramo de sistema, gerado no transform).
-- Chave natural: (id_sistema_origem, nome_grupo).
-- id_grupo_origem = NULL para todos os sistemas — o extract de veiculo não
-- preservou o ID do grupo (apenas nome_grupo via JOIN). O load_fatos.sql
-- usa (id_sistema_origem, nome_grupo) para resolver sk_grupo.
--
-- classe_luxo / valor_diaria_base: NULL para todos os sistemas neste pipeline
-- (campos presentes em gupessanha.grupo mas não capturados no extract).

INSERT INTO dw.dim_grupo
    (id_grupo_origem, nome_grupo, mecanizacao, classe_luxo, valor_diaria_base, id_sistema_origem)
SELECT
    g.id_grupo_origem,     -- NULL: não capturado no extract de veiculo
    g.nome_grupo,
    g.mecanizacao,         -- 'MANUAL'|'AUTOMATICO' ou NULL (mhscardoso)
    g.classe_luxo,         -- NULL para todos os sistemas neste pipeline
    g.valor_diaria_base,   -- NULL para todos os sistemas neste pipeline
    g.id_sistema_origem
FROM staging.std_grupo g
ON CONFLICT (id_sistema_origem, nome_grupo) DO NOTHING;

-- =============================================================================
-- 3. dim_patio
-- =============================================================================
-- Chave natural: (id_sistema_origem, id_patio_origem).
-- localizacao: NULL para tadeupires (ausente no OLTP).
-- cidade: NULL para gupessanha e valviesse (campo isolado ausente).

INSERT INTO dw.dim_patio
    (id_patio_origem, nome_patio, cidade, localizacao, id_sistema_origem)
SELECT
    p.id_patio_origem,
    p.nome_patio,
    p.cidade,        -- NULL para gupessanha e valviesse
    p.localizacao,   -- NULL para tadeupires
    p.id_sistema_origem
FROM staging.std_patio p
ON CONFLICT (id_sistema_origem, id_patio_origem) DO NOTHING;

-- =============================================================================
-- 4. dim_cliente
-- =============================================================================
-- Chave natural: (id_sistema_origem, id_cliente_origem).
-- tipo_cliente: sempre 'PF'|'PJ' (normalizado no transform).
-- estado_origem: NULL para tadeupires e gupessanha (ausente nos OLTPs).

INSERT INTO dw.dim_cliente
    (id_cliente_origem, nome_cliente, tipo_cliente, cidade_origem, estado_origem, id_sistema_origem)
SELECT
    c.id_cliente_origem,
    c.nome_cliente,
    c.tipo_cliente,    -- 'PF'|'PJ'
    c.cidade_origem,
    c.estado_origem,   -- NULL para tadeupires e gupessanha
    c.id_sistema_origem
FROM staging.std_cliente c
ON CONFLICT (id_sistema_origem, id_cliente_origem) DO NOTHING;

-- =============================================================================
-- 5. dim_veiculo
-- =============================================================================
-- Chave de conflito: (placa) — UNIQUE adicionado na v2 de create_dw_v2.sql.
-- Garante que o mesmo veículo físico não seja duplicado mesmo que apareça
-- em recargas ou (improvável) em dois sistemas com a mesma placa.
--
-- Campos excluídos do INSERT (existem em std_veiculo mas não em dim_veiculo):
--   nome_grupo  — usado pelo load_fatos.sql para resolver sk_grupo em dim_grupo
--   mecanizacao — idem; armazenado em dim_grupo, não em dim_veiculo
--
-- Campos ausentes por sistema (carregados como NULL):
--   marca, cor        → mhscardoso
--   ano               → tadeupires e valviesse

INSERT INTO dw.dim_veiculo
    (id_veiculo_origem, placa, chassi, marca, modelo, ano, cor, ar_condicionado, id_sistema_origem)
SELECT
    v.id_veiculo_origem,
    v.placa,
    v.chassi,
    v.marca,               -- NULL para mhscardoso
    v.modelo,
    v.ano::SMALLINT,       -- NULL para tadeupires e valviesse; cast INT→SMALLINT
    v.cor,                 -- NULL para mhscardoso
    v.ar_condicionado,
    v.id_sistema_origem
FROM staging.std_veiculo v
ON CONFLICT (placa) DO NOTHING;
