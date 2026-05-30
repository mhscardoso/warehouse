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
-- Arquivo  : 03_etl/02_transformacao/transform_staging.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Consolida as 4 extrações (stg_mhsc_*, stg_tade_*, stg_gupe_*,
--            stg_valv_*) em tabelas std_* padronizadas no schema staging.
--            Uma tabela std_* por entidade DW. Cada std_* fornece exatamente
--            as colunas necessárias para as dim_* e fato_* de create_dw_v2.sql.
--
-- Pré-requisito: todos os extract_grupo_*.sql já executados com sucesso.
-- Cron recomendado: 0 5 * * *  (30 min após a extração das 04h00)
--
-- Padronizações aplicadas:
--   mecanizacao  → sempre 'MANUAL' | 'AUTOMATICO'
--                  tadeupires: UPPER() converte 'manual'/'automatico'
--                  gupessanha: REPLACE(UPPER(..),'AUTOMATICA','AUTOMATICO')
--                  valviesse:  já correto; mhscardoso: NULL (campo ausente)
--   tipo_cliente → já 'PF'|'PJ' em todos os stg_* (normalizado no extract)
--   status locacao → derivado de dt_devolucao_real:
--                    IS NULL → 'EM_ANDAMENTO', IS NOT NULL → 'CONCLUIDA'
--   valor_diaria → mhscardoso: campo direto; gupessanha: valor_diaria_aplicada;
--                  tadeupires: NULL (capturado apenas valor_total de cobranca);
--                  valviesse:  NULL (schema tem totais, não diária)
--   valor_total  → mhscardoso: valor_diaria × dias_locacao;
--                  tadeupires: cobranca.valor (via extract);
--                  gupessanha: valor_diaria × dias_locacao;
--                  valviesse:  COALESCE(valor_final, valor_previsto)
--   km_rodados   → NULL para todos (não capturado na extração)
--   campos ausentes → sempre NULL explícito; coluna nunca omitida
--
-- Idempotência: cada std_* é DROPada antes de ser recriada (sem TRUNCATE).
-- Não há FKs entre std_* (tabelas planas), portanto a ordem dos DROPs não
-- precisa respeitar dependências.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- =============================================================================
-- Remover tabelas std_* existentes (idempotência)
-- A ordem respeita possíveis dependências lógicas: fatos antes de dimensões.
-- =============================================================================

DROP TABLE IF EXISTS staging.std_movimentacao;
DROP TABLE IF EXISTS staging.std_locacao;
DROP TABLE IF EXISTS staging.std_reserva;
DROP TABLE IF EXISTS staging.std_veiculo;
DROP TABLE IF EXISTS staging.std_grupo;
DROP TABLE IF EXISTS staging.std_cliente;
DROP TABLE IF EXISTS staging.std_patio;

-- =============================================================================
-- 1. std_patio
-- =============================================================================
-- Alvo: dw.dim_patio (id_patio_origem, nome_patio, cidade, localizacao,
--       id_sistema_origem).
--
-- localizacao disponível em:
--   mhscardoso → logradouro||numero||bairro||uf (concatenado no extract)
--   gupessanha → campo endereco (texto livre do OLTP)
--   valviesse  → campo localizacao direto
--   tadeupires → NULL (schema não tem campo de endereço)
--
-- cidade disponível em:
--   mhscardoso → Endereco.cidade
--   tadeupires → patio.cidade
--   gupessanha → NULL (só tem endereco texto livre)
--   valviesse  → NULL (campo isolado ausente em valviesse.patio)

CREATE TABLE staging.std_patio AS

SELECT
    id_patio_origem,
    nome_patio,
    cidade,        -- do Endereco (JOIN no extract)
    localizacao,   -- logradouro+numero+bairro+uf concatenados no extract
    id_sistema_origem
FROM staging.stg_mhsc_patio

UNION ALL

SELECT
    id_patio_origem,
    nome_patio,
    cidade,
    localizacao,   -- NULL: ausente no schema tadeupires
    id_sistema_origem
