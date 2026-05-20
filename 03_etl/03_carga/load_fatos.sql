-- =============================================================================
-- Arquivo  : 03_etl/03_carga/load_fatos.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Carrega as tabelas fato_* do schema dw a partir das std_*
--            do schema staging. Todas as surrogate keys são resolvidas via
--            LEFT JOIN + WHERE sk IS NOT NULL (linhas sem match são descartadas).
--
-- Pré-requisito: load_dimensoes.sql já executado (dim_* populadas).
-- Cron recomendado: 0 7 * * *  (após carga de dimensões das 06h00)
--
-- IDEMPOTÊNCIA — estratégia por tabela fato:
--   As tabelas fato_* em create_dw_v2.sql não possuem colunas de chave de
--   negócio (id_locacao_origem, etc.), impossibilitando ON CONFLICT sobre chave
--   natural. Este script adiciona essas colunas e os índices UNIQUE necessários
--   idempotentemente via DO/EXCEPTION antes de cada INSERT, permitindo re-execuções
--   seguras sem TRUNCATE.
--
-- PADRÃO DE SKIP (LEFT JOIN + WHERE sk IS NOT NULL):
--   Todos os JOINs com dimensões são LEFT JOIN. Linhas cujo sk obrigatório
--   resultar NULL após o JOIN são descartadas pelo filtro WHERE. Isso evita
--   que falhas de resolução de SK quebrem o pipeline e documenta o volume
--   de descarte esperado nos comentários de cada seção.
--
-- sk_tempo: calculado como TO_CHAR(data::DATE, 'YYYYMMDD')::INT (= YYYYMMDD).
--   Não é necessário JOIN com dim_tempo para obter o SK — ele é deduzível
--   diretamente da data, e dim_tempo foi populada com exatamente esse range.
--
-- SENTINELA dim_tempo 99991231 (9999-12-31):
--   Usada para sk_tempo_devolucao_prevista quando dt_devolucao_prevista IS NULL
--   (mhscardoso e valviesse — campo não capturado no extract de locacao).
--   Inserida por load_dimensoes.sql antes do GENERATE_SERIES.
-- =============================================================================

-- =============================================================================
-- 0. Colunas de rastreabilidade e constraints para idempotência
-- =============================================================================
-- Adicionadas às fato_* para suportar ON CONFLICT em re-execuções.
-- DO/EXCEPTION torna cada operação idempotente.

-- fato_locacao ----------------------------------------------------------------
DO $$
BEGIN
    ALTER TABLE dw.fato_locacao ADD COLUMN id_locacao_origem VARCHAR(50);
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE dw.fato_locacao
        ADD CONSTRAINT uq_fato_locacao_src UNIQUE (id_sistema_origem, id_locacao_origem);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- fato_reserva ----------------------------------------------------------------
DO $$
BEGIN
    ALTER TABLE dw.fato_reserva ADD COLUMN id_reserva_origem VARCHAR(50);
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE dw.fato_reserva
        ADD CONSTRAINT uq_fato_reserva_src UNIQUE (id_sistema_origem, id_reserva_origem);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- fato_movimentacao_patio -----------------------------------------------------
DO $$
BEGIN
    ALTER TABLE dw.fato_movimentacao_patio ADD COLUMN id_movimentacao_origem VARCHAR(50);
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE dw.fato_movimentacao_patio
        ADD CONSTRAINT uq_fato_mov_src UNIQUE (id_sistema_origem, id_movimentacao_origem);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- fato_movimentacao_patio: quantidade_veiculos (sempre 1; cada linha = 1 veículo)
DO $$
BEGIN
    ALTER TABLE dw.fato_movimentacao_patio
        ADD COLUMN quantidade_veiculos INT NOT NULL DEFAULT 1;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- =============================================================================
-- 1. fato_locacao
-- =============================================================================
-- Grão: uma linha por locação (contrato de retirada de veículo).
--
-- Resolução de surrogate keys:
--   sk_cliente   → dim_cliente ON (id_sistema_origem, id_cliente_origem)
--   sk_veiculo   → dim_veiculo ON (id_sistema_origem, id_veiculo_origem)
--   sk_grupo     → dim_grupo   ON (id_sistema_origem, nome_grupo)
--                  nome_grupo disponível em std_locacao (JOIN com veiculo no transform)
--   sk_patio_ret → dim_patio   ON (id_sistema_origem, id_patio_retirada_origem)
--   sk_patio_dev → dim_patio   ON (id_sistema_origem, id_patio_devolucao_origem)
--                  LEFT JOIN; NULL para locações em aberto (id_patio_devolucao_origem=NULL)
--   sk_tempo_retirada           → YYYYMMDD de dt_retirada
--   sk_tempo_devolucao          → YYYYMMDD de dt_devolucao_real  (NULL se em aberto)
--   sk_tempo_devolucao_prevista → YYYYMMDD de dt_devolucao_prevista; COALESCE(., 99991231)
--                  para mhscardoso (Reserva sem DtDevolucaoPrevista) e
--                  valviesse (data_hora_prev_devolucao não capturada no extract)
--
-- valor_diaria (NOT NULL em fato_locacao):
--   Fonte primária: std_locacao.valor_diaria (mhscardoso e gupessanha)
--   Fallback:       valor_total / NULLIF(dias_locacao, 0) (tadeupires e valviesse)
--   SKIP estimado:  locações em aberto de tadeupires sem cobrança E valviesse
--                   sem valor_previsto → estimativa < 5% dos registros
--
-- valor_total:
--   Fonte primária: std_locacao.valor_total
--   Fallback:       valor_diaria * dias_locacao (para mhscardoso e gupessanha)
--
-- dias_locacao: calculado no transform (std_locacao.dias_locacao).
-- km_rodados: NULL para todos os sistemas (não capturado no extract).

