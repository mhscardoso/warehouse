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


CREATE TABLE Endereco (
    IDEndereco  INT NOT NULL,
    CEP         VARCHAR(8) NOT NULL,
    UF          CHAR(2) NOT NULL,
    Cidade      VARCHAR(100) NOT NULL,
    Bairro      VARCHAR(100) NOT NULL,
    Logradouro  VARCHAR(255) NOT NULL,
    Numero      VARCHAR(10) NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Endereco PRIMARY KEY (IDEndereco),

    -- Validações
    CONSTRAINT CHK_CEP CHECK (LENGTH(CEP) = 8),
    CONSTRAINT CHK_UF CHECK (
        UF IN ('AC','AL','AP','AM','BA','CE','DF','ES','GO',
               'MA','MT','MS','MG','PA','PB','PR','PE','PI',
               'RJ','RN','RS','RO','RR','SC','SP','SE','TO')
    )
);


CREATE TABLE Parceira (
    IDParceira INT NOT NULL,
    CNPJ       VARCHAR(14) NOT NULL,
    Nome       VARCHAR(255) NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Parceira PRIMARY KEY (IDParceira),

    -- CNPJ único
    CONSTRAINT UQ_Parceira_CNPJ UNIQUE (CNPJ)
);

CREATE TABLE Patio (
    IDPatio           INT NOT NULL,
    CDPatio           VARCHAR(50) NOT NULL,
    Lotacao           INT NOT NULL,
    HorarioAbertura   TIME NOT NULL,
    HorarioFechamento TIME NOT NULL,
    IDEndereco        INT NOT NULL,
    IDParceira        INT NOT NULL,

    CONSTRAINT PK_Patio PRIMARY KEY (IDPatio),

    -- Restrições de integridade
    CONSTRAINT UQ_CodigoPatio UNIQUE (CDPatio),
    CONSTRAINT CHK_Lotacao CHECK (Lotacao > 0),

    -- Chaves estrangeiras
    CONSTRAINT FK_Patio_Endereco FOREIGN KEY (IDEndereco)
        REFERENCES Endereco(IDEndereco),

    CONSTRAINT FK_Patio_Parceira FOREIGN KEY (IDParceira)
        REFERENCES Parceira(IDParceira),

    CONSTRAINT CHK_Horario CHECK (HorarioFechamento > HorarioAbertura)
);



CREATE TABLE Vaga (
    IDVaga   INT NOT NULL,
    CodVaga  VARCHAR(50) NOT NULL,
    Coberta  BOOLEAN NOT NULL,
    Andar    INT,
    IDPatio  INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Vaga PRIMARY KEY (IDVaga),

    -- Código único da vaga
    CONSTRAINT UQ_Vaga_Cod UNIQUE (CodVaga),

    -- evitar andar negativo
    CONSTRAINT CHK_Andar CHECK (Andar IS NULL OR Andar >= 0),

    -- Chave estrangeira
    CONSTRAINT FK_Vaga_Patio FOREIGN KEY (IDPatio)
        REFERENCES Patio(IDPatio)
);



CREATE TABLE Categoria (
    IDCategoria       INT NOT NULL,
    Classificacao     VARCHAR(50) NOT NULL,
    ClasseLuxo        CHAR(1) NOT NULL,
    ValorDiariaBase   DECIMAL(10,2) NOT NULL,
    Tracao4x4         BOOLEAN NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Categoria PRIMARY KEY (IDCategoria),

    -- Garantir valores válidos (opcional, mas recomendado)
    CONSTRAINT CHK_ClasseLuxo CHECK (ClasseLuxo IN ('A', 'B', 'C')),
    CONSTRAINT CHK_ValorDiaria CHECK (ValorDiariaBase >= 0)
);



CREATE TABLE Veiculo (
    IDVeiculo           INT NOT NULL,
    Placa               VARCHAR(10) NOT NULL,
    Chassi              VARCHAR(30) NOT NULL,
    Modelo              VARCHAR(100) NOT NULL,
    Ano                 INT NOT NULL,
    Altura              DECIMAL(5,2) NOT NULL,
    Largura             DECIMAL(5,2) NOT NULL,
    Portas              INT NOT NULL,
    UltimaKilometragem  INT NOT NULL,
    ArCondicionado      BOOLEAN NOT NULL,
    CadeiraInfantil     BOOLEAN NOT NULL,
    BebeConforto        BOOLEAN NOT NULL,
    ValorDiaria         DECIMAL(10,2) NOT NULL,
    IDCategoria         INT NOT NULL,

    -- Chave primária (apenas uma!)
    CONSTRAINT PK_Veiculo PRIMARY KEY (IDVeiculo),

    -- Identificadores únicos
    CONSTRAINT UQ_Veiculo_Placa UNIQUE (Placa),
    CONSTRAINT UQ_Veiculo_Chassi UNIQUE (Chassi),

    -- Validações (boas práticas)
    CONSTRAINT CHK_Ano CHECK (Ano >= 1900),
    CONSTRAINT CHK_Portas CHECK (Portas > 0),
    CONSTRAINT CHK_KM CHECK (UltimaKilometragem >= 0),
    CONSTRAINT CHK_ValorDiaria CHECK (ValorDiaria >= 0),
    CONSTRAINT CHK_Dimensoes CHECK (Altura > 0 AND Largura > 0),

    -- Chave estrangeira
    CONSTRAINT FK_Veiculo_Categoria FOREIGN KEY (IDCategoria)
        REFERENCES Categoria(IDCategoria)
);