FROM staging.stg_tade_patio

UNION ALL

SELECT
    id_patio_origem,
    nome_patio,
    cidade,        -- NULL: schema gupessanha não tem cidade isolada
    localizacao,   -- campo endereco (texto livre)
    id_sistema_origem
FROM staging.stg_gupe_patio

UNION ALL

SELECT
    id_patio_origem,
    nome_patio,
    cidade,        -- NULL: campo cidade isolado ausente em valviesse.patio
    localizacao,   -- campo localizacao direto do OLTP
    id_sistema_origem
FROM staging.stg_valv_patio;


-- =============================================================================
-- 2. std_cliente
-- =============================================================================
-- Alvo: dw.dim_cliente (id_cliente_origem, nome_cliente, tipo_cliente,
--       cidade_origem, estado_origem, id_sistema_origem).
--
-- tipo_cliente: já normalizado ('PF'|'PJ') em todos os stg_* no extract.
-- estado_origem disponível apenas em mhscardoso (Endereco.uf) e valviesse;
-- NULL para tadeupires e gupessanha (campo ausente nos OLTPs respectivos).

CREATE TABLE staging.std_cliente AS

SELECT
    id_cliente_origem,
    nome_cliente,
    tipo_cliente,
    cidade_origem,
    estado_origem,   -- Endereco.uf (PF ou Empresa)
    id_sistema_origem
FROM staging.stg_mhsc_cliente

UNION ALL

SELECT
    id_cliente_origem,
    nome_cliente,
    tipo_cliente,
    cidade_origem,
    estado_origem,   -- NULL: ausente no schema tadeupires
    id_sistema_origem
FROM staging.stg_tade_cliente

UNION ALL

SELECT
    id_cliente_origem,
    nome_cliente,
    tipo_cliente,
    cidade_origem,
    estado_origem,   -- NULL: ausente no schema gupessanha
    id_sistema_origem
FROM staging.stg_gupe_cliente

UNION ALL

SELECT
    id_cliente_origem,
    nome_cliente,
    tipo_cliente,
    cidade_origem,
    estado_origem,   -- disponível diretamente (valviesse é o schema mais completo)
    id_sistema_origem
FROM staging.stg_valv_cliente;


-- =============================================================================
-- 3. std_grupo
-- =============================================================================
-- Alvo: dw.dim_grupo (id_grupo_origem, nome_grupo, mecanizacao, classe_luxo,
--       valor_diaria_base, id_sistema_origem).
--
-- Fonte: stg_*_veiculo (cada veículo referencia seu grupo via JOIN no extract).
-- DISTINCT por ramo evita uma linha por veículo — o load fase usa (nome_grupo,
-- id_sistema_origem) como chave natural para resolver o sk_grupo.
--
-- id_grupo_origem: não foi capturado nas tabelas stg_*_veiculo (o extract
-- trouxe apenas nome_grupo via JOIN). Registrado como NULL; o load deve
-- usar nome_grupo + id_sistema_origem como chave de lookup.
--
-- classe_luxo / valor_diaria_base: presentes apenas em gupessanha.grupo,
-- mas não foram capturados no extract (stg_gupe_veiculo não tem esses campos).
-- NULL para todos os sistemas neste pipeline.
--
-- Normalização de mecanizacao:
--   mhscardoso  → NULL (campo ausente no OLTP — Categoria não tem mecanizacao)
--   tadeupires  → UPPER(): 'manual'→'MANUAL', 'automatico'→'AUTOMATICO'
--   gupessanha  → REPLACE(UPPER(..),'AUTOMATICA','AUTOMATICO'): remove sufixo 'A'
--   valviesse   → já 'MANUAL'|'AUTOMATICO' (sem transformação)

CREATE TABLE staging.std_grupo AS

