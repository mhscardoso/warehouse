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
-- Arquivo  : 02_dw_schema/create_dw_v2.sql
-- Projeto  : Locadora de Veículos — Data Warehouse (Parte II)
-- Versão   : 2
-- SGBD     : PostgreSQL (ANSI SQL:1999+)
-- Schema   : dw
--
-- DIFERENÇAS EM RELAÇÃO À v1 (create_dw.sql — entregável da Parte I):
--
-- 1. [fato_locacao] REMOVIDO campo tempo_restante_devolucao_dias INT
--    Motivo: campo derivado (calculado como DATE_PART('day',
--    t_dev_prev.dt_ref - CURRENT_DATE)). Armazená-lo viola a regra de não
--    guardar métricas calculáveis, desperdiça espaço e fica stale a cada
--    dia sem re-carga. Em query usa-se a SK já presente (sk_tempo_devolucao_prevista).
--
-- 2. [fato_reserva] ADICIONADO sk_tempo_devolucao_prevista INT
--    Motivo: a v1 só armazenava sk_tempo_retirada_prevista, impossibilitando
--    calcular a duração planejada da reserva (data_devolucao - data_retirada)
--    diretamente no DW. Fontes tadeupires, gupessanha e valviesse possuem
--    data_prev_devolucao; para mhscardoso (sem esse campo em Reserva) o
--    valor é NULL — aceito por ser coluna nullable.
--
-- 3. [dim_veiculo] ADICIONADO UNIQUE(placa)
--    Motivo: a placa é identificador natural do veículo em todas as fontes.
--    Sem UNIQUE, o ETL pode inserir duplicatas do mesmo veículo vindo de
--    sistemas diferentes ou de re-execuções parciais, corrompendo joins na
--    fato. O UNIQUE garante idempotência da carga.
--
-- 4. [dim_tempo] ADICIONADO semana_ano INT NOT NULL
--    Motivo: análises por semana (ocupação semanal, sazonalidade) eram
--    impossíveis na v1 sem GROUP BY calculado. A semana ISO (1-53) é um
--    atributo estável da dimensão tempo e deve estar pré-calculado.
--
-- 5. [dim_patio] ADICIONADO localizacao VARCHAR(100)
--    Motivo: as fontes valviesse (PATIO.localizacao) e mhscardoso
--    (Endereco concatenado) têm endereço detalhado do pátio. A v1 só
--    armazenava nome e cidade, perdendo granularidade geográfica útil
--    para relatórios operacionais e visualização de mapa.
-- =============================================================================

-- =============================================================================
-- 0. Infraestrutura
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS dw;

-- =============================================================================
-- 1. Dimensão Tempo
-- =============================================================================
-- sk_tempo recomendado = data no formato YYYYMMDD (ex.: 20240101).
-- Isso facilita filtros por range e é legível sem JOIN.

CREATE TABLE dw.dim_tempo (
    sk_tempo          INT          NOT NULL,
    dt_ref            DATE         NOT NULL,
    dia               SMALLINT     NOT NULL CHECK (dia BETWEEN 1 AND 31),
    mes               SMALLINT     NOT NULL CHECK (mes BETWEEN 1 AND 12),
    trimestre         SMALLINT     NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    semestre          SMALLINT     NOT NULL CHECK (semestre BETWEEN 1 AND 2),
    ano               SMALLINT     NOT NULL CHECK (ano >= 1900),
    dia_semana        SMALLINT     NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
    nome_dia          VARCHAR(20)  NOT NULL,
    nome_mes          VARCHAR(20)  NOT NULL,
    semana_ano        INT          NOT NULL CHECK (semana_ano BETWEEN 1 AND 53), -- v2: semana ISO do ano
    is_feriado        BOOLEAN      NOT NULL DEFAULT FALSE,

    CONSTRAINT pk_dim_tempo PRIMARY KEY (sk_tempo),
    CONSTRAINT uq_dim_tempo_data UNIQUE (dt_ref)
);

COMMENT ON COLUMN dw.dim_tempo.dia_semana IS '1 = Segunda, 7 = Domingo (ISO 8601)';
COMMENT ON COLUMN dw.dim_tempo.semana_ano IS 'Semana ISO do ano (1-53). Adicionado na v2.';

