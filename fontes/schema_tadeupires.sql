-- =====================================
Grupo: Tadeu Belfort Neto -119034813 
         Vicente Alves 120044148 
-- Arquivo: scheme.sql (versão revisada)
-- =====================================

-- =========================
-- EMPRESA
-- =========================
CREATE TABLE IF NOT EXISTS empresa_locadora (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    cnpj VARCHAR(20) NOT NULL UNIQUE
);

-- =========================
-- CLIENTE
-- =========================
CREATE TABLE IF NOT EXISTS cliente (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    tipo VARCHAR(2) NOT NULL CHECK (tipo IN ('PF','PJ')),
    cidade VARCHAR(50) NOT NULL
);

-- =========================
-- CONDUTOR
-- =========================
CREATE TABLE IF NOT EXISTS condutor (
    id SERIAL PRIMARY KEY,
    cliente_id INT NOT NULL,
    nome VARCHAR(100) NOT NULL,
    cnh VARCHAR(20) NOT NULL UNIQUE,
    validade DATE NOT NULL,
    categoria VARCHAR(5) NOT NULL,
    telefone VARCHAR(20),
    FOREIGN KEY (cliente_id) REFERENCES cliente(id) ON DELETE RESTRICT
);

-- =========================
-- GRUPO VEÍCULO
-- =========================
CREATE TABLE IF NOT EXISTS grupo_veiculo (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    categoria VARCHAR(50) NOT NULL
);

-- =========================
-- VEÍCULO
-- =========================
CREATE TABLE IF NOT EXISTS veiculo (
    id SERIAL PRIMARY KEY,
    placa VARCHAR(10) NOT NULL UNIQUE,
    chassi VARCHAR(30) NOT NULL UNIQUE,
    modelo VARCHAR(50) NOT NULL,
    marca VARCHAR(50) NOT NULL,
    cor VARCHAR(30) NOT NULL,
    tipo_mecanizacao VARCHAR(20) NOT NULL CHECK (tipo_mecanizacao IN ('manual','automatico')),
    ar_condicionado BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL DEFAULT 'disponivel' CHECK (status IN ('disponivel','alugado','manutencao')),
    adaptado_cadeirante BOOLEAN NOT NULL DEFAULT FALSE,
    grupo_id INT NOT NULL,
    empresa_id INT NOT NULL,
    FOREIGN KEY (grupo_id) REFERENCES grupo_veiculo(id) ON DELETE RESTRICT,
    FOREIGN KEY (empresa_id) REFERENCES empresa_locadora(id) ON DELETE RESTRICT
);

-- =========================
-- ACESSÓRIO
-- =========================
CREATE TABLE IF NOT EXISTS acessorio (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL UNIQUE
);

-- =========================
-- VEÍCULO_ACESSÓRIO
-- =========================
CREATE TABLE IF NOT EXISTS veiculo_acessorio (
    veiculo_id INT NOT NULL,
    acessorio_id INT NOT NULL,
    PRIMARY KEY (veiculo_id, acessorio_id),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE CASCADE,
    FOREIGN KEY (acessorio_id) REFERENCES acessorio(id) ON DELETE CASCADE
);

-- =========================
-- PÁTIO
-- =========================
CREATE TABLE IF NOT EXISTS patio (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    cidade VARCHAR(50) NOT NULL
);

-- =========================
-- VAGA
-- =========================
CREATE TABLE IF NOT EXISTS vaga (
    codigo VARCHAR(10) NOT NULL,
    patio_id INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'livre' CHECK (status IN ('livre','ocupada')),
    PRIMARY KEY (codigo, patio_id),
    FOREIGN KEY (patio_id) REFERENCES patio(id) ON DELETE CASCADE
);