SELECT DISTINCT
    NULL::VARCHAR(50)    AS id_grupo_origem,
    nome_grupo,
    NULL::VARCHAR(20)    AS mecanizacao,       -- ausente no schema mhscardoso
    NULL::VARCHAR(20)    AS classe_luxo,
    NULL::NUMERIC(10,2)  AS valor_diaria_base,
    id_sistema_origem
FROM staging.stg_mhsc_veiculo
WHERE nome_grupo IS NOT NULL

UNION ALL

SELECT DISTINCT
    NULL::VARCHAR(50)    AS id_grupo_origem,
    nome_grupo,
    UPPER(mecanizacao)   AS mecanizacao,   -- 'manual'→'MANUAL', 'automatico'→'AUTOMATICO'
    NULL::VARCHAR(20)    AS classe_luxo,
    NULL::NUMERIC(10,2)  AS valor_diaria_base,
    id_sistema_origem
FROM staging.stg_tade_veiculo
WHERE nome_grupo IS NOT NULL

UNION ALL

SELECT DISTINCT
    NULL::VARCHAR(50)    AS id_grupo_origem,
    nome_grupo,
    -- 'AUTOMATICA' viola CHECK em dim_grupo (aceita só 'AUTOMATICO')
    REPLACE(UPPER(mecanizacao), 'AUTOMATICA', 'AUTOMATICO') AS mecanizacao,
    NULL::VARCHAR(20)    AS classe_luxo,
    NULL::NUMERIC(10,2)  AS valor_diaria_base,
    id_sistema_origem
FROM staging.stg_gupe_veiculo
WHERE nome_grupo IS NOT NULL

UNION ALL

SELECT DISTINCT
    NULL::VARCHAR(50)    AS id_grupo_origem,
    nome_grupo,
    mecanizacao,         -- já 'MANUAL'|'AUTOMATICO'
    NULL::VARCHAR(20)    AS classe_luxo,
    NULL::NUMERIC(10,2)  AS valor_diaria_base,
    id_sistema_origem
FROM staging.stg_valv_veiculo
WHERE nome_grupo IS NOT NULL;


-- =============================================================================
-- 4. std_veiculo
-- =============================================================================
-- Alvo: dw.dim_veiculo (id_veiculo_origem, placa, chassi, marca, modelo, ano,
--       cor, ar_condicionado, id_sistema_origem).
-- Extra: nome_grupo e mecanizacao (normalizados) para o load resolver sk_grupo
--        via std_grupo sem precisar de JOIN adicional.
--
-- Campos ausentes por sistema:
--   mhscardoso: marca=NULL, cor=NULL, mecanizacao=NULL (ausentes no OLTP)
--   tadeupires: ano=NULL (ausente); mecanizacao normalizada via UPPER()
--   gupessanha: mecanizacao normalizada via REPLACE/UPPER
--   valviesse:  ano=NULL (ausente); mecanizacao já correta

CREATE TABLE staging.std_veiculo AS

SELECT
    id_veiculo_origem,
    placa,
    chassi,
    marca,                     -- NULL: ausente no schema mhscardoso
    modelo,
    ano,
    cor,                       -- NULL: ausente no schema mhscardoso
    ar_condicionado,
    nome_grupo,                -- Categoria.Classificacao (chave para dim_grupo)
    NULL::VARCHAR(20) AS mecanizacao,  -- ausente no schema mhscardoso
    id_sistema_origem
FROM staging.stg_mhsc_veiculo

UNION ALL

SELECT
    id_veiculo_origem,
    placa,
    chassi,
    marca,
    modelo,
    ano,                       -- NULL: ausente no schema tadeupires
    cor,
    ar_condicionado,
    nome_grupo,
    UPPER(mecanizacao) AS mecanizacao,  -- 'manual'→'MANUAL', 'automatico'→'AUTOMATICO'
    id_sistema_origem
FROM staging.stg_tade_veiculo

UNION ALL

SELECT
    id_veiculo_origem,
    placa,
    chassi,
    marca,
    modelo,
    ano,
    cor,
    ar_condicionado,
    nome_grupo,
    REPLACE(UPPER(mecanizacao), 'AUTOMATICA', 'AUTOMATICO') AS mecanizacao,
    id_sistema_origem