INSERT INTO dw.fato_locacao (
    id_locacao_origem,
    sk_cliente,
    sk_veiculo,
    sk_grupo,
    sk_patio_retirada,
    sk_patio_devolucao,
    sk_tempo_retirada,
    sk_tempo_devolucao,
    sk_tempo_devolucao_prevista,
    valor_diaria,
    dias_locacao,
    km_rodados,
    valor_total,
    status,
    id_sistema_origem
)
SELECT
    l.id_locacao_origem,
    dc.sk_cliente,
    dv.sk_veiculo,
    dg.sk_grupo,
    dp_ret.sk_patio                                AS sk_patio_retirada,
    dp_dev.sk_patio                                AS sk_patio_devolucao,  -- NULL se em aberto

    -- sk_tempo calculado diretamente como YYYYMMDD; dim_tempo já contém o range completo
    TO_CHAR(l.dt_retirada::DATE, 'YYYYMMDD')::INT  AS sk_tempo_retirada,

    CASE WHEN l.dt_devolucao_real IS NOT NULL
         THEN TO_CHAR(l.dt_devolucao_real::DATE, 'YYYYMMDD')::INT
    END                                            AS sk_tempo_devolucao,  -- NULL se em aberto

    -- sentinela 99991231 para mhscardoso e valviesse (dt_devolucao_prevista=NULL no staging)
    COALESCE(
        CASE WHEN l.dt_devolucao_prevista IS NOT NULL
             THEN TO_CHAR(l.dt_devolucao_prevista::DATE, 'YYYYMMDD')::INT
        END,
        99991231
    )                                              AS sk_tempo_devolucao_prevista,

    -- valor_diaria NOT NULL: fallback para tadeupires (só valor_total) e valviesse (só totais)
    COALESCE(
        l.valor_diaria,
        l.valor_total / NULLIF(l.dias_locacao, 0)
    )                                              AS valor_diaria,

    l.dias_locacao,
    l.km_rodados,                                  -- NULL para todos os sistemas

    -- valor_total: prefer explícito; fallback calculado para mhscardoso/gupessanha em aberto
    COALESCE(l.valor_total, l.valor_diaria * l.dias_locacao) AS valor_total,

    l.status,
    l.id_sistema_origem

FROM staging.std_locacao l

-- sk_cliente: SKIP se cliente não encontrado em dim_cliente
LEFT JOIN dw.dim_cliente dc
    ON  dc.id_cliente_origem  = l.id_cliente_origem
    AND dc.id_sistema_origem  = l.id_sistema_origem

-- sk_veiculo: SKIP se veículo não encontrado em dim_veiculo
LEFT JOIN dw.dim_veiculo dv
    ON  dv.id_veiculo_origem  = l.id_veiculo_origem
    AND dv.id_sistema_origem  = l.id_sistema_origem

-- sk_grupo: resolução via nome_grupo (id_grupo_origem=NULL em dim_grupo)
-- SKIP se grupo não encontrado — pode ocorrer para veículos sem grupo definido
LEFT JOIN dw.dim_grupo dg
    ON  dg.nome_grupo        = l.nome_grupo
    AND dg.id_sistema_origem = l.id_sistema_origem

-- sk_patio_retirada: SKIP se pátio não encontrado
LEFT JOIN dw.dim_patio dp_ret
    ON  dp_ret.id_patio_origem  = l.id_patio_retirada_origem
    AND dp_ret.id_sistema_origem = l.id_sistema_origem

-- sk_patio_devolucao: LEFT JOIN permitido (NULL para locações em aberto)
LEFT JOIN dw.dim_patio dp_dev
    ON  dp_dev.id_patio_origem  = l.id_patio_devolucao_origem
    AND dp_dev.id_sistema_origem = l.id_sistema_origem
    AND l.id_patio_devolucao_origem IS NOT NULL

