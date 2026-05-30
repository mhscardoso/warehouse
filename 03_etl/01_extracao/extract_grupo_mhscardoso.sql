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
-- Arquivo  : 03_etl/01_extracao/extract_grupo_mhscardoso.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Descrição: Extração do OLTP do Grupo MHSCardoso para o schema staging.
--            Cada tabela staging recebe um SELECT direto do schema fonte
--            (mhscardoso.*) sem transformação de negócio — apenas resolução
--            de JOINs estruturais do OLTP (Vaga→Patio, CentroCusto→PF|PJ).
--
-- Cron recomendado: 0 4 * * *  (diário, às 04h00)
-- Justificativa: Locadoras operam com pico de transações entre 07h e 22h.
--   Executar às 04h garante captura completa do dia anterior com janela de
--   carga antes do início do expediente. Frequência horária seria overkill
--   para análise OLAP — se necessário, adotar CDC (Change Data Capture) em
--   vez de batch ETL.
--
-- Pré-requisito: tabelas OLTP do grupo carregadas no schema 'mhscardoso'
--   da mesma instância PostgreSQL onde reside o DW.
--   Ex.: SET search_path = mhscardoso, public;
--
-- Peculiaridades do schema mhscardoso tratadas aqui:
--   * Cliente   → não existe tabela unificada; usa CentroCusto→PessoaFisica|Empresa→Endereco
--   * Veículo   → não tem marca nem mecanizacao; usa Categoria.Classificacao como nome_grupo
--   * Pátio     → endereço via JOIN com Endereco
--   * Reserva   → não tem grupo_id nem patio_retirada (registrados como NULL)
--   * Locação   → pátio via JOIN Locacao→Vaga→Patio
--   * Moviment. → pátios via JOIN Movimentacao→Vaga(origem|destino)→Patio
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- =============================================================================
-- 1. stg_mhsc_patio
-- =============================================================================
-- Fonte: mhscardoso.patio JOIN mhscardoso.endereco
-- CDPatio é o código operacional — usado como identificador legível do pátio.
-- Endereço completo concatenado em localizacao (correspondendo ao campo v2
-- adicionado em dim_patio.localizacao).

CREATE TABLE IF NOT EXISTS staging.stg_mhsc_patio (
    id_patio_origem   VARCHAR(50)  NOT NULL,
    nome_patio        VARCHAR(100) NOT NULL,
    cidade            VARCHAR(100),
    localizacao       VARCHAR(300),
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_MHSCARDOSO',
    CONSTRAINT pk_stg_mhsc_patio PRIMARY KEY (id_patio_origem)
);

INSERT INTO staging.stg_mhsc_patio
    (id_patio_origem, nome_patio, cidade, localizacao, id_sistema_origem)
SELECT
    p.idpatio::VARCHAR                                               AS id_patio_origem,
    p.cdpatio                                                        AS nome_patio,
    e.cidade,
    e.logradouro || ', ' || e.numero
        || ' - ' || e.bairro
        || ' - ' || e.uf                                             AS localizacao,
    'GRUPO_MHSCARDOSO'
FROM mhscardoso.patio  p
JOIN mhscardoso.endereco e ON e.idendereco = p.idendereco
ON CONFLICT (id_patio_origem) DO NOTHING;

-- =============================================================================
-- 2. stg_mhsc_cliente
-- =============================================================================
-- Fonte: mhscardoso.centrocusto JOIN pessoafisica|empresa JOIN endereco
-- Em mhscardoso o "cliente" que faz reservas é o CentroCusto.
-- CentroCusto liga OU a PessoaFisica (IDFisica NOT NULL) OU a Empresa
-- (IDEmpresa NOT NULL) — CHECK constraint garante exclusividade.
-- id_cliente_origem = IDCentroCusto (chave de que a Reserva referencia).
-- cidade_origem e estado_origem vêm do Endereco da PF ou da Empresa.

CREATE TABLE IF NOT EXISTS staging.stg_mhsc_cliente (
    id_cliente_origem VARCHAR(50)  NOT NULL,
    tipo_cliente      CHAR(2)      NOT NULL,
    nome_cliente      VARCHAR(255) NOT NULL,
    cidade_origem     VARCHAR(100),
    estado_origem     CHAR(2),
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_MHSCARDOSO',
    CONSTRAINT pk_stg_mhsc_cliente PRIMARY KEY (id_cliente_origem),
    CONSTRAINT chk_stg_cli_tipo    CHECK (tipo_cliente IN ('PF','PJ'))
);