FROM staging.stg_gupe_veiculo

UNION ALL

SELECT
    id_veiculo_origem,
    placa,
    chassi,
    marca,
    modelo,
    ano,                       -- NULL: ausente no schema valviesse
    cor,
    ar_condicionado,
    nome_grupo,
    mecanizacao,               -- já 'MANUAL'|'AUTOMATICO'
    id_sistema_origem
FROM staging.stg_valv_veiculo;


-- =============================================================================
-- 5. std_reserva
-- =============================================================================
-- Alvo: dw.fato_reserva (id_reserva_origem, id_cliente_origem, id_grupo_origem,
--       id_patio_retirada_origem, id_patio_devolucao_origem, dt_reserva,
--       dt_retirada_prevista, dt_devolucao_prevista, antecedencia_dias,
--       qt_veiculos_solicitados, status, id_sistema_origem).
--
-- antecedencia_dias: DATE_PART('day', dt_retirada_prevista - dt_reserva)::INT
--   NULL para tadeupires (dt_reserva=NULL: campo data_reserva ausente no OLTP).
--
-- Campos ausentes por sistema:
--   mhscardoso: id_grupo_origem=NULL, id_patio_retirada_origem=NULL,
--               id_patio_devolucao_origem=NULL (stg_mhsc_reserva não tem a coluna),
--               dt_devolucao_prevista=NULL (Reserva mhscardoso sem esse campo)
--   tadeupires: dt_reserva=NULL → antecedencia_dias=NULL
--   gupessanha: completo
--   valviesse:  completo

CREATE TABLE staging.std_reserva AS

SELECT
    r.id_reserva_origem,
    r.id_cliente_origem,
    r.id_grupo_origem,               -- NULL: Reserva mhscardoso não referencia grupo
    r.id_patio_retirada_origem,      -- NULL: pátio só na Locacao mhscardoso (via Vaga)
    NULL::VARCHAR(50) AS id_patio_devolucao_origem,  -- ausente em stg_mhsc_reserva
    r.dt_reserva,
    r.dt_retirada_prevista,
    r.dt_devolucao_prevista,         -- NULL: DtDevolucaoPrevista ausente na Reserva mhscardoso
    DATE_PART('day', r.dt_retirada_prevista - r.dt_reserva)::INT AS antecedencia_dias,
    r.qt_veiculos_solicitados,
    r.status,
    r.id_sistema_origem
FROM staging.stg_mhsc_reserva r

UNION ALL

SELECT
    r.id_reserva_origem,
    r.id_cliente_origem,
    r.id_grupo_origem,
    r.id_patio_retirada_origem,
    r.id_patio_devolucao_origem,
    r.dt_reserva,                    -- NULL: campo data_reserva ausente no schema tadeupires
    r.dt_retirada_prevista,
    r.dt_devolucao_prevista,
    -- antecedencia_dias: NULL quando dt_reserva é NULL (tadeupires não tem data_reserva)
    NULL::INT AS antecedencia_dias,
    r.qt_veiculos_solicitados,       -- NULL: reserva tadeupires é por veículo (implícito 1)
    r.status,
    r.id_sistema_origem
FROM staging.stg_tade_reserva r

UNION ALL

SELECT
    r.id_reserva_origem,
    r.id_cliente_origem,
    r.id_grupo_origem,
    r.id_patio_retirada_origem,
    r.id_patio_devolucao_origem,
    r.dt_reserva,
    r.dt_retirada_prevista,
    r.dt_devolucao_prevista,
    DATE_PART('day', r.dt_retirada_prevista - r.dt_reserva)::INT AS antecedencia_dias,
    r.qt_veiculos_solicitados,       -- NULL: uma reserva = um veículo
    r.status,
    r.id_sistema_origem
FROM staging.stg_gupe_reserva r

UNION ALL