-- =============================================================================
-- 2. Dimensão Pátio
-- =============================================================================

CREATE TABLE dw.dim_patio (
    sk_patio           SERIAL       NOT NULL,
    id_patio_origem    VARCHAR(50),
    nome_patio         VARCHAR(100) NOT NULL,
    cidade             VARCHAR(100),
    localizacao        VARCHAR(100),  -- v2: endereço/localização detalhada do pátio
    id_sistema_origem  VARCHAR(50)  NOT NULL,

    CONSTRAINT pk_dim_patio PRIMARY KEY (sk_patio)
);

COMMENT ON COLUMN dw.dim_patio.localizacao  IS 'Endereço ou localização detalhada. Adicionado na v2. '
                                               'NULL para fontes que não fornecem esse campo.';
COMMENT ON COLUMN dw.dim_patio.id_sistema_origem IS 'Identifica o grupo/sistema de origem dos dados.';

-- =============================================================================
-- 3. Dimensão Cliente
-- =============================================================================
-- Representa a entidade contratante da locação (PF ou PJ).
-- Em mhscardoso o cliente corresponde ao CentroCusto (PessoaFisica | Empresa).

CREATE TABLE dw.dim_cliente (
    sk_cliente         SERIAL       NOT NULL,
    id_cliente_origem  VARCHAR(50),
    nome_cliente       VARCHAR(255) NOT NULL,
    tipo_cliente       CHAR(2)      NOT NULL DEFAULT 'PF',
    cidade_origem      VARCHAR(100),
    estado_origem      CHAR(2),
    id_sistema_origem  VARCHAR(50)  NOT NULL,

    CONSTRAINT pk_dim_cliente    PRIMARY KEY (sk_cliente),
    CONSTRAINT chk_tipo_cliente  CHECK (tipo_cliente IN ('PF','PJ'))
);

-- =============================================================================
-- 4. Dimensão Grupo de Veículo
-- =============================================================================
-- Em mhscardoso não existe tabela de grupo — usa-se Categoria.Classificacao
-- como nome_grupo e mecanizacao fica NULL (campo ausente no OLTP).

CREATE TABLE dw.dim_grupo (
    sk_grupo           SERIAL        NOT NULL,
    id_grupo_origem    VARCHAR(50),
    nome_grupo         VARCHAR(100)  NOT NULL,
    mecanizacao        VARCHAR(20),           -- NULL quando a fonte não informa
    classe_luxo        VARCHAR(20),
    valor_diaria_base  NUMERIC(10,2),
    id_sistema_origem  VARCHAR(50)   NOT NULL,

    CONSTRAINT pk_dim_grupo    PRIMARY KEY (sk_grupo),
    CONSTRAINT chk_mecanizacao CHECK (mecanizacao IS NULL
                                      OR mecanizacao IN ('MANUAL','AUTOMATICO'))
);

COMMENT ON COLUMN dw.dim_grupo.mecanizacao IS 'NULL para mhscardoso (não disponível no OLTP fonte).';

-- =============================================================================
-- 5. Dimensão Veículo
-- =============================================================================
-- UNIQUE(placa) adicionado na v2 para garantir idempotência do ETL
-- e evitar duplicatas cross-sistema.

CREATE TABLE dw.dim_veiculo (
    sk_veiculo         SERIAL       NOT NULL,
    id_veiculo_origem  VARCHAR(50),
    placa              VARCHAR(10)  NOT NULL,
    chassi             VARCHAR(30),
    marca              VARCHAR(50),           -- NULL para mhscardoso (ausente no OLTP)
    modelo             VARCHAR(100) NOT NULL,
    ano                SMALLINT,
    cor                VARCHAR(30),           -- NULL para mhscardoso (ausente no OLTP)
    ar_condicionado    BOOLEAN,
    id_sistema_origem  VARCHAR(50)  NOT NULL,

    CONSTRAINT pk_dim_veiculo      PRIMARY KEY (sk_veiculo),
    CONSTRAINT uq_dim_veiculo_placa UNIQUE (placa)  -- v2: unicidade da placa no DW
);