INSERT INTO staging.stg_mhsc_cliente
    (id_cliente_origem, tipo_cliente, nome_cliente,
     cidade_origem, estado_origem, id_sistema_origem)
SELECT
    cc.idcentrocusto::VARCHAR                              AS id_cliente_origem,
    CASE WHEN cc.idfisica IS NOT NULL THEN 'PF' ELSE 'PJ' END AS tipo_cliente,
    COALESCE(pf.nome, emp.razaosocial)                     AS nome_cliente,
    -- Usa endereco da PF quando PF, endereco da Empresa quando PJ
    COALESCE(e_pf.cidade,  e_emp.cidade)                   AS cidade_origem,
    COALESCE(e_pf.uf,      e_emp.uf)                       AS estado_origem,
    'GRUPO_MHSCARDOSO'
FROM mhscardoso.centrocusto cc
LEFT JOIN mhscardoso.pessoafisica pf  ON pf.idfisica    = cc.idfisica
LEFT JOIN mhscardoso.endereco     e_pf  ON e_pf.idendereco  = pf.idendereco
LEFT JOIN mhscardoso.empresa      emp ON emp.idempresa   = cc.idempresa
LEFT JOIN mhscardoso.endereco     e_emp ON e_emp.idendereco = emp.idendereco
ON CONFLICT (id_cliente_origem) DO NOTHING;

-- =============================================================================
-- 3. stg_mhsc_veiculo
-- =============================================================================
-- Fonte: mhscardoso.veiculo JOIN mhscardoso.categoria
-- Peculiaridades:
--   * marca      → NULL (ausente no schema mhscardoso)
--   * cor        → NULL (ausente no schema mhscardoso)
--   * mecanizacao → NULL (ausente; Categoria.Tracao4x4 é booleano, não equivalente)
--   * nome_grupo → Categoria.Classificacao (melhor aproximação disponível)
-- Ambiguidade: Categoria.ClasseLuxo ('A','B','C') poderia mapear para mecanizacao,
--   mas não é semanticamente equivalente. Decisão conservadora: mecanizacao = NULL.

CREATE TABLE IF NOT EXISTS staging.stg_mhsc_veiculo (
    id_veiculo_origem VARCHAR(50)  NOT NULL,
    placa             VARCHAR(10)  NOT NULL,
    chassi            VARCHAR(30),
    marca             VARCHAR(50),
    modelo            VARCHAR(100) NOT NULL,
    ano               INT,
    cor               VARCHAR(30),
    ar_condicionado   BOOLEAN,
    nome_grupo        VARCHAR(100),
    mecanizacao       VARCHAR(20),
    id_sistema_origem VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_MHSCARDOSO',
    CONSTRAINT pk_stg_mhsc_veiculo PRIMARY KEY (id_veiculo_origem)
);

INSERT INTO staging.stg_mhsc_veiculo
    (id_veiculo_origem, placa, chassi, marca, modelo, ano, cor,
     ar_condicionado, nome_grupo, mecanizacao, id_sistema_origem)
SELECT
    v.idveiculo::VARCHAR          AS id_veiculo_origem,
    v.placa,
    v.chassi,
    NULL::VARCHAR                 AS marca,       -- ausente no schema mhscardoso
    v.modelo,
    v.ano,
    NULL::VARCHAR                 AS cor,         -- ausente no schema mhscardoso
    v.arcondicionado              AS ar_condicionado,
    c.classificacao               AS nome_grupo,  -- Categoria.Classificacao como grupo
    NULL::VARCHAR                 AS mecanizacao, -- ausente no schema mhscardoso
    'GRUPO_MHSCARDOSO'
FROM mhscardoso.veiculo   v
JOIN mhscardoso.categoria c ON c.idcategoria = v.idcategoria
ON CONFLICT (id_veiculo_origem) DO NOTHING;

-- =============================================================================
-- 4. stg_mhsc_reserva
-- =============================================================================
-- Fonte: mhscardoso.reserva
-- Peculiaridades:
--   * id_grupo_origem          → NULL (Reserva liga a CentroCusto, não a grupo de veículo)
--   * id_patio_retirada_origem → NULL (Reserva não contém pátio; pátio é resolvido
--                                      na Locacao via Vaga)
--   * dt_devolucao_prevista    → NULL (Reserva tem DtLimiteRetirada, não DtDevolucao)
--     DtLimiteRetirada = prazo máximo para retirar o veículo, não data de devolução.
--     Registra-se como dt_limite_retirada separadamente para não confundir semântica.