-- =========================
-- RESERVA (com pátio de retirada e devolução)
-- =========================
CREATE TABLE IF NOT EXISTS reserva (
    id SERIAL PRIMARY KEY,
    cliente_id INT NOT NULL,
    grupo_id INT NOT NULL,
    patio_retirada_id INT NOT NULL,
    patio_devolucao_id INT NOT NULL,
    data_inicio DATE NOT NULL,
    data_fim DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ativa' CHECK (status IN ('ativa','confirmada','cancelada','espera')),
    FOREIGN KEY (cliente_id) REFERENCES cliente(id) ON DELETE RESTRICT,
    FOREIGN KEY (grupo_id) REFERENCES grupo_veiculo(id) ON DELETE RESTRICT,
    FOREIGN KEY (patio_retirada_id) REFERENCES patio(id) ON DELETE RESTRICT,
    FOREIGN KEY (patio_devolucao_id) REFERENCES patio(id) ON DELETE RESTRICT,
    CHECK (data_fim >= data_inicio)
);

-- =========================
-- LOCAÇÃO (VERSÃO REFORÇADA)
-- =========================
CREATE TABLE IF NOT EXISTS locacao (
    id SERIAL PRIMARY KEY,

    -- reserva_id pode ser NULL (walk-in); quando presente, 1:1 com locacao
    reserva_id INT UNIQUE,

    veiculo_id INT NOT NULL,
    condutor_id INT NOT NULL,

    patio_retirada_id INT NOT NULL,
    patio_devolucao_id INT NOT NULL,

    -- DATAS PREVISTAS (obrigatórias) vs REALIZADAS (podem ser NULL até ocorrer)
    data_retirada_prevista TIMESTAMP NOT NULL,
    data_retirada_realizada TIMESTAMP,
    data_devolucao_prevista TIMESTAMP NOT NULL,
    data_devolucao_realizada TIMESTAMP,

    -- ESTADO DO VEÍCULO (texto descritivo no momento da entrega/devolução)
    estado_entrega TEXT,
    estado_devolucao TEXT,

    -- KM (podem ser NULL até a realização; constraints adicionais abaixo)
    km_entrega INT,
    km_devolucao INT,

    -- auditoria básica
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP,

    FOREIGN KEY (reserva_id) REFERENCES reserva(id) ON DELETE SET NULL,
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE RESTRICT,
    FOREIGN KEY (condutor_id) REFERENCES condutor(id) ON DELETE RESTRICT,
    FOREIGN KEY (patio_retirada_id) REFERENCES patio(id) ON DELETE RESTRICT,
    FOREIGN KEY (patio_devolucao_id) REFERENCES patio(id) ON DELETE RESTRICT,

    -- Regras de integridade temporal
    CHECK (
        -- se a devolução realizada existe, então a retirada realizada deve existir e ser anterior/igual
        data_devolucao_realizada IS NULL
        OR (data_retirada_realizada IS NOT NULL AND data_devolucao_realizada >= data_retirada_realizada)
    ),

    CHECK (
        -- se a retirada realizada existe, então a km_entrega deve existir e ser >= 0
        data_retirada_realizada IS NULL
        OR (km_entrega IS NOT NULL AND km_entrega >= 0)
    ),

    CHECK (
        -- se a devolução realizada existe, então km_devolucao deve existir e ser >= km_entrega (quando km_entrega disponível)
        data_devolucao_realizada IS NULL
        OR (km_devolucao IS NOT NULL AND km_devolucao >= 0)
    ),

    CHECK (
        -- previsões coerentes: devolução prevista >= retirada prevista
        data_devolucao_prevista >= data_retirada_prevista
    )
);