SELECT
    r.id_reserva_origem,
    r.id_cliente_origem,
    r.id_grupo_origem,
    r.id_patio_retirada_origem,
    r.id_patio_devolucao_origem,     -- id_patio_devolucao_previsto do OLTP
    r.dt_reserva,
    r.dt_retirada_prevista,
    r.dt_devolucao_prevista,
    DATE_PART('day', r.dt_retirada_prevista - r.dt_reserva)::INT AS antecedencia_dias,
    r.qt_veiculos_solicitados,       -- NULL: uma reserva = um veículo
    r.status,
    r.id_sistema_origem
FROM staging.stg_valv_reserva r;


-- =============================================================================
-- 6. std_locacao
-- =============================================================================
-- Alvo: dw.fato_locacao (id_locacao_origem, id_cliente_origem, id_veiculo_origem,
--       nome_grupo, id_patio_retirada_origem, id_patio_devolucao_origem,
--       dt_retirada, dt_devolucao_real, dt_devolucao_prevista, valor_diaria,
--       valor_total, dias_locacao, km_rodados, status, id_sistema_origem).
--
-- nome_grupo: obtido via JOIN com stg_*_veiculo; o load phase usa
--   (nome_grupo, id_sistema_origem) para resolver sk_grupo em dim_grupo.
--
-- dt_devolucao_prevista: necessária para sk_tempo_devolucao_prevista em
--   fato_locacao (NOT NULL). Obtida via LEFT JOIN com stg_*_reserva onde
--   id_reserva_origem IS NOT NULL. NULL para:
--     mhscardoso — Reserva não tem DtDevolucaoPrevista no OLTP
--     valviesse  — data_hora_prev_devolucao não foi capturada no extract
--   AVISO: registros com dt_devolucao_prevista=NULL falharão na carga para
--   fato_locacao (sk_tempo_devolucao_prevista NOT NULL). O load deve filtrar
--   ou usar um valor padrão (ex.: sk_tempo de data-sentinela) para esses casos.
--
-- valor_diaria (NOT NULL em fato_locacao):
--   mhscardoso: campo direto do OLTP (ValorDiaria)
--   gupessanha: valor_diaria_aplicada (campo direto)
--   tadeupires: NULL — não capturado no extract (apenas valor_total de cobranca)
--   valviesse:  NULL — schema tem apenas totais (valor_previsto / valor_final)
--   AVISO: NULL quebrará a constraint NOT NULL em fato_locacao para tadeupires
--   e valviesse. O load deve tratar esses casos (ex.: calcular valor_diaria =
--   valor_total / NULLIF(dias_locacao, 0) ou usar valor sentinela -1).
--
-- valor_total:
--   mhscardoso: valor_diaria × dias_locacao (NULL se locação em aberto)
--   tadeupires: cobranca.valor capturado no extract como valor_total
--   gupessanha: valor_diaria × dias_locacao (NULL se locação em aberto)
--   valviesse:  COALESCE(valor_final, valor_previsto) — real se disponível
--
-- km_rodados: NULL para todos (km_entrega/km_devolucao não capturados no extract).
--
-- status: derivado de dt_devolucao_real em todos os grupos (coluna status não
--   foi capturada no extract de locacao de nenhum sistema).

CREATE TABLE staging.std_locacao AS

-- mhscardoso ---------------------------------------------------------------
SELECT
    l.id_locacao_origem,
    l.id_reserva_origem,
    l.id_cliente_origem,
    l.id_veiculo_origem,
    v.nome_grupo,                  -- via JOIN stg_mhsc_veiculo
    l.id_patio_retirada_origem,
    l.id_patio_devolucao_origem,
    l.dt_retirada,
    l.dt_devolucao_real,
    NULL::TIMESTAMP                AS dt_devolucao_prevista,  -- Reserva mhscardoso sem DtDevolucaoPrevista
    l.valor_diaria,
    CASE
        WHEN l.dt_devolucao_real IS NOT NULL
        THEN l.valor_diaria
             * DATE_PART('day', l.dt_devolucao_real - l.dt_retirada)
        ELSE NULL
    END::NUMERIC(10,2)             AS valor_total,
    DATE_PART('day', l.dt_devolucao_real - l.dt_retirada)::INT AS dias_locacao,
    NULL::INT                      AS km_rodados,
    CASE WHEN l.dt_devolucao_real IS NULL
         THEN 'EM_ANDAMENTO' ELSE 'CONCLUIDA' END             AS status,
    l.id_sistema_origem
