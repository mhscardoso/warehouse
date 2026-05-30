-- =====================================================================
--  Modelo Físico — OLTP da Locadora de Veículos
--  Avaliação 01 — Parte I — Modelagem de Data Warehouse
--
--  Grupo:
--    - Gustavo Oliveira Pessanha da Silva — DRE 122051824
--    - André Vinícius Lobo Giron           — DRE 122050404
--
--  SGBD: PostgreSQL (compatível com ANSI SQL:1999+).
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. Pátios e Vagas
-- ---------------------------------------------------------------------

CREATE TABLE patio (
    id_patio          SERIAL       PRIMARY KEY,
    nome              VARCHAR(100) NOT NULL,
    endereco          VARCHAR(200) NOT NULL,
    capacidade_vagas  INTEGER      NOT NULL CHECK (capacidade_vagas >= 0)
);

CREATE TABLE vaga (
    patio_id  INTEGER     NOT NULL REFERENCES patio(id_patio) ON DELETE CASCADE,
    codigo    VARCHAR(20) NOT NULL,
    setor     VARCHAR(30),
    ocupada   BOOLEAN     NOT NULL DEFAULT FALSE,
    PRIMARY KEY (patio_id, codigo)
);


-- ---------------------------------------------------------------------
--  2. Grupos de veículos
-- ---------------------------------------------------------------------

CREATE TABLE grupo (
    id_grupo            SERIAL        PRIMARY KEY,
    codigo              VARCHAR(10)   NOT NULL UNIQUE,
    nome                VARCHAR(50)   NOT NULL,
    classe_luxo         VARCHAR(20)   NOT NULL,
    valor_diaria        NUMERIC(10,2) NOT NULL CHECK (valor_diaria >= 0),
    franquia_km_diaria  INTEGER       NOT NULL CHECK (franquia_km_diaria >= 0)
);


-- ---------------------------------------------------------------------
--  3. Veículos
-- ---------------------------------------------------------------------

CREATE TABLE veiculo (
    id_veiculo           SERIAL        PRIMARY KEY,
    grupo_id             INTEGER       NOT NULL REFERENCES grupo(id_grupo) ON DELETE RESTRICT,
    patio_origem_id      INTEGER       NOT NULL REFERENCES patio(id_patio) ON DELETE RESTRICT,
    placa                VARCHAR(8)    NOT NULL UNIQUE,
    chassi               VARCHAR(17)   NOT NULL UNIQUE,
    renavam              VARCHAR(11)   NOT NULL UNIQUE,
    marca                VARCHAR(30)   NOT NULL,
    modelo               VARCHAR(50)   NOT NULL,
    cor                  VARCHAR(20)   NOT NULL,
    ano_fabricacao       INTEGER       NOT NULL,
    mecanizacao          VARCHAR(10)   NOT NULL CHECK (mecanizacao IN ('MANUAL','AUTOMATICA')),
    tem_ar_condicionado  BOOLEAN       NOT NULL DEFAULT TRUE,
    km_atual             INTEGER       NOT NULL CHECK (km_atual >= 0),
    situacao             VARCHAR(15)   NOT NULL CHECK (situacao IN ('DISPONIVEL','ALUGADO','MANUTENCAO','BAIXADO'))
);


-- ---------------------------------------------------------------------
--  4. Cliente (superclasse) e subclasses PF/PJ
-- ---------------------------------------------------------------------