-- =========================
-- COBRANÇA
-- =========================
CREATE TABLE IF NOT EXISTS cobranca (
    id SERIAL PRIMARY KEY,
    locacao_id INT UNIQUE,
    valor DECIMAL(10,2) NOT NULL CHECK (valor >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','pago','cancelado')),
    data_pagamento DATE,
    FOREIGN KEY (locacao_id) REFERENCES locacao(id) ON DELETE SET NULL
);

-- =========================
-- SEGURO
-- =========================
CREATE TABLE IF NOT EXISTS seguro (
    id SERIAL PRIMARY KEY,
    tipo VARCHAR(50) NOT NULL,
    valor DECIMAL(10,2) NOT NULL CHECK (valor >= 0)
);

-- =========================
-- LOCAÇÃO_SEGURO
-- =========================
CREATE TABLE IF NOT EXISTS locacao_seguro (
    locacao_id INT NOT NULL,
    seguro_id INT NOT NULL,
    PRIMARY KEY (locacao_id, seguro_id),
    FOREIGN KEY (locacao_id) REFERENCES locacao(id) ON DELETE CASCADE,
    FOREIGN KEY (seguro_id) REFERENCES seguro(id) ON DELETE RESTRICT
);

-- =========================
-- FOTO
-- =========================
CREATE TABLE IF NOT EXISTS foto (
    id SERIAL PRIMARY KEY,
    veiculo_id INT NOT NULL,
    url TEXT NOT NULL,
    tipo VARCHAR(50),
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE CASCADE
);

-- =========================
-- MANUTENÇÃO
-- =========================
CREATE TABLE IF NOT EXISTS manutencao (
    id SERIAL PRIMARY KEY,
    veiculo_id INT NOT NULL,
    data DATE NOT NULL,
    descricao TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE CASCADE
);

-- =========================
-- TABELA ADICIONAL RECOMENDADA (MOVIMENTAÇÃO ENTRE PÁTIOS)
-- =========================
-- (útil para gerar a matriz de transição para a cadeia de Markov)
CREATE TABLE IF NOT EXISTS movimentacao_patio (
    id SERIAL PRIMARY KEY,
    veiculo_id INT NOT NULL,
    origem_patio_id INT NOT NULL,
    destino_patio_id INT NOT NULL,
    data_movimentacao TIMESTAMP NOT NULL DEFAULT now(),
    motivo VARCHAR(100),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE RESTRICT,
    FOREIGN KEY (origem_patio_id) REFERENCES patio(id) ON DELETE RESTRICT,
    FOREIGN KEY (destino_patio_id) REFERENCES patio(id) ON DELETE RESTRICT,
    CHECK (origem_patio_id <> destino_patio_id)
);

-- =========================
-- ÍNDICES SUGERIDOS (aplicar conforme necessidade)
-- =========================
CREATE INDEX IF NOT EXISTS idx_veiculo_grupo ON veiculo(grupo_id);
CREATE INDEX IF NOT EXISTS idx_veiculo_empresa ON veiculo(empresa_id);
CREATE INDEX IF NOT EXISTS idx_reserva_periodo ON reserva(grupo_id, data_inicio, data_fim);
CREATE INDEX IF NOT EXISTS idx_reserva_patio_retirada ON reserva(patio_retirada_id, data_inicio);
CREATE INDEX IF NOT EXISTS idx_locacao_devolucao ON locacao(patio_devolucao_id, data_devolucao_realizada);
CREATE INDEX IF NOT EXISTS idx_locacao_veiculo_retirada ON locacao(veiculo_id, data_retirada_realizada);

-- =========================
-- OBSERVAÇÕES IMPORTANTES
-- =========================
-- 1) Mantive reserva_id em locacao como UNIQUE mas NULLABLE (walk-in). Se preferir que toda locacao
--    seja derivada de reserva, torne reserva_id NOT NULL e remova a possibilidade de NULL.
-- 2) As CHECKs garantem coerência básica entre datas e KM; regras de negócio adicionais
--    (ex.: tolerâncias, políticas de cobrança) devem ser implementadas na camada de aplicação ou triggers.
-- 3) Ajuste ON DELETE/ON UPDATE conforme política da sua empresa (aqui usei RESTRICT/SET NULL/CASCADE de forma conservadora).
-- 4) Para produção, considere BIGSERIAL ou UUID para PKs e criptografia/mascaramento para dados sensíveis (CNH).