CREATE TABLE PessoaFisica (
    IDFisica      INT NOT NULL,
    CPF           VARCHAR(11) NOT NULL,
    Nome          VARCHAR(255) NOT NULL,
    DtNascimento  DATE NOT NULL,
    RG            VARCHAR(20) NOT NULL,
    Telefone      VARCHAR(20) NOT NULL,
    IDEndereco    INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_PessoaFisica PRIMARY KEY (IDFisica),

    -- CPF único
    CONSTRAINT UQ_PessoaFisica_CPF UNIQUE (CPF),

    -- Validações básicas
    CONSTRAINT CHK_CPF_Tamanho CHECK (LENGTH(CPF) = 11),
    CONSTRAINT CHK_DataNascimento CHECK (DtNascimento < CURRENT_DATE),

    -- Chave estrangeira
    CONSTRAINT FK_PessoaFisica_Endereco FOREIGN KEY (IDEndereco)
        REFERENCES Endereco(IDEndereco)
);


CREATE TABLE Empresa (
    IDEmpresa    INT NOT NULL,
    CNPJ         VARCHAR(14) NOT NULL,
    RazaoSocial  VARCHAR(255) NOT NULL,
    DtAbertura   DATE NOT NULL,
    Telefone     VARCHAR(20) NOT NULL,
    IDEndereco   INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Empresa PRIMARY KEY (IDEmpresa),

    -- CNPJ único
    CONSTRAINT UQ_Empresa_CNPJ UNIQUE (CNPJ),

    -- Validações básicas
    CONSTRAINT CHK_CNPJ_Tamanho CHECK (LENGTH(CNPJ) = 14),

    -- Chave estrangeira
    CONSTRAINT FK_Empresa_Endereco FOREIGN KEY (IDEndereco)
        REFERENCES Endereco(IDEndereco)
);



CREATE TABLE Motorista (
    IDMotorista   INT NOT NULL,
    CNH           VARCHAR(20) NOT NULL,
    CategoriaCNH  VARCHAR(5) NOT NULL,
    IDFisica      INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Motorista PRIMARY KEY (IDMotorista),

    -- CNH única
    CONSTRAINT UQ_Motorista_CNH UNIQUE (CNH),

    -- Cada motorista vinculado a uma única pessoa física (1:1)
    CONSTRAINT UQ_Motorista_Fisica UNIQUE (IDFisica),

    -- Validações
    CONSTRAINT CHK_CategoriaCNH CHECK (
        CategoriaCNH IN ('A', 'B', 'C', 'D', 'E', 'AB', 'AC', 'AD', 'AE')
    ),

    -- Chave estrangeira
    CONSTRAINT FK_Motorista_PessoaFisica FOREIGN KEY (IDFisica)
        REFERENCES PessoaFisica(IDFisica)
);



CREATE TABLE CentroCusto (
    IDCentroCusto INT NOT NULL,
    IDEmpresa     INT,
    IDFisica      INT,
    IDResponsavel INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_CentroCusto PRIMARY KEY (IDCentroCusto),

    -- Garantir que seja OU empresa OU pessoa física (não ambos, não nenhum)
    CONSTRAINT CHK_CentroCusto_Tipo CHECK (
        (IDEmpresa IS NOT NULL AND IDFisica IS NULL) OR
        (IDEmpresa IS NULL AND IDFisica IS NOT NULL)
    ),

    -- Chaves estrangeiras
    CONSTRAINT FK_CC_Empresa FOREIGN KEY (IDEmpresa)
        REFERENCES Empresa(IDEmpresa),

    CONSTRAINT FK_CC_Fisica FOREIGN KEY (IDFisica)
        REFERENCES PessoaFisica(IDFisica),

    CONSTRAINT FK_CC_Responsavel FOREIGN KEY (IDResponsavel)
        REFERENCES PessoaFisica(IDFisica)
);


CREATE TABLE Movimentacao (
    IDMovimentacao INT NOT NULL,
    DtChegada      TIMESTAMP NOT NULL,
    DtRetirada     TIMESTAMP NOT NULL,
    IDVeiculo      INT NOT NULL,
    IDVagaOrigem   INT NOT NULL,
    IDVagaDestino  INT,

    -- Chave primária
    CONSTRAINT PK_Movimentacao PRIMARY KEY (IDMovimentacao),

    -- Regra de integridade temporal
    CONSTRAINT CHK_Movimentacao_Datas 
        CHECK (DtChegada >= DtRetirada),

    -- Chaves estrangeiras
    CONSTRAINT FK_Mov_Veiculo FOREIGN KEY (IDVeiculo)
        REFERENCES Veiculo(IDVeiculo),

    CONSTRAINT FK_Mov_VagaOrigem FOREIGN KEY (IDVagaOrigem)
        REFERENCES Vaga(IDVaga),

    CONSTRAINT FK_Mov_VagaDestino FOREIGN KEY (IDVagaDestino)
        REFERENCES Vaga(IDVaga)
);