FROM staging.stg_mhsc_locacao l
JOIN staging.stg_mhsc_veiculo  v ON v.id_veiculo_origem = l.id_veiculo_origem

UNION ALL

-- tadeupires ----------------------------------------------------------------
SELECT
    l.id_locacao_origem,
    l.id_reserva_origem,
    l.id_cliente_origem,
    l.id_veiculo_origem,
    v.nome_grupo,
    l.id_patio_retirada_origem,
    l.id_patio_devolucao_origem,
    l.dt_retirada,
    l.dt_devolucao_real,
    r.dt_devolucao_prevista,       -- via LEFT JOIN stg_tade_reserva (NULL se walk-in)
    NULL::NUMERIC(10,2)            AS valor_diaria,  -- não capturado no extract tadeupires
    l.valor_total,                 -- cobranca.valor (NULL se sem cobrança registrada)
    DATE_PART('day', l.dt_devolucao_real - l.dt_retirada)::INT AS dias_locacao,
    NULL::INT                      AS km_rodados,
    CASE WHEN l.dt_devolucao_real IS NULL
         THEN 'EM_ANDAMENTO' ELSE 'CONCLUIDA' END             AS status,
    l.id_sistema_origem
FROM staging.stg_tade_locacao      l
JOIN staging.stg_tade_veiculo      v ON v.id_veiculo_origem  = l.id_veiculo_origem
LEFT JOIN staging.stg_tade_reserva r ON r.id_reserva_origem  = l.id_reserva_origem

UNION ALL

-- gupessanha ----------------------------------------------------------------
SELECT
    l.id_locacao_origem,
    l.id_reserva_origem,
    l.id_cliente_origem,
    l.id_veiculo_origem,
    v.nome_grupo,
    l.id_patio_retirada_origem,
    l.id_patio_devolucao_origem,
    l.dt_retirada,
    l.dt_devolucao_real,
    r.dt_devolucao_prevista,       -- via LEFT JOIN stg_gupe_reserva
    l.valor_diaria,                -- valor_diaria_aplicada (capturado no extract)
    CASE
        WHEN l.dt_devolucao_real IS NOT NULL
        THEN l.valor_diaria
             * DATE_PART('day', l.dt_devolucao_real - l.dt_retirada)
        ELSE NULL
    END::NUMERIC(10,2)             AS valor_total,
    DATE_PART('day', l.dt_devolucao_real - l.dt_retirada)::INT AS dias_locacao,
    NULL::INT                      AS km_rodados,
    CASE WHEN l.dt_devolucao_real IS NULL
         THEN 'EM_ANDAMENTO' ELSE 'CONCLUIDA' END             AS status,
    l.id_sistema_origem
FROM staging.stg_gupe_locacao      l
JOIN staging.stg_gupe_veiculo      v ON v.id_veiculo_origem  = l.id_veiculo_origem
LEFT JOIN staging.stg_gupe_reserva r ON r.id_reserva_origem  = l.id_reserva_origem

UNION ALL

