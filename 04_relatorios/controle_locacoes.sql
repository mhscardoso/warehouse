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
-- REPORT: Vehicles currently rented per Group
-- Shows: rental period, remaining days until return (availability)
-- Only active/open rentals (sk_tempo_devolucao IS NULL or status = 'em aberto')
-- =============================================================================

-- =============================================================================
--                                 CONSIDERATIONS
--
-- The filter WHERE fl.sk_tempo_devolucao IS NULL isolates only open rentals —
-- vehicles not yet returned, therefore unavailable for a new rental.
--
-- dias_restantes_devolucao uses DATE_PART('day', tp_prev.dt_ref - CURRENT_DATE)
-- as documented in the DW itself (the comment in fato_locacao explicitly
-- recommends this calculation). Negative values mean the customer is overdue.
--
-- The sentinel 99991231 is handled explicitly — when the planned return date is
-- unknown (mainly mhscardoso and valviesse), dias_restantes_devolucao and
-- em_atraso return NULL instead of a misleading value.
--
-- The ORDER BY dias_restantes_devolucao ASC NULLS LAST puts the most urgent
-- returns (closest or already overdue) at the top, which is the most
-- operationally useful view for a fleet manager.
-- =============================================================================

SELECT
    dg.nome_grupo,
    dg.mecanizacao,
    dv.placa,
    dv.marca,
    dv.modelo,
    dc.nome_cliente,
    fl.id_sistema_origem                                        AS sistema_origem,

    -- Rental period
    tp_ret.dt_ref                                               AS dt_retirada,
    tp_prev.dt_ref                                              AS dt_devolucao_prevista,

    fl.dias_locacao                                             AS dias_contratados,

    -- Remaining days until planned return (from today)
    -- Negative value means the return is already overdue
    CASE
        WHEN tp_prev.sk_tempo = 99991231 THEN NULL             -- no planned return date
        ELSE DATE_PART('day', tp_prev.dt_ref - CURRENT_DATE)::INT
    END                                                         AS dias_restantes_devolucao,

    -- Flag: overdue return
    CASE
        WHEN tp_prev.sk_tempo = 99991231 THEN NULL
        WHEN tp_prev.dt_ref < CURRENT_DATE THEN TRUE
        ELSE FALSE
    END                                                         AS em_atraso,

    fl.valor_diaria,
    fl.valor_total,
    fl.status

FROM dw.fato_locacao fl

INNER JOIN dw.dim_grupo dg
    ON dg.sk_grupo    = fl.sk_grupo

INNER JOIN dw.dim_veiculo dv
    ON dv.sk_veiculo  = fl.sk_veiculo

INNER JOIN dw.dim_cliente dc
    ON dc.sk_cliente  = fl.sk_cliente

-- Pickup date
INNER JOIN dw.dim_tempo tp_ret
    ON tp_ret.sk_tempo = fl.sk_tempo_retirada

-- Planned return date (99991231 = unknown/sentinel)
INNER JOIN dw.dim_tempo tp_prev
    ON tp_prev.sk_tempo = fl.sk_tempo_devolucao_prevista

-- Only open/active rentals (vehicle not yet returned)
WHERE fl.sk_tempo_devolucao IS NULL

ORDER BY
    dias_restantes_devolucao ASC NULLS LAST,
    dg.nome_grupo,
    dv.placa;