WHERE dc.sk_cliente  IS NOT NULL   -- SKIP: cliente ausente em dim_cliente
  AND dv.sk_veiculo  IS NOT NULL   -- SKIP: veículo ausente em dim_veiculo
  AND dg.sk_grupo    IS NOT NULL   -- SKIP: grupo ausente em dim_grupo
  AND dp_ret.sk_patio IS NOT NULL  -- SKIP: pátio de retirada ausente em dim_patio
  -- SKIP: valor_diaria irresolvível (locações em aberto sem cobrança nem valor_previsto)
  -- Estimativa: < 5% dos registros de tadeupires walk-in e valviesse sem valor_previsto
  AND COALESCE(l.valor_diaria, l.valor_total / NULLIF(l.dias_locacao, 0)) IS NOT NULL

ON CONFLICT (id_sistema_origem, id_locacao_origem) DO NOTHING;

-- =============================================================================
-- 2. fato_reserva
-- =============================================================================
-- Grão: uma linha por reserva.
--
-- Resolução de surrogate keys:
--   sk_cliente              → dim_cliente ON (id_sistema_origem, id_cliente_origem)
--   sk_grupo                → NULL para todos os sistemas — std_reserva tem
--                             id_grupo_origem mas dim_grupo usa nome_grupo como
--                             chave natural (id_grupo_origem=NULL na staging).
--                             Limitação do pipeline: extract de veiculo não
--                             preservou id_grupo. Aceito pois sk_grupo é nullable.
--   sk_patio_retirada       → dim_patio; NULL para mhscardoso (ausente em Reserva)
--   sk_patio_devolucao      → dim_patio; NULL para mhscardoso
--   sk_tempo_reserva        → YYYYMMDD de COALESCE(dt_reserva, dt_retirada_prevista)
--                             Para tadeupires (dt_reserva=NULL), usa dt_retirada_prevista
--                             como proxy da data de criação da reserva.
--   sk_tempo_retirada_prev  → YYYYMMDD de dt_retirada_prevista (NOT NULL)
--   sk_tempo_devolucao_prev → YYYYMMDD de dt_devolucao_prevista; NULL para mhscardoso
--
-- antecedencia_dias: da std_reserva diretamente (já calculado no transform).
--   NULL para tadeupires (dt_reserva=NULL → cálculo impossível).
--
-- qt_veiculos_solicitados NOT NULL: COALESCE(., 1) — NULL na staging = implícito 1.

INSERT INTO dw.fato_reserva (
    id_reserva_origem,
    sk_cliente,
    sk_grupo,
    sk_patio_retirada,
    sk_patio_devolucao,
    sk_tempo_reserva,
    sk_tempo_retirada_prevista,
    sk_tempo_devolucao_prevista,
    antecedencia_dias,
    qt_veiculos_solicitados,
    status,
    id_sistema_origem
)
SELECT
    r.id_reserva_origem,
    dc.sk_cliente,

    -- sk_grupo = NULL para todos os sistemas: id_grupo_origem ausente em dim_grupo
    -- (chave natural de dim_grupo é nome_grupo, ausente em std_reserva)
    NULL::INT                                          AS sk_grupo,

    dp_ret.sk_patio                                    AS sk_patio_retirada,
    dp_dev.sk_patio                                    AS sk_patio_devolucao,

    -- sk_tempo_reserva: proxy dt_retirada_prevista quando dt_reserva=NULL (tadeupires)
    TO_CHAR(
        COALESCE(r.dt_reserva, r.dt_retirada_prevista)::DATE,
        'YYYYMMDD'
    )::INT                                             AS sk_tempo_reserva,

    TO_CHAR(r.dt_retirada_prevista::DATE, 'YYYYMMDD')::INT AS sk_tempo_retirada_prevista,

    -- sk_tempo_devolucao_prevista: NULL para mhscardoso (DtDevolucaoPrevista ausente em Reserva)
    CASE WHEN r.dt_devolucao_prevista IS NOT NULL
         THEN TO_CHAR(r.dt_devolucao_prevista::DATE, 'YYYYMMDD')::INT
    END                                                AS sk_tempo_devolucao_prevista,

    r.antecedencia_dias,                               -- NULL para tadeupires (sem dt_reserva)
    COALESCE(r.qt_veiculos_solicitados, 1)             AS qt_veiculos_solicitados,
    r.status,
    r.id_sistema_origem

FROM staging.std_reserva r

-- sk_cliente: SKIP se cliente não encontrado
LEFT JOIN dw.dim_cliente dc
    ON  dc.id_cliente_origem  = r.id_cliente_origem
    AND dc.id_sistema_origem  = r.id_sistema_origem

