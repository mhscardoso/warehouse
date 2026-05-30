-- =========================================================
-- Projeto: Sistema de Locadora de Veículos
-- Arquivo: 01_create_table.sql
-- Alunos: Breno Belaid Machado Wanderley - 121122313
---------- Hygor Goulart Knust - 117124785
---------- João Valviesse Peclat Brito - 115065139
-- Descrição: Criação das tabelas base do modelo relacional
-- =========================================================

CREATE TABLE EMPRESA (
    id_empresa INTEGER PRIMARY KEY,
    nome_empresa VARCHAR(100) NOT NULL
);

CREATE TABLE PATIO (
    id_patio INTEGER PRIMARY KEY,
    id_empresa INTEGER NOT NULL,
    nome_patio VARCHAR(100) NOT NULL,
    localizacao VARCHAR(150) NOT NULL,
    codigo_patio VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE GRUPO_VEICULO (
    id_grupo INTEGER PRIMARY KEY,
    nome_grupo VARCHAR(50) NOT NULL,
    descricao VARCHAR(200),
    faixa_valor_diaria DECIMAL(10,2) NOT NULL
);

CREATE TABLE CLIENTE (
    id_cliente INTEGER PRIMARY KEY,
    tipo_cliente VARCHAR(2) NOT NULL,
    nome_razao_social VARCHAR(150) NOT NULL,
    cpf_cnpj VARCHAR(20) NOT NULL,
    cidade VARCHAR(50) NOT NULL,
    estado VARCHAR(2) NOT NULL,
    telefone VARCHAR(20),
    email VARCHAR(100)
);

CREATE TABLE CONDUTOR (
    id_condutor INTEGER PRIMARY KEY,
    nome_condutor VARCHAR(150) NOT NULL,
    cpf VARCHAR(20) NOT NULL,
    numero_cnh VARCHAR(20) NOT NULL,
    categoria_cnh VARCHAR(5) NOT NULL,
    validade_cnh DATE NOT NULL,
    id_cliente INTEGER NOT NULL
);

CREATE TABLE VEICULO (
    id_veiculo INTEGER PRIMARY KEY,
    placa VARCHAR(10) NOT NULL,
    chassi VARCHAR(50) NOT NULL,
    marca VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    cor VARCHAR(30) NOT NULL,
    mecanizacao VARCHAR(20) NOT NULL,
    ar_condicionado BOOLEAN NOT NULL,
    status VARCHAR(20) NOT NULL,
    id_grupo INTEGER NOT NULL,
    id_empresa INTEGER NOT NULL,
    id_patio_atual INTEGER NOT NULL
);

CREATE TABLE RESERVA (
    id_reserva INTEGER PRIMARY KEY,
    data_reserva DATE NOT NULL,
    data_prev_retirada DATE NOT NULL,
    data_prev_devolucao DATE NOT NULL,
    status_reserva VARCHAR(20) NOT NULL,
    id_cliente INTEGER NOT NULL,
    id_grupo INTEGER NOT NULL,
    id_patio_retirada INTEGER NOT NULL,
    id_patio_devolucao_previsto INTEGER NOT NULL
);

CREATE TABLE LOCACAO (
    id_locacao INTEGER PRIMARY KEY,
    data_hora_retirada TIMESTAMP NOT NULL,
    data_hora_prev_devolucao TIMESTAMP NOT NULL,
    data_hora_real_devolucao TIMESTAMP,
    valor_previsto DECIMAL(10,2) NOT NULL,
    valor_final DECIMAL(10,2),
    status_locacao VARCHAR(20) NOT NULL,
    id_reserva INTEGER,
    id_cliente INTEGER NOT NULL,
    id_condutor INTEGER NOT NULL,
    id_veiculo INTEGER NOT NULL,
    id_patio_retirada INTEGER NOT NULL,
    id_patio_devolucao_previsto INTEGER NOT NULL,
    id_patio_devolucao_real INTEGER
);

CREATE TABLE PAGAMENTO (
    id_pagamento INTEGER PRIMARY KEY,
    data_pagamento DATE NOT NULL,
    valor_pagamento DECIMAL(10,2) NOT NULL,
    forma_pagamento VARCHAR(20) NOT NULL,
    tipo_pagamento VARCHAR(20) NOT NULL,
    id_locacao INTEGER NOT NULL
);

CREATE TABLE MOVIMENTACAO_PATIO (
    id_movimentacao INTEGER PRIMARY KEY,
    data_hora_movimentacao TIMESTAMP NOT NULL,
    motivo_movimentacao VARCHAR(100) NOT NULL,
    id_veiculo INTEGER NOT NULL,
    id_patio_origem INTEGER NOT NULL,
    id_patio_destino INTEGER NOT NULL
);


-- =========================================================
-- Projeto: Sistema de Locadora de Veículos
-- Arquivo: 02_constraints.sql
-- Alunos: Breno Belaid Machado Wanderley - 121122313
---------- Hygor Goulart Knust - 117124785
---------- João Valviesse Peclat Brito - 115065139
-- Descrição: Constraints de integridade referencial e regras
--             adicionais do modelo relacional
-- =========================================================

-- =========================================================
-- FOREIGN KEYS
-- =========================================================

ALTER TABLE PATIO
    ADD CONSTRAINT fk_patio_empresa
    FOREIGN KEY (id_empresa)
    REFERENCES EMPRESA (id_empresa);

ALTER TABLE CONDUTOR
    ADD CONSTRAINT fk_condutor_cliente
    FOREIGN KEY (id_cliente)
    REFERENCES CLIENTE (id_cliente);

ALTER TABLE VEICULO
    ADD CONSTRAINT fk_veiculo_grupo
    FOREIGN KEY (id_grupo)
    REFERENCES GRUPO_VEICULO (id_grupo);

ALTER TABLE VEICULO
    ADD CONSTRAINT fk_veiculo_empresa
    FOREIGN KEY (id_empresa)
    REFERENCES EMPRESA (id_empresa);

ALTER TABLE VEICULO
    ADD CONSTRAINT fk_veiculo_patio_atual
    FOREIGN KEY (id_patio_atual)
    REFERENCES PATIO (id_patio);

ALTER TABLE RESERVA
    ADD CONSTRAINT fk_reserva_cliente
    FOREIGN KEY (id_cliente)
    REFERENCES CLIENTE (id_cliente);

ALTER TABLE RESERVA
    ADD CONSTRAINT fk_reserva_grupo
    FOREIGN KEY (id_grupo)
    REFERENCES GRUPO_VEICULO (id_grupo);

ALTER TABLE RESERVA
    ADD CONSTRAINT fk_reserva_patio_retirada
    FOREIGN KEY (id_patio_retirada)
    REFERENCES PATIO (id_patio);

ALTER TABLE RESERVA
    ADD CONSTRAINT fk_reserva_patio_devolucao_prev
    FOREIGN KEY (id_patio_devolucao_previsto)
    REFERENCES PATIO (id_patio);

ALTER TABLE LOCACAO
    ADD CONSTRAINT fk_locacao_reserva
    FOREIGN KEY (id_reserva)
    REFERENCES RESERVA (id_reserva);

ALTER TABLE LOCACAO
    ADD CONSTRAINT fk_locacao_cliente
    FOREIGN KEY (id_cliente)
    REFERENCES CLIENTE (id_cliente);

ALTER TABLE LOCACAO
    ADD CONSTRAINT fk_locacao_condutor
    FOREIGN KEY (id_condutor)
    REFERENCES CONDUTOR (id_condutor);

ALTER TABLE LOCACAO
    ADD CONSTRAINT fk_locacao_veiculo
    FOREIGN KEY (id_veiculo)
    REFERENCES VEICULO (id_veiculo);

ALTER TABLE LOCACAO
    ADD CONSTRAINT fk_locacao_patio_retirada
    FOREIGN KEY (id_patio_retirada)
    REFERENCES PATIO (id_patio);

ALTER TABLE LOCACAO
    ADD CONSTRAINT fk_locacao_patio_devolucao_prev
    FOREIGN KEY (id_patio_devolucao_previsto)
    REFERENCES PATIO (id_patio);

ALTER TABLE LOCACAO
    ADD CONSTRAINT fk_locacao_patio_devolucao_real
    FOREIGN KEY (id_patio_devolucao_real)
    REFERENCES PATIO (id_patio);

ALTER TABLE PAGAMENTO
    ADD CONSTRAINT fk_pagamento_locacao
    FOREIGN KEY (id_locacao)
    REFERENCES LOCACAO (id_locacao);

ALTER TABLE MOVIMENTACAO_PATIO
    ADD CONSTRAINT fk_movimentacao_veiculo
    FOREIGN KEY (id_veiculo)
    REFERENCES VEICULO (id_veiculo);

ALTER TABLE MOVIMENTACAO_PATIO
    ADD CONSTRAINT fk_movimentacao_patio_origem
    FOREIGN KEY (id_patio_origem)
    REFERENCES PATIO (id_patio);

ALTER TABLE MOVIMENTACAO_PATIO
    ADD CONSTRAINT fk_movimentacao_patio_destino
    FOREIGN KEY (id_patio_destino)
    REFERENCES PATIO (id_patio);

-- =========================================================
-- UNIQUE CONSTRAINTS
-- =========================================================

ALTER TABLE CLIENTE
    ADD CONSTRAINT uq_cliente_cpf_cnpj
    UNIQUE (cpf_cnpj);

ALTER TABLE CONDUTOR
    ADD CONSTRAINT uq_condutor_cpf
    UNIQUE (cpf);

ALTER TABLE CONDUTOR
    ADD CONSTRAINT uq_condutor_numero_cnh
    UNIQUE (numero_cnh);

ALTER TABLE VEICULO
    ADD CONSTRAINT uq_veiculo_placa
    UNIQUE (placa);

ALTER TABLE VEICULO
    ADD CONSTRAINT uq_veiculo_chassi
    UNIQUE (chassi);

-- =========================================================
-- CHECK CONSTRAINTS
-- =========================================================

ALTER TABLE CLIENTE
    ADD CONSTRAINT ck_cliente_tipo
    CHECK (tipo_cliente IN ('PF', 'PJ'));

ALTER TABLE CLIENTE
    ADD CONSTRAINT ck_cliente_estado
    CHECK (CHAR_LENGTH(estado) = 2);

ALTER TABLE VEICULO
    ADD CONSTRAINT ck_veiculo_mecanizacao
    CHECK (mecanizacao IN ('MANUAL', 'AUTOMATICO'));

ALTER TABLE VEICULO
    ADD CONSTRAINT ck_veiculo_status
    CHECK (status IN ('DISPONIVEL', 'ALUGADO', 'MANUTENCAO', 'RESERVADO'));

ALTER TABLE GRUPO_VEICULO
    ADD CONSTRAINT ck_grupo_valor_diaria
    CHECK (faixa_valor_diaria > 0);

ALTER TABLE CONDUTOR
    ADD CONSTRAINT ck_condutor_validade_cnh
    CHECK (validade_cnh >= CURRENT_DATE);

ALTER TABLE RESERVA
    ADD CONSTRAINT ck_reserva_status
    CHECK (status_reserva IN ('ATIVA', 'CANCELADA', 'CONVERTIDA'));

ALTER TABLE RESERVA
    ADD CONSTRAINT ck_reserva_datas
    CHECK (data_prev_devolucao >= data_prev_retirada);

ALTER TABLE RESERVA
    ADD CONSTRAINT ck_reserva_data_registro
    CHECK (data_reserva <= data_prev_retirada);

ALTER TABLE LOCACAO
    ADD CONSTRAINT ck_locacao_status
    CHECK (status_locacao IN ('ATIVA', 'FINALIZADA', 'CANCELADA'));

ALTER TABLE LOCACAO
    ADD CONSTRAINT ck_locacao_valor_previsto
    CHECK (valor_previsto > 0);

ALTER TABLE LOCACAO
    ADD CONSTRAINT ck_locacao_valor_final
    CHECK (valor_final IS NULL OR valor_final >= 0);

ALTER TABLE LOCACAO
    ADD CONSTRAINT ck_locacao_datas_previstas
    CHECK (data_hora_prev_devolucao >= data_hora_retirada);

ALTER TABLE LOCACAO
    ADD CONSTRAINT ck_locacao_data_real
    CHECK (
        data_hora_real_devolucao IS NULL
        OR data_hora_real_devolucao >= data_hora_retirada
    );

ALTER TABLE PAGAMENTO
    ADD CONSTRAINT ck_pagamento_valor
    CHECK (valor_pagamento > 0);

ALTER TABLE PAGAMENTO
    ADD CONSTRAINT ck_pagamento_forma
    CHECK (forma_pagamento IN ('DINHEIRO', 'CARTAO', 'PIX', 'BOLETO'));

ALTER TABLE PAGAMENTO
    ADD CONSTRAINT ck_pagamento_tipo
    CHECK (tipo_pagamento IN ('ENTRADA', 'PARCIAL', 'FINAL'));

ALTER TABLE MOVIMENTACAO_PATIO
    ADD CONSTRAINT ck_movimentacao_patio_diferente
    CHECK (id_patio_origem <> id_patio_destino);