CREATE TABLE IF NOT EXISTS staging.stg_mhsc_reserva (
    id_reserva_origem          VARCHAR(50)  NOT NULL,
    id_cliente_origem          VARCHAR(50)  NOT NULL,
    id_grupo_origem            VARCHAR(50),         -- NULL: ausente em mhscardoso
    id_patio_retirada_origem   VARCHAR(50),         -- NULL: ausente em mhscardoso
    dt_reserva                 TIMESTAMP    NOT NULL,
    dt_retirada_prevista       TIMESTAMP    NOT NULL,
    dt_limite_retirada         TIMESTAMP,           -- prazo máximo de retirada (NÃO é devolução)
    dt_devolucao_prevista      TIMESTAMP,           -- NULL: ausente em mhscardoso
    qt_veiculos_solicitados    INT          NOT NULL DEFAULT 1,
    status                     VARCHAR(30)  NOT NULL,
    id_sistema_origem          VARCHAR(50)  NOT NULL DEFAULT 'GRUPO_MHSCARDOSO',
    CONSTRAINT pk_stg_mhsc_reserva PRIMARY KEY (id_reserva_origem)
);

INSERT INTO staging.stg_mhsc_reserva
    (id_reserva_origem, id_cliente_origem, id_grupo_origem,
     id_patio_retirada_origem, dt_reserva, dt_retirada_prevista,
     dt_limite_retirada, dt_devolucao_prevista,
     qt_veiculos_solicitados, status, id_sistema_origem)
SELECT
    r.idreserva::VARCHAR            AS id_reserva_origem,
    r.idcentrocusto::VARCHAR        AS id_cliente_origem,
    NULL::VARCHAR                   AS id_grupo_origem,           -- ausente: Reserva→CentroCusto, não grupo
    NULL::VARCHAR                   AS id_patio_retirada_origem,  -- ausente: pátio só na Locacao via Vaga
    r.dtreserva,
    r.dtretiradaprevista            AS dt_retirada_prevista,
    r.dtlimiteretirada              AS dt_limite_retirada,
    NULL::TIMESTAMP                 AS dt_devolucao_prevista,     -- campo inexistente na Reserva mhscardoso
    r.qtveiculossolicitados         AS qt_veiculos_solicitados,
    r.status,
    'GRUPO_MHSCARDOSO'
FROM mhscardoso.reserva r
ON CONFLICT (id_reserva_origem) DO NOTHING;

-- =============================================================================
-- 5. stg_mhsc_locacao
-- =============================================================================
-- Fonte: mhscardoso.locacao
--        JOIN mhscardoso.reserva     (para resolver id_cliente via CentroCusto)
--        JOIN mhscardoso.vaga        v_ret → mhscardoso.patio p_ret (pátio retirada)
--        LEFT JOIN mhscardoso.vaga   v_dev → mhscardoso.patio p_dev (pátio devolução)
-- DtChegada (devolução real) é NULL enquanto o veículo não foi devolvido.

CREATE TABLE IF NOT EXISTS staging.stg_mhsc_locacao (
    id_locacao_origem          VARCHAR(50)   NOT NULL,
    id_reserva_origem          VARCHAR(50),
    id_cliente_origem          VARCHAR(50)   NOT NULL,
    id_veiculo_origem          VARCHAR(50)   NOT NULL,
    id_patio_retirada_origem   VARCHAR(50)   NOT NULL,
    id_patio_devolucao_origem  VARCHAR(50),           -- NULL se não devolvido
    dt_retirada                TIMESTAMP     NOT NULL,
    dt_devolucao_real          TIMESTAMP,             -- NULL se locação em aberto
    valor_diaria               NUMERIC(10,2) NOT NULL,
    id_sistema_origem          VARCHAR(50)   NOT NULL DEFAULT 'GRUPO_MHSCARDOSO',
    CONSTRAINT pk_stg_mhsc_locacao PRIMARY KEY (id_locacao_origem)
);

INSERT INTO staging.stg_mhsc_locacao
    (id_locacao_origem, id_reserva_origem, id_cliente_origem,
     id_veiculo_origem, id_patio_retirada_origem, id_patio_devolucao_origem,
     dt_retirada, dt_devolucao_real, valor_diaria, id_sistema_origem)
