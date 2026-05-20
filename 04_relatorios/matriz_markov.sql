-- =============================================================================
-- Arquivo  : 04_relatorios/matriz_markov.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Matriz de Markov de transição entre pátios, operando sobre
--            dw.fato_movimentacao_patio.
--
-- O QUE É A MATRIZ DE MARKOV NO CONTEXTO DO NEGÓCIO:
--   Uma cadeia de Markov de 1ª ordem modela um sistema cujo próximo estado
--   depende apenas do estado atual (propriedade de Markov). Aqui, o "estado"
--   é o pátio em que um veículo se encontra. A matriz de transição P[i,j]
--   representa a probabilidade de um veículo sair do pátio i e chegar ao
--   pátio j na próxima movimentação.
--
-- COMO INTERPRETAR:
--   * Cada linha é um pátio de origem; cada coluna é um pátio de destino.
--   * O valor em P[i,j] é o percentual histórico de veículos que, estando
--     no pátio i, foram para o pátio j.
--   * A soma dos percentuais em cada linha deve ser 100%.
--   * Um valor alto em P[i,j] indica desequilíbrio de frota: veículos
--     tendem a acumular no pátio j. Isso orienta ações de reposicionamento.
--   * A diagonal (P[i,i]) representa devoluções no mesmo pátio de retirada.
--
-- DECISÃO DE IMPLEMENTAÇÃO — CASE WHEN vs crosstab:
--   Escolhido CASE WHEN por ser mais legível e não exigir a extensão
--   'tablefunc' (crosstab). O formato de matriz é aproximado: cada pátio
--   recebe uma coluna nomeada. Para um conjunto dinâmico de pátios, gere
--   o SQL com: SELECT string_agg(...) FROM dw.dim_patio e execute via
--   EXECUTE em PL/pgSQL, ou use a função crosstab() do tablefunc.
--   O conjunto de colunas abaixo deve ser atualizado se novos pátios forem
--   adicionados ao DW.
-- =============================================================================


-- =============================================================================
-- QUERY 1 — Contagens absolutas de movimentações por par (origem, destino)
-- =============================================================================
-- Retorna: uma linha por combinação (pátio_origem, pátio_destino) com o
-- total de movimentações. Útil para auditar os dados antes de normalizar.

SELECT
    po.nome_patio                          AS patio_origem,
    pd.nome_patio                          AS patio_destino,
    COUNT(*)                               AS total_movimentacoes
FROM dw.fato_movimentacao_patio fm
JOIN dw.dim_patio po ON po.sk_patio = fm.sk_patio_origem
JOIN dw.dim_patio pd ON pd.sk_patio = fm.sk_patio_destino
GROUP BY
    fm.sk_patio_origem,
    fm.sk_patio_destino,
    po.nome_patio,
    pd.nome_patio
ORDER BY
    po.nome_patio,
    total_movimentacoes DESC;


-- =============================================================================
-- QUERY 2 — Matriz estocástica (percentuais de transição)
-- =============================================================================
-- Retorna: uma linha por pátio de origem, uma coluna por pátio de destino.
-- Cada valor é o percentual de movimentações que saíram do pátio i com destino j.
-- A soma de cada linha é 100% (ou próximo, sujeito a arredondamento).
--
-- Window function: SUM(qtd) OVER (PARTITION BY sk_patio_origem) acumula o
-- total de saídas da origem APÓS a agregação GROUP BY, o que é possível
-- pois window functions são avaliadas depois do GROUP BY em SQL.
--
-- NOTA: Substitua os nomes literais nos FILTER WHERE pelos nomes reais dos
-- pátios cadastrados em dw.dim_patio. Para descobrir os pátios ativos:
--   SELECT DISTINCT nome_patio FROM dw.dim_patio ORDER BY 1;