COMMENT ON COLUMN dw.dim_veiculo.marca IS 'NULL para mhscardoso (campo ausente no OLTP fonte).';
COMMENT ON COLUMN dw.dim_veiculo.cor   IS 'NULL para mhscardoso (campo ausente no OLTP fonte).';

-- =============================================================================
-- 6. Fato Locação
-- =============================================================================
-- Grão: uma linha por locação (contrato de retirada de veículo).
-- sk_patio_devolucao e sk_tempo_devolucao são NULL enquanto o veículo não foi devolvido.
-- REMOVIDO da v1: tempo_restante_devolucao_dias INT (campo derivado).
--   Para obtê-lo em query: DATE_PART('day', tp.dt_ref - CURRENT_DATE)
--   onde tp é o JOIN com dim_tempo via sk_tempo_devolucao_prevista.

CREATE TABLE dw.fato_locacao (
    sk_locacao                   SERIAL        NOT NULL,
    sk_cliente                   INT           NOT NULL,
    sk_veiculo                   INT           NOT NULL,
    sk_grupo                     INT           NOT NULL,
    sk_patio_retirada            INT           NOT NULL,
    sk_patio_devolucao           INT,          -- NULL se locação ainda em aberto
    sk_tempo_retirada            INT           NOT NULL,
    sk_tempo_devolucao           INT,          -- NULL se locação ainda em aberto
    sk_tempo_devolucao_prevista  INT           NOT NULL,
    -- [v1 tinha: tempo_restante_devolucao_dias INT — removido na v2]
    valor_diaria                 NUMERIC(10,2) NOT NULL,
    dias_locacao                 INT,          -- NULL se locação em aberto; calculado no ETL
    km_rodados                   INT,          -- NULL para mhscardoso (ausente no OLTP)
    valor_total                  NUMERIC(10,2),
    status                       VARCHAR(30)   NOT NULL,
    id_sistema_origem            VARCHAR(50)   NOT NULL,

    CONSTRAINT pk_fato_locacao      PRIMARY KEY (sk_locacao),
    CONSTRAINT fk_fl_cliente        FOREIGN KEY (sk_cliente)
        REFERENCES dw.dim_cliente(sk_cliente),
    CONSTRAINT fk_fl_veiculo        FOREIGN KEY (sk_veiculo)
        REFERENCES dw.dim_veiculo(sk_veiculo),
    CONSTRAINT fk_fl_grupo          FOREIGN KEY (sk_grupo)
        REFERENCES dw.dim_grupo(sk_grupo),
    CONSTRAINT fk_fl_patio_ret      FOREIGN KEY (sk_patio_retirada)
        REFERENCES dw.dim_patio(sk_patio),
    CONSTRAINT fk_fl_patio_dev      FOREIGN KEY (sk_patio_devolucao)
        REFERENCES dw.dim_patio(sk_patio),
    CONSTRAINT fk_fl_tempo_ret      FOREIGN KEY (sk_tempo_retirada)
        REFERENCES dw.dim_tempo(sk_tempo),
    CONSTRAINT fk_fl_tempo_dev      FOREIGN KEY (sk_tempo_devolucao)
        REFERENCES dw.dim_tempo(sk_tempo),
    CONSTRAINT fk_fl_tempo_dev_prev FOREIGN KEY (sk_tempo_devolucao_prevista)
        REFERENCES dw.dim_tempo(sk_tempo)
);

-- =============================================================================
-- 7. Fato Reserva
-- =============================================================================
-- Grão: uma linha por reserva.
-- sk_grupo e sk_patio_retirada são NULL para mhscardoso (Reserva não tem
-- grupo nem pátio diretos — registra-se NULL conforme CONTEXT.MD).
-- ADICIONADO na v2: sk_tempo_devolucao_prevista para calcular duração planejada.