-- sk_patio_retirada: NULL para mhscardoso (id_patio_retirada_origem=NULL em Reserva)
LEFT JOIN dw.dim_patio dp_ret
    ON  dp_ret.id_patio_origem   = r.id_patio_retirada_origem
    AND dp_ret.id_sistema_origem = r.id_sistema_origem
    AND r.id_patio_retirada_origem IS NOT NULL

-- sk_patio_devolucao: NULL para mhscardoso (id_patio_devolucao_origem ausente em stg_mhsc_reserva)
LEFT JOIN dw.dim_patio dp_dev
    ON  dp_dev.id_patio_origem   = r.id_patio_devolucao_origem
    AND dp_dev.id_sistema_origem = r.id_sistema_origem
    AND r.id_patio_devolucao_origem IS NOT NULL

WHERE dc.sk_cliente IS NOT NULL   -- SKIP: cliente ausente em dim_cliente (estimativa: ~0%)
  -- SKIP: reservas sem data de retirada prevista são inválidas (nunca esperado)
  AND r.dt_retirada_prevista IS NOT NULL

ON CONFLICT (id_sistema_origem, id_reserva_origem) DO NOTHING;

-- =============================================================================
-- 3. fato_movimentacao_patio
-- =============================================================================
-- Grão: uma transferência de veículo entre dois pátios.
--
-- Resolução de surrogate keys:
--   sk_veiculo       → dim_veiculo ON (id_sistema_origem, id_veiculo_origem)
--   sk_patio_origem  → dim_patio ON (id_sistema_origem, id_patio_origem_origem)
--   sk_patio_destino → dim_patio; NULL se veículo ainda em trânsito
--                      (id_patio_destino_origem=NULL em mhscardoso para IDVagaDestino=NULL)
--   sk_tempo         → YYYYMMDD de dt_saida_origem (NOT NULL em std_movimentacao)
--
-- motivo: disponível apenas para valviesse; NULL para mhscardoso, tadeupires
--   e gupessanha (derivada de locacao, sem campo motivo).
--
-- quantidade_veiculos: sempre 1 (cada linha representa 1 veículo movimentado).
--   Coluna adicionada à fato_movimentacao_patio na seção 0 deste script.
--
-- SKIP estimado:
--   sk_veiculo=NULL: veículos em movimentacao sem correspondente em dim_veiculo
--     → possível se o veículo foi excluído do OLTP após a movimentação. ~0%.
--   sk_patio_origem=NULL: pátio de origem ausente em dim_patio. ~0%.
--   Linhas gupessanha com patio_retirada = patio_devolucao: já filtradas no
--     extract (stg_gupe_movimentacao WHERE patio_retirada_id <> patio_devolucao_id).

INSERT INTO dw.fato_movimentacao_patio (
    id_movimentacao_origem,
    sk_veiculo,
    sk_patio_origem,
    sk_patio_destino,
    sk_tempo,
    motivo,
    quantidade_veiculos,
    id_sistema_origem
)
SELECT
    m.id_movimentacao_origem,
    dv.sk_veiculo,
    dp_orig.sk_patio                               AS sk_patio_origem,
    dp_dest.sk_patio                               AS sk_patio_destino,  -- NULL se em trânsito

    -- sk_tempo = data de saída do pátio de origem (timestamp único para tadeupires e valviesse)
    TO_CHAR(m.dt_saida_origem::DATE, 'YYYYMMDD')::INT AS sk_tempo,

    m.motivo,                                      -- NULL exceto valviesse
    1                                              AS quantidade_veiculos,
    m.id_sistema_origem

FROM staging.std_movimentacao m

-- sk_veiculo: SKIP se veículo não encontrado em dim_veiculo
LEFT JOIN dw.dim_veiculo dv
    ON  dv.id_veiculo_origem  = m.id_veiculo_origem
    AND dv.id_sistema_origem  = m.id_sistema_origem

-- sk_patio_origem: SKIP se pátio de origem não encontrado
LEFT JOIN dw.dim_patio dp_orig
    ON  dp_orig.id_patio_origem   = m.id_patio_origem_origem
    AND dp_orig.id_sistema_origem = m.id_sistema_origem

-- sk_patio_destino: NULL permitido (veículo ainda em trânsito — IDVagaDestino=NULL no mhscardoso)
LEFT JOIN dw.dim_patio dp_dest
    ON  dp_dest.id_patio_origem   = m.id_patio_destino_origem
    AND dp_dest.id_sistema_origem = m.id_sistema_origem
    AND m.id_patio_destino_origem IS NOT NULL

WHERE dv.sk_veiculo      IS NOT NULL   -- SKIP: veículo ausente em dim_veiculo
  AND dp_orig.sk_patio   IS NOT NULL   -- SKIP: pátio de origem ausente em dim_patio

ON CONFLICT (id_sistema_origem, id_movimentacao_origem) DO NOTHING;
