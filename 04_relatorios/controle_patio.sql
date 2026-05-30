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
-- REPORT: Number of vehicles by Group and Origin
-- Grouping: brand, model, mechanization
-- Origin: company that owns the yard (id_sistema_origem)
-- =============================================================================


-- =============================================================================
--                                CONSIDERATIONS
-- 
-- The join between dim_veiculo and dim_grupo goes through fato_locacao 
-- because there is no direct FK between these two dimension tables in the 
-- DW — the relationship only exists at the fact grain (a vehicle was rented 
-- under a specific group). This is the correct relational path given the model.
-- 
-- The id_sistema_origem on dim_veiculo serves as the "origin" — each value 
-- identifies one of the six companies (yours + five partners).
-- 
-- ```marca``` will be NULL for vehicles from mhscardoso, since that field 
-- isn't captured in that source's OLTP. If you want to handle that explicitly,
-- you can replace dv.marca with COALESCE(dv.marca, '(não informado)') in both the 
-- ```SELECT and GROUP BY```.
-- 
-- ```mecanizacao``` will also be NULL for mhscardoso vehicles, for the same 
-- reason documented in ```dim_grupo```.
-- =============================================================================

SELECT
    dv.marca,
    dv.modelo,
    dg.nome_grupo,
    dg.mecanizacao,
    dv.id_sistema_origem                        AS sistema_origem,

    COUNT(DISTINCT dv.sk_veiculo)               AS qt_veiculos

FROM dw.dim_veiculo dv

-- Join to get group attributes (nome_grupo, mecanizacao)
-- Uses id_sistema_origem + nome_grupo as the natural key of dim_grupo
INNER JOIN dw.dim_grupo dg
    ON  dg.id_sistema_origem = dv.id_sistema_origem

-- At least one rental must exist to confirm the vehicle is active in the fleet
INNER JOIN dw.fato_locacao fl
    ON  fl.sk_veiculo        = dv.sk_veiculo
    AND fl.sk_grupo          = dg.sk_grupo

GROUP BY
    dv.marca,
    dv.modelo,
    dg.nome_grupo,
    dg.mecanizacao,
    dv.id_sistema_origem

ORDER BY
    dv.id_sistema_origem,
    dg.nome_grupo,
    dv.marca,
    dv.modelo;