SELECT
    l.idlocacao::VARCHAR           AS id_locacao_origem,
    l.idreserva::VARCHAR           AS id_reserva_origem,
    r.idcentrocusto::VARCHAR       AS id_cliente_origem,   -- Locacao→Reserva→CentroCusto
    l.idveiculo::VARCHAR           AS id_veiculo_origem,
    p_ret.idpatio::VARCHAR         AS id_patio_retirada_origem,  -- Locacao→VagaRetirada→Patio
    p_dev.idpatio::VARCHAR         AS id_patio_devolucao_origem, -- NULL se não devolvido
    l.dtretirada                   AS dt_retirada,
    l.dtchegada                    AS dt_devolucao_real,   -- DtChegada = devolução real em mhscardoso
    l.valordiaria,
    'GRUPO_MHSCARDOSO'
FROM mhscardoso.locacao     l
JOIN mhscardoso.reserva     r       ON r.idreserva      = l.idreserva
JOIN mhscardoso.vaga        v_ret   ON v_ret.idvaga     = l.idvagaretirada
JOIN mhscardoso.patio       p_ret   ON p_ret.idpatio    = v_ret.idpatio
LEFT JOIN mhscardoso.vaga   v_dev   ON v_dev.idvaga     = l.idvagadevolvida
LEFT JOIN mhscardoso.patio  p_dev   ON p_dev.idpatio    = v_dev.idpatio
ON CONFLICT (id_locacao_origem) DO NOTHING;

-- =============================================================================
-- 6. stg_mhsc_movimentacao
-- =============================================================================
-- Fonte: mhscardoso.movimentacao
--        JOIN  mhscardoso.vaga  v_orig → mhscardoso.patio p_orig  (pátio origem)
--        LEFT JOIN mhscardoso.vaga  v_dest → mhscardoso.patio p_dest (pátio destino)
-- IDVagaDestino pode ser NULL (veículo ainda em trânsito).
-- DtRetirada = quando o veículo saiu da vaga de origem.
-- DtChegada  = quando chegou na vaga de destino (>= DtRetirada per CHECK no OLTP).

CREATE TABLE IF NOT EXISTS staging.stg_mhsc_movimentacao (
    id_movimentacao_origem    VARCHAR(50) NOT NULL,
    id_veiculo_origem         VARCHAR(50) NOT NULL,
    id_patio_origem_origem    VARCHAR(50) NOT NULL,
    id_patio_destino_origem   VARCHAR(50),           -- NULL se veículo em trânsito
    dt_saida_origem           TIMESTAMP   NOT NULL,  -- DtRetirada: saída do pátio de origem
    dt_chegada_destino        TIMESTAMP   NOT NULL,  -- DtChegada: chegada ao pátio de destino
    id_sistema_origem         VARCHAR(50) NOT NULL DEFAULT 'GRUPO_MHSCARDOSO',
    CONSTRAINT pk_stg_mhsc_movimentacao PRIMARY KEY (id_movimentacao_origem)
);

INSERT INTO staging.stg_mhsc_movimentacao
    (id_movimentacao_origem, id_veiculo_origem,
     id_patio_origem_origem, id_patio_destino_origem,
     dt_saida_origem, dt_chegada_destino, id_sistema_origem)
SELECT
    m.idmovimentacao::VARCHAR      AS id_movimentacao_origem,
    m.idveiculo::VARCHAR           AS id_veiculo_origem,
    p_orig.idpatio::VARCHAR        AS id_patio_origem_origem,  -- Movimentacao→VagaOrigem→Patio
    p_dest.idpatio::VARCHAR        AS id_patio_destino_origem, -- NULL se IDVagaDestino é NULL
    m.dtretirada                   AS dt_saida_origem,         -- saída do pátio de origem
    m.dtchegada                    AS dt_chegada_destino,      -- chegada ao pátio de destino
    'GRUPO_MHSCARDOSO'
FROM mhscardoso.movimentacao m
JOIN  mhscardoso.vaga   v_orig  ON v_orig.idvaga   = m.idvagaorigem
JOIN  mhscardoso.patio  p_orig  ON p_orig.idpatio  = v_orig.idpatio
LEFT JOIN mhscardoso.vaga   v_dest  ON v_dest.idvaga   = m.idvagadestino
LEFT JOIN mhscardoso.patio  p_dest  ON p_dest.idpatio  = v_dest.idpatio
ON CONFLICT (id_movimentacao_origem) DO NOTHING;
