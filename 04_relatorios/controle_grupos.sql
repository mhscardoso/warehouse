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
-- REPORT: Most Rented Vehicle Groups cross-referenced with Customer Origin
-- =============================================================================


-- =============================================================================
--                                 CONSIDERATIONS
--
-- This report ranks vehicle groups by rental demand, cross-referenced with
-- the geographic and corporate origin of customers.
--
-- GRAIN: one row per (group, customer city, customer state, customer type,
--        source system) — aggregated rental metrics.
--
-- Ranking is based on qt_locacoes (total number of rentals per group).
--   RANK() is used instead of ROW_NUMBER() to handle ties correctly —
--   two groups with the same count receive the same rank position.
--
-- Only completed or active rentals are considered.
--   Cancelled rentals are not present in fato_locacao (filtered at load time
--   by the ETL — only rentals with a valid sk_veiculo, sk_grupo and sk_patio
--   are inserted). No additional status filter is strictly required here,
--   but an optional WHERE clause is provided commented out for reference.
--
-- valor_total_periodo: SUM of valor_total across rentals in the group.
--   NULL values (open rentals without valor_total) are ignored by SUM()
--   and do not distort the metric — this is the correct behavior.
--
-- media_dias_locacao: AVG of dias_locacao across rentals in the group.
--   NULL values (open rentals) are also ignored by AVG().
--   Useful to understand whether a group is preferred for short or long rentals.
--
-- cidade_origem and estado_origem are NULL for tadeupires and gupessanha
--   (field absent in their OLTPs). These appear as '(não informado)'.
--
-- tipo_cliente ('PF'|'PJ') cross-references whether demand comes from
--   individual or corporate customers per group.
--
-- id_sistema_origem on fato_locacao identifies the company that owns
--   the yard where the rental originated (the "fleet owner").
-- =============================================================================



SELECT
    -- Ranking of groups by number of rentals
    RANK() OVER (
        PARTITION BY fl.id_sistema_origem
        ORDER BY COUNT(fl.sk_locacao) DESC
    )                                                       AS ranking_grupo,

    -- Group
    dg.nome_grupo,
    COALESCE(dg.mecanizacao,  '(não informado)')            AS mecanizacao,
    COALESCE(dg.classe_luxo,  '(não informado)')            AS classe_luxo,

    -- Customer origin
    COALESCE(dc.cidade_origem, '(não informado)')           AS cidade_cliente,
    COALESCE(dc.estado_origem, '(não informado)')           AS estado_cliente,
    dc.tipo_cliente,

    -- Source company (fleet owner)
    fl.id_sistema_origem                                    AS sistema_origem,

    -- Rental volume metrics
    COUNT(fl.sk_locacao)                                    AS qt_locacoes,
    SUM(fl.qt_veiculos_solicitados_reserva)                 AS qt_veiculos_solicitados,

    -- Financial metrics
    SUM(fl.valor_total)                                     AS valor_total_periodo,
    ROUND(AVG(fl.valor_diaria), 2)                          AS media_valor_diaria,

    -- Duration metrics
    ROUND(AVG(fl.dias_locacao), 1)                          AS media_dias_locacao,
    MIN(fl.dias_locacao)                                    AS min_dias_locacao,
    MAX(fl.dias_locacao)                                    AS max_dias_locacao

FROM dw.fato_locacao fl

-- Group dimension
INNER JOIN dw.dim_grupo dg
    ON dg.sk_grupo   = fl.sk_grupo

-- Customer dimension
INNER JOIN dw.dim_cliente dc
    ON dc.sk_cliente = fl.sk_cliente

-- Optional: restrict to completed rentals only (uncomment if needed)
-- WHERE fl.status IN ('concluida', 'concluído', 'CONCLUIDA', 'CONCLUIDO')

GROUP BY
    dg.nome_grupo,
    dg.mecanizacao,
    dg.classe_luxo,
    dc.cidade_origem,
    dc.estado_origem,
    dc.tipo_cliente,
    fl.id_sistema_origem

ORDER BY
    fl.id_sistema_origem,
    ranking_grupo,
    dg.nome_grupo,
    dc.estado_origem NULLS LAST,
    dc.cidade_origem NULLS LAST;