-- valviesse -----------------------------------------------------------------
SELECT
    l.id_locacao_origem,
    l.id_reserva_origem,
    l.id_cliente_origem,
    l.id_veiculo_origem,
    v.nome_grupo,
    l.id_patio_retirada_origem,
    l.id_patio_devolucao_origem,   -- id_patio_devolucao_real (NULL se em aberto)
    l.dt_retirada,
    l.dt_devolucao_real,
    NULL::TIMESTAMP                AS dt_devolucao_prevista,  -- data_hora_prev_devolucao não capturada no extract
    NULL::NUMERIC(10,2)            AS valor_diaria,  -- valviesse tem apenas totais (sem diária)
    COALESCE(l.valor_final,
             l.valor_previsto)     AS valor_total,   -- real preferido; previsto como fallback
    DATE_PART('day', l.dt_devolucao_real - l.dt_retirada)::INT AS dias_locacao,
    NULL::INT                      AS km_rodados,
    CASE WHEN l.dt_devolucao_real IS NULL
         THEN 'EM_ANDAMENTO' ELSE 'CONCLUIDA' END             AS status,
    l.id_sistema_origem
FROM staging.stg_valv_locacao      l
JOIN staging.stg_valv_veiculo      v ON v.id_veiculo_origem  = l.id_veiculo_origem;


-- =============================================================================
-- 7. std_movimentacao
-- =============================================================================
-- Alvo: dw.fato_movimentacao_patio (id_movimentacao_origem, id_veiculo_origem,
--       id_patio_origem_origem, id_patio_destino_origem, dt_saida_origem,
--       dt_chegada_destino, motivo, id_sistema_origem).
--
-- dt_chegada_destino disponível em:
--   mhscardoso: DtChegada (chegada ao pátio destino) — capturado no extract
--   gupessanha: data_devolucao_real (locação CONCLUÍDA) — capturado no extract
--   tadeupires: NULL (data_movimentacao é timestamp único de saída)
--   valviesse:  NULL (data_hora_movimentacao é timestamp único de saída)
--
-- motivo disponível em:
--   valviesse:  motivo_movimentacao → capturado no extract como motivo
--   tadeupires: campo motivo existe no OLTP mas NÃO foi capturado no extract
--               (stg_tade_movimentacao não tem coluna motivo) → NULL
--   mhscardoso: ausente no schema → NULL
--   gupessanha: derivada de locacao, sem campo motivo → NULL

CREATE TABLE staging.std_movimentacao AS

SELECT
    id_movimentacao_origem,
    id_veiculo_origem,
    id_patio_origem_origem,
    id_patio_destino_origem,       -- NULL se veículo ainda em trânsito
    dt_saida_origem,               -- DtRetirada: saída do pátio de origem
    dt_chegada_destino,            -- DtChegada: chegada ao pátio de destino
    NULL::VARCHAR(100) AS motivo,  -- ausente no schema mhscardoso
    id_sistema_origem
FROM staging.stg_mhsc_movimentacao

UNION ALL

SELECT
    id_movimentacao_origem,
    id_veiculo_origem,
    id_patio_origem_origem,
    id_patio_destino_origem,
    dt_saida_origem,               -- data_movimentacao (timestamp único)
    dt_chegada_destino,            -- NULL: schema tadeupires tem timestamp único
    NULL::VARCHAR(100) AS motivo,  -- campo motivo existe no OLTP mas não foi capturado no extract
    id_sistema_origem
FROM staging.stg_tade_movimentacao

UNION ALL

SELECT
    id_movimentacao_origem,        -- 'LOC-{id_locacao}' (prefixo do extract)
    id_veiculo_origem,
    id_patio_origem_origem,
    id_patio_destino_origem,
    dt_saida_origem,               -- data_retirada_real da locação
    dt_chegada_destino,            -- data_devolucao_real da locação
    NULL::VARCHAR(100) AS motivo,  -- derivada de locacao; sem campo motivo
    id_sistema_origem
FROM staging.stg_gupe_movimentacao

UNION ALL

SELECT
    id_movimentacao_origem,
    id_veiculo_origem,
    id_patio_origem_origem,
    id_patio_destino_origem,
    dt_saida_origem,               -- data_hora_movimentacao (timestamp único)
    dt_chegada_destino,            -- NULL: schema valviesse tem timestamp único
    motivo,                        -- motivo_movimentacao (disponível no schema valviesse)
    id_sistema_origem
FROM staging.stg_valv_movimentacao;