WITH contagens AS (
    -- Passo 1: totalizar movimentações por par origem→destino
    SELECT
        fm.sk_patio_origem,
        fm.sk_patio_destino,
        COUNT(*)::BIGINT AS qtd
    FROM dw.fato_movimentacao_patio fm
    WHERE fm.sk_patio_destino IS NOT NULL  -- exclui veículos ainda em trânsito
    GROUP BY
        fm.sk_patio_origem,
        fm.sk_patio_destino
),
com_totais AS (
    -- Passo 2: adicionar total de saídas por origem via window function
    SELECT
        sk_patio_origem,
        sk_patio_destino,
        qtd,
        SUM(qtd) OVER (PARTITION BY sk_patio_origem) AS total_saidas_origem
    FROM contagens
)
SELECT
    po.nome_patio                                AS patio_origem,
    -- Para cada pátio de destino: percentual de transição a partir desta origem
    -- Expanda/remova colunas conforme os pátios existentes no seu DW.
    ROUND(
        100.0 * SUM(ct.qtd) FILTER (WHERE pd.nome_patio = 'Pátio Central')
        / MAX(ct.total_saidas_origem),
        2
    )                                            AS "Pátio Central",

    ROUND(
        100.0 * SUM(ct.qtd) FILTER (WHERE pd.nome_patio = 'Pátio Norte')
        / MAX(ct.total_saidas_origem),
        2
    )                                            AS "Pátio Norte",

    ROUND(
        100.0 * SUM(ct.qtd) FILTER (WHERE pd.nome_patio = 'Pátio Sul')
        / MAX(ct.total_saidas_origem),
        2
    )                                            AS "Pátio Sul",

    ROUND(
        100.0 * SUM(ct.qtd) FILTER (WHERE pd.nome_patio = 'Pátio Leste')
        / MAX(ct.total_saidas_origem),
        2
    )                                            AS "Pátio Leste",

    ROUND(
        100.0 * SUM(ct.qtd) FILTER (WHERE pd.nome_patio = 'Pátio Oeste')
        / MAX(ct.total_saidas_origem),
        2
    )                                            AS "Pátio Oeste",

    MAX(ct.total_saidas_origem)                  AS total_saidas_origem  -- linha de referência
FROM com_totais ct
JOIN dw.dim_patio po ON po.sk_patio = ct.sk_patio_origem
JOIN dw.dim_patio pd ON pd.sk_patio = ct.sk_patio_destino
GROUP BY
    ct.sk_patio_origem,
    po.nome_patio
ORDER BY
    po.nome_patio;

-- =============================================================================
-- ALTERNATIVA — Formato longo (sem pivotar): uma linha por par (i,j)
-- =============================================================================
-- Use esta versão quando o número de pátios é dinâmico ou desconhecido.
-- Cada linha tem o percentual P[i,j]; filtre por patio_origem para ver
-- a distribuição de um pátio específico.

/*
WITH contagens AS (
    SELECT
        fm.sk_patio_origem,
        fm.sk_patio_destino,
        COUNT(*)::BIGINT AS qtd
    FROM dw.fato_movimentacao_patio fm
    WHERE fm.sk_patio_destino IS NOT NULL
    GROUP BY fm.sk_patio_origem, fm.sk_patio_destino
)
SELECT
    po.nome_patio                                                     AS patio_origem,
    pd.nome_patio                                                     AS patio_destino,
    c.qtd                                                             AS movimentacoes,
    SUM(c.qtd) OVER (PARTITION BY c.sk_patio_origem)                  AS total_saidas_origem,
    ROUND(
        100.0 * c.qtd
        / SUM(c.qtd) OVER (PARTITION BY c.sk_patio_origem),
        2
    )                                                                 AS pct_transicao
FROM contagens c
JOIN dw.dim_patio po ON po.sk_patio = c.sk_patio_origem
JOIN dw.dim_patio pd ON pd.sk_patio = c.sk_patio_destino
ORDER BY po.nome_patio, pct_transicao DESC;
*/
