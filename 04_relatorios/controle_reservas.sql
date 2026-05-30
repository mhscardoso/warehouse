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
-- REPORT: Reservations per Group, Location, Pick-up Period and Customer Origin
-- =============================================================================


-- =============================================================================
--                                 CONSIDERATIONS
--
-- This report shows demand intelligence for the fleet:
-- how many reservations exist per vehicle group, per pick-up yard,
-- segmented by future pick-up horizon and customer city of origin.
--
-- GRAIN: one row per (group, yard, pick-up horizon, rental duration bucket,
--        customer city) — aggregated count of reservations.
--
-- pick-up horizon buckets (from CURRENT_DATE):
--   'Esta Semana'    → pick-up within the next 7 days
--   'Próxima Semana' → between 8 and 14 days
--   'Este Mês'       → between 15 and 30 days
--   'Próximos 3M'    → between 31 and 90 days
--   'Mais de 3M'     → beyond 90 days
--   Only future reservations are considered (dt_retirada_prevista > CURRENT_DATE).
--
-- rental duration buckets (sk_tempo_devolucao_prevista - sk_tempo_retirada_prevista):
--   'Até 3 dias'     → 1 to 3 days
--   '4 a 7 dias'     → 4 to 7 days
--   '8 a 15 dias'    → 8 to 15 days
--   'Mais de 15 dias'→ above 15 days
--   NULL             → when sk_tempo_devolucao_prevista is NULL (mhscardoso)
--                      duration is unknown and bucketed as '(não informado)'.
--
-- sk_grupo is NULL for mhscardoso reservations (documented limitation:
--   std_reserva has id_grupo_origem but dim_grupo uses nome_grupo as natural key,
--   which is absent in std_reserva). These reservations appear as '(não informado)'
--   in nome_grupo to avoid losing demand signal.
--
-- sk_patio_retirada is NULL for mhscardoso (yard only known at rental time).
--   These reservations appear as '(não informado)' in nome_patio.
--
-- cidade_origem is NULL for tadeupires and gupessanha (field absent in their OLTPs).
--   These appear as '(não informado)' in cidade_cliente.
--
-- Only reservations with status indicating active demand are counted.
--   Cancelled reservations are excluded via WHERE clause.
--
-- qt_reservas: COUNT of reservations per group of dimensions.
-- qt_veiculos_solicitados: SUM of vehicles requested across those reservations.
-- =============================================================================


SELECT
    -- Group
    COALESCE(dg.nome_grupo,  '(não informado)')             AS nome_grupo,
    COALESCE(dg.mecanizacao, '(não informado)')             AS mecanizacao,

    -- Pick-up yard (location)
    COALESCE(dp.nome_patio,  '(não informado)')             AS nome_patio,
    COALESCE(dp.cidade,      '(não informado)')             AS cidade_patio,

    -- Future pick-up horizon bucket
    CASE
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 7   THEN 'Esta Semana'
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 14  THEN 'Próxima Semana'
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 30  THEN 'Este Mês'
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 90  THEN 'Próximos 3M'
        ELSE                                          'Mais de 3M'
    END                                                     AS horizonte_retirada,

    -- Planned pick-up date (for detail drill-down if needed)
    tp_ret.dt_ref                                           AS dt_retirada_prevista,

    -- Rental duration bucket
    CASE
        WHEN tp_dev.dt_ref IS NULL
             THEN '(não informado)'                         -- mhscardoso: no planned return
        WHEN DATE_PART('day', tp_dev.dt_ref - tp_ret.dt_ref) <= 3
             THEN 'Até 3 dias'
        WHEN DATE_PART('day', tp_dev.dt_ref - tp_ret.dt_ref) <= 7
             THEN '4 a 7 dias'
        WHEN DATE_PART('day', tp_dev.dt_ref - tp_ret.dt_ref) <= 15
             THEN '8 a 15 dias'
        ELSE      'Mais de 15 dias'
    END                                                     AS faixa_duracao,

    -- Customer city of origin
    COALESCE(dc.cidade_origem, '(não informado)')           AS cidade_cliente,
    dc.tipo_cliente,

    -- Source company
    fr.id_sistema_origem                                    AS sistema_origem,

    -- Metrics
    COUNT(fr.sk_reserva)                                    AS qt_reservas,
    SUM(fr.qt_veiculos_solicitados)                         AS qt_veiculos_solicitados

FROM dw.fato_reserva fr

-- Customer dimension
INNER JOIN dw.dim_cliente dc
    ON dc.sk_cliente = fr.sk_cliente

-- Group dimension: LEFT JOIN because sk_grupo is NULL for mhscardoso
LEFT JOIN dw.dim_grupo dg
    ON dg.sk_grupo = fr.sk_grupo

-- Pick-up yard: LEFT JOIN because sk_patio_retirada is NULL for mhscardoso
LEFT JOIN dw.dim_patio dp
    ON dp.sk_patio = fr.sk_patio_retirada

-- Planned pick-up date: NOT NULL in fato_reserva (guaranteed by load filter)
INNER JOIN dw.dim_tempo tp_ret
    ON tp_ret.sk_tempo = fr.sk_tempo_retirada_prevista

-- Planned return date: LEFT JOIN because NULL for mhscardoso
LEFT JOIN dw.dim_tempo tp_dev
    ON tp_dev.sk_tempo = fr.sk_tempo_devolucao_prevista
    AND fr.sk_tempo_devolucao_prevista IS NOT NULL

-- Only future reservations with active demand
WHERE tp_ret.dt_ref > CURRENT_DATE
  AND fr.status NOT IN ('cancelada', 'cancelado', 'CANCELADA', 'CANCELADO')

GROUP BY
    dg.nome_grupo,
    dg.mecanizacao,
    dp.nome_patio,
    dp.cidade,
    CASE
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 7   THEN 'Esta Semana'
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 14  THEN 'Próxima Semana'
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 30  THEN 'Este Mês'
        WHEN tp_ret.dt_ref <= CURRENT_DATE + 90  THEN 'Próximos 3M'
        ELSE                                          'Mais de 3M'
    END,
    tp_ret.dt_ref,
    CASE
        WHEN tp_dev.dt_ref IS NULL
             THEN '(não informado)'
        WHEN DATE_PART('day', tp_dev.dt_ref - tp_ret.dt_ref) <= 3
             THEN 'Até 3 dias'
        WHEN DATE_PART('day', tp_dev.dt_ref - tp_ret.dt_ref) <= 7
             THEN '4 a 7 dias'
        WHEN DATE_PART('day', tp_dev.dt_ref - tp_ret.dt_ref) <= 15
             THEN '8 a 15 dias'
        ELSE      'Mais de 15 dias'
    END,
    dc.cidade_origem,
    dc.tipo_cliente,
    fr.id_sistema_origem

ORDER BY
    fr.id_sistema_origem,
    horizonte_retirada,
    tp_ret.dt_ref,
    nome_grupo,
    nome_patio;