CREATE TABLE Reserva (
    IDReserva             INT NOT NULL,
    QtVeiculosSolicitados INT NOT NULL,
    DtReserva             TIMESTAMP NOT NULL,
    DtRetiradaPrevista    TIMESTAMP NOT NULL,
    DtLimiteRetirada      TIMESTAMP NOT NULL,
    Status                VARCHAR(20) NOT NULL,
    IDCentroCusto         INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Reserva PRIMARY KEY (IDReserva),

    -- Regras de integridade
    CONSTRAINT CHK_QtdVeiculos CHECK (QtVeiculosSolicitados >= 1),
    CONSTRAINT CHK_DatasReserva CHECK (
        DtLimiteRetirada > DtRetiradaPrevista
    ),

    -- Status controlado
    CONSTRAINT CHK_Status CHECK (
        Status IN ('Confirmada', 'Cancelada', 'Atendida')
    ),

    -- Chave estrangeira
    CONSTRAINT FK_Reserva_CentroCusto FOREIGN KEY (IDCentroCusto)
        REFERENCES CentroCusto(IDCentroCusto)
);




CREATE TABLE Locacao (
    IDLocacao        INT NOT NULL,
    ValorDiaria      DECIMAL(10,2) NOT NULL,
    DtRetirada       TIMESTAMP NOT NULL,
    DtChegada        TIMESTAMP,
    IDVagaRetirada   INT NOT NULL,
    IDVagaDevolvida  INT,
    IDVeiculo        INT NOT NULL,
    IDReserva        INT NOT NULL,
    IDMotorista      INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Locacao PRIMARY KEY (IDLocacao),

    -- Regras de integridade
    CONSTRAINT CHK_ValorDiaria CHECK (ValorDiaria > 0),
    CONSTRAINT CHK_Datas CHECK (DtChegada IS NULL OR DtChegada >= DtRetirada),

    -- Chaves estrangeiras
    CONSTRAINT FK_Locacao_VagaRetirada FOREIGN KEY (IDVagaRetirada)
        REFERENCES Vaga(IDVaga),

    CONSTRAINT FK_Locacao_VagaDevolvida FOREIGN KEY (IDVagaDevolvida)
        REFERENCES Vaga(IDVaga),

    CONSTRAINT FK_Locacao_Veiculo FOREIGN KEY (IDVeiculo)
        REFERENCES Veiculo(IDVeiculo),

    CONSTRAINT FK_Locacao_Reserva FOREIGN KEY (IDReserva)
        REFERENCES Reserva(IDReserva),

    CONSTRAINT FK_Locacao_Motorista FOREIGN KEY (IDMotorista)
        REFERENCES Motorista(IDMotorista)
);


CREATE TABLE Prontuario (
    IDProntuario INT NOT NULL,
    Operacao     VARCHAR(255) NOT NULL,
    Custo        DECIMAL(10,2) NOT NULL,
    IDEndereco   INT NOT NULL,
    IDVeiculo    INT NOT NULL,

    -- Chave primária
    CONSTRAINT PK_Prontuario PRIMARY KEY (IDProntuario),

    -- Validações
    CONSTRAINT CHK_Custo CHECK (Custo >= 0),

    -- Chaves estrangeiras
    CONSTRAINT FK_Prontuario_Endereco FOREIGN KEY (IDEndereco)
        REFERENCES Endereco(IDEndereco),

    CONSTRAINT FK_Prontuario_Veiculo FOREIGN KEY (IDVeiculo)
        REFERENCES Veiculo(IDVeiculo)
);

CREATE TABLE Avaria (
    IDAvaria                 INT NOT NULL,
    DtRegistro               TIMESTAMP NOT NULL,
    Descricao                VARCHAR(500) NOT NULL,
    IDLocacao                INT NOT NULL,
    IDVeiculo                INT NOT NULL,
    IDProntuarioRelacionado  INT,

    -- Chave primária
    CONSTRAINT PK_Avaria PRIMARY KEY (IDAvaria),

    -- Validação básica de data
    CONSTRAINT CHK_Avaria_Data CHECK (DtRegistro <= CURRENT_TIMESTAMP),

    -- Chaves estrangeiras
    CONSTRAINT FK_Avaria_Locacao FOREIGN KEY (IDLocacao)
        REFERENCES Locacao(IDLocacao),

    CONSTRAINT FK_Avaria_Veiculo FOREIGN KEY (IDVeiculo)
        REFERENCES Veiculo(IDVeiculo),

    CONSTRAINT FK_Avaria_Prontuario FOREIGN KEY (IDProntuarioRelacionado)
        REFERENCES Prontuario(IDProntuario)
);