CREATE TABLE dw.fato_reserva (
    sk_reserva                   SERIAL      NOT NULL,
    sk_cliente                   INT         NOT NULL,
    sk_grupo                     INT,         -- NULL para mhscardoso
    sk_patio_retirada            INT,         -- NULL para mhscardoso
    sk_patio_devolucao           INT,         -- NULL para mhscardoso
    sk_tempo_reserva             INT         NOT NULL,
    sk_tempo_retirada_prevista   INT         NOT NULL,
    sk_tempo_devolucao_prevista  INT,         -- v2: NULL para mhscardoso (ausente em Reserva)
    antecedencia_dias            INT,
    qt_veiculos_solicitados      INT         NOT NULL DEFAULT 1,
    status                       VARCHAR(30) NOT NULL,
    id_sistema_origem            VARCHAR(50) NOT NULL,

    CONSTRAINT pk_fato_reserva       PRIMARY KEY (sk_reserva),
    CONSTRAINT fk_fr_cliente         FOREIGN KEY (sk_cliente)
        REFERENCES dw.dim_cliente(sk_cliente),
    CONSTRAINT fk_fr_grupo           FOREIGN KEY (sk_grupo)
        REFERENCES dw.dim_grupo(sk_grupo),
    CONSTRAINT fk_fr_patio_ret       FOREIGN KEY (sk_patio_retirada)
        REFERENCES dw.dim_patio(sk_patio),
    CONSTRAINT fk_fr_patio_dev       FOREIGN KEY (sk_patio_devolucao)
        REFERENCES dw.dim_patio(sk_patio),
    CONSTRAINT fk_fr_tempo_res       FOREIGN KEY (sk_tempo_reserva)
        REFERENCES dw.dim_tempo(sk_tempo),
    CONSTRAINT fk_fr_tempo_ret_prev  FOREIGN KEY (sk_tempo_retirada_prevista)
        REFERENCES dw.dim_tempo(sk_tempo),
    CONSTRAINT fk_fr_tempo_dev_prev  FOREIGN KEY (sk_tempo_devolucao_prevista)
        REFERENCES dw.dim_tempo(sk_tempo)  -- v2: adicionado
);

COMMENT ON COLUMN dw.fato_reserva.sk_grupo    IS 'NULL para mhscardoso: Reserva não referencia grupo diretamente.';
COMMENT ON COLUMN dw.fato_reserva.sk_patio_retirada IS 'NULL para mhscardoso: pátio só é conhecido na Locacao (via Vaga).';
COMMENT ON COLUMN dw.fato_reserva.sk_tempo_devolucao_prevista IS 'Adicionado na v2. NULL para mhscardoso (DtDevolucaoPrevista ausente em Reserva).';

-- =============================================================================
-- 8. Fato Movimentação de Pátio
-- =============================================================================
-- Grão: uma transferência de veículo entre dois pátios.
-- sk_patio_destino é NULL se o veículo ainda está em trânsito (IDVagaDestino NULL).

CREATE TABLE dw.fato_movimentacao_patio (
    sk_movimentacao    SERIAL       NOT NULL,
    sk_veiculo         INT          NOT NULL,
    sk_patio_origem    INT          NOT NULL,
    sk_patio_destino   INT,         -- NULL se veículo ainda em trânsito
    sk_tempo           INT          NOT NULL,  -- data/hora de saída do pátio origem
    motivo             VARCHAR(100),
    id_sistema_origem  VARCHAR(50)  NOT NULL,

    CONSTRAINT pk_fato_movimentacao   PRIMARY KEY (sk_movimentacao),
    CONSTRAINT fk_fm_veiculo          FOREIGN KEY (sk_veiculo)
        REFERENCES dw.dim_veiculo(sk_veiculo),
    CONSTRAINT fk_fm_patio_orig       FOREIGN KEY (sk_patio_origem)
        REFERENCES dw.dim_patio(sk_patio),
    CONSTRAINT fk_fm_patio_dest       FOREIGN KEY (sk_patio_destino)
        REFERENCES dw.dim_patio(sk_patio),
    CONSTRAINT fk_fm_tempo            FOREIGN KEY (sk_tempo)
        REFERENCES dw.dim_tempo(sk_tempo)
);

COMMENT ON COLUMN dw.fato_movimentacao_patio.sk_tempo IS 'Referencia o dia da movimentação (DtRetirada/data_saida da origem).';