CREATE TABLE cliente (
    id_cliente      SERIAL       PRIMARY KEY,
    tipo_pessoa     VARCHAR(2)   NOT NULL CHECK (tipo_pessoa IN ('PF','PJ')),
    nome            VARCHAR(150) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    telefone        VARCHAR(20),
    cidade_origem   VARCHAR(80)  NOT NULL,
    data_cadastro   DATE         NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE cliente_pf (
    cliente_id       INTEGER     PRIMARY KEY REFERENCES cliente(id_cliente) ON DELETE CASCADE,
    cpf              VARCHAR(11) NOT NULL UNIQUE,
    rg               VARCHAR(15),
    data_nascimento  DATE        NOT NULL,
    cnh_numero       VARCHAR(15) NOT NULL UNIQUE,
    cnh_categoria    VARCHAR(2)  NOT NULL CHECK (cnh_categoria IN ('A','B','AB','C','AC','D','AD','E','AE')),
    cnh_validade     DATE        NOT NULL
);

CREATE TABLE cliente_pj (
    cliente_id       INTEGER      PRIMARY KEY REFERENCES cliente(id_cliente) ON DELETE CASCADE,
    cnpj             VARCHAR(14)  NOT NULL UNIQUE,
    nome_fantasia    VARCHAR(150),
    responsavel      VARCHAR(150) NOT NULL
);


-- ---------------------------------------------------------------------
--  5. Condutores (entidade fraca de cliente_pj)
-- ---------------------------------------------------------------------

CREATE TABLE condutor (
    cliente_pj_id  INTEGER     NOT NULL REFERENCES cliente_pj(cliente_id) ON DELETE CASCADE,
    cpf            VARCHAR(11) NOT NULL,
    nome           VARCHAR(150) NOT NULL,
    cnh_numero     VARCHAR(15) NOT NULL UNIQUE,
    cnh_categoria  VARCHAR(2)  NOT NULL CHECK (cnh_categoria IN ('A','B','AB','C','AC','D','AD','E','AE')),
    cnh_validade   DATE        NOT NULL,
    PRIMARY KEY (cliente_pj_id, cpf)
);


-- ---------------------------------------------------------------------
--  6. Reservas
-- ---------------------------------------------------------------------

CREATE TABLE reserva (
    id_reserva               SERIAL    PRIMARY KEY,
    cliente_id               INTEGER   NOT NULL REFERENCES cliente(id_cliente) ON DELETE RESTRICT,
    grupo_id                 INTEGER   NOT NULL REFERENCES grupo(id_grupo) ON DELETE RESTRICT,
    patio_retirada_id        INTEGER   NOT NULL REFERENCES patio(id_patio) ON DELETE RESTRICT,
    patio_devolucao_id       INTEGER   NOT NULL REFERENCES patio(id_patio) ON DELETE RESTRICT,
    data_reserva             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_retirada_prevista   TIMESTAMP NOT NULL,
    data_devolucao_prevista  TIMESTAMP NOT NULL,
    estado                   VARCHAR(20) NOT NULL CHECK (estado IN ('CONFIRMADA','EM_FILA_ESPERA','CANCELADA','CONCRETIZADA')),
    CHECK (data_devolucao_prevista > data_retirada_prevista)
);


-- ---------------------------------------------------------------------
--  7. Locações
-- ---------------------------------------------------------------------

CREATE TABLE locacao (
    id_locacao             SERIAL        PRIMARY KEY,
    numero_contrato        VARCHAR(30)   NOT NULL UNIQUE,
    reserva_id             INTEGER       UNIQUE REFERENCES reserva(id_reserva) ON DELETE RESTRICT,
    cliente_id             INTEGER       NOT NULL REFERENCES cliente(id_cliente) ON DELETE RESTRICT,
    veiculo_id             INTEGER       NOT NULL REFERENCES veiculo(id_veiculo) ON DELETE RESTRICT,
    patio_retirada_id      INTEGER       NOT NULL REFERENCES patio(id_patio) ON DELETE RESTRICT,
    patio_devolucao_id     INTEGER       NOT NULL REFERENCES patio(id_patio) ON DELETE RESTRICT,
    data_retirada_real     TIMESTAMP     NOT NULL,
    data_devolucao_real    TIMESTAMP,
    km_saida               INTEGER       NOT NULL CHECK (km_saida >= 0),
    km_chegada             INTEGER       CHECK (km_chegada IS NULL OR km_chegada >= km_saida),
    valor_diaria_aplicada  NUMERIC(10,2) NOT NULL CHECK (valor_diaria_aplicada >= 0),
    status                 VARCHAR(15)   NOT NULL CHECK (status IN ('EM_ANDAMENTO','CONCLUIDA','CANCELADA')),
    CHECK (data_devolucao_real IS NULL OR data_devolucao_real > data_retirada_real)
);

-- R03: um veículo só pode ter uma locação EM_ANDAMENTO por vez.
-- Implementado por índice único parcial (extensão padrão de PostgreSQL).
CREATE UNIQUE INDEX uq_locacao_veiculo_em_andamento
    ON locacao (veiculo_id)
    WHERE status = 'EM_ANDAMENTO';


-- ---------------------------------------------------------------------
--  8. Cobranças
-- ---------------------------------------------------------------------

CREATE TABLE cobranca (
    id_cobranca   SERIAL        PRIMARY KEY,
    locacao_id    INTEGER       NOT NULL REFERENCES locacao(id_locacao) ON DELETE RESTRICT,
    data_emissao  DATE          NOT NULL DEFAULT CURRENT_DATE,
    valor_total   NUMERIC(10,2) NOT NULL CHECK (valor_total >= 0),
    status        VARCHAR(15)   NOT NULL CHECK (status IN ('PENDENTE','PAGA','CANCELADA'))
);


-- ---------------------------------------------------------------------
--  9. Índices auxiliares (em FKs com filtro frequente)
-- ---------------------------------------------------------------------

CREATE INDEX ix_veiculo_grupo            ON veiculo(grupo_id);
CREATE INDEX ix_veiculo_situacao         ON veiculo(situacao);
CREATE INDEX ix_reserva_cliente          ON reserva(cliente_id);
CREATE INDEX ix_reserva_grupo_estado     ON reserva(grupo_id, estado);
CREATE INDEX ix_locacao_cliente          ON locacao(cliente_id);
CREATE INDEX ix_locacao_veiculo_status   ON locacao(veiculo_id, status);
CREATE INDEX ix_cobranca_locacao         ON cobranca(locacao_id);


-- ---------------------------------------------------------------------
-- 10. Views para os relatórios gerenciais (item 12 do enunciado)
-- ---------------------------------------------------------------------

-- 12.a Controle de pátio: veículos disponíveis por pátio de origem e grupo
CREATE VIEW vw_veiculos_por_patio_grupo AS
SELECT p.nome AS patio, g.codigo AS grupo, COUNT(*) AS total
FROM veiculo v
JOIN grupo g ON g.id_grupo = v.grupo_id
JOIN patio p ON p.id_patio = v.patio_origem_id
WHERE v.situacao = 'DISPONIVEL'
GROUP BY p.nome, g.codigo;

-- 12.b Controle das locações em andamento
CREATE VIEW vw_locacoes_em_andamento AS
SELECT g.codigo AS grupo, COUNT(*) AS total_locacoes
FROM locacao l
JOIN veiculo v ON v.id_veiculo = l.veiculo_id
JOIN grupo g   ON g.id_grupo  = v.grupo_id
WHERE l.status = 'EM_ANDAMENTO'
GROUP BY g.codigo;

-- 12.c Reservas por grupo, pátio de retirada e cidade de origem do cliente
CREATE VIEW vw_reservas_por_grupo_patio_cidade AS
SELECT g.codigo AS grupo, p.nome AS patio_retirada,
       c.cidade_origem, COUNT(*) AS total
FROM reserva r
JOIN grupo  g ON g.id_grupo  = r.grupo_id
JOIN patio  p ON p.id_patio  = r.patio_retirada_id
JOIN cliente c ON c.id_cliente = r.cliente_id
WHERE r.estado IN ('CONFIRMADA','EM_FILA_ESPERA')
GROUP BY g.codigo, p.nome, c.cidade_origem;

-- 12.d Grupos mais alugados × cidade do cliente
CREATE VIEW vw_grupos_alugados_por_cidade AS
SELECT c.cidade_origem, g.codigo AS grupo, COUNT(*) AS total_locacoes
FROM locacao l
JOIN cliente c ON c.id_cliente = l.cliente_id
JOIN veiculo v ON v.id_veiculo = l.veiculo_id
JOIN grupo   g ON g.id_grupo   = v.grupo_id
GROUP BY c.cidade_origem, g.codigo
ORDER BY total_locacoes DESC;

-- 13 Movimentação entre pátios (insumo para matriz de Markov)
CREATE VIEW vw_movimentacao_patio AS
SELECT pr.nome AS patio_retirada, pd.nome AS patio_devolucao,
       COUNT(*) AS total_locacoes
FROM locacao l
JOIN patio pr ON pr.id_patio = l.patio_retirada_id
JOIN patio pd ON pd.id_patio = l.patio_devolucao_id
WHERE l.status = 'CONCLUIDA'
GROUP BY pr.nome, pd.nome;
