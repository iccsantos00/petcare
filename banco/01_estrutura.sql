-- =====================================================================
-- PETCARE - 01: ESTRUTURA (banco, funções de ID, tabelas e índices)
-- Executar como administrador do MySQL (só na instalação).
-- =====================================================================

-- Garante acentuação correta (ã, é, ç) independente do cliente usado.
SET NAMES utf8mb4;

DROP DATABASE IF EXISTS petcare;

CREATE DATABASE petcare
CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

USE petcare;

-- ---------------------------------------------------------------------
-- FUNÇÕES
-- Criadas antes das tabelas porque são usadas na carga de dados.
-- ---------------------------------------------------------------------

DELIMITER $$

-- Gera IDs no formato PREFIXO-<32 hex aleatórios> (ex.: PET-9F3A1C...).
-- Por que não AUTO_INCREMENT?
--  * AUTO_INCREMENT é previsível: com /pets/10 dá para "chutar" /pets/11 e
--    ver dados de outro tutor. Aqui são 128 bits aleatórios (RANDOM_BYTES
--    usa gerador criptográfico): impossível adivinhar o próximo ID;
--  * o ID existe antes do INSERT (a procedure já sabe o ID que vai devolver)
--    e não colide se os dados forem migrados/juntados com outro banco;
--  * o prefixo mostra a entidade só de olhar o ID (PET, CON, PRO...).
-- Usamos RANDOM_BYTES e não UUID() porque o UUID() do MySQL é versão 1
-- (baseado em relógio + MAC da máquina), ou seja, parcialmente previsível.
-- O prefixo tem no máximo 4 letras: 4 + '-' + 32 = 37 <= VARCHAR(40).
CREATE FUNCTION fn_gerar_id(p_prefixo VARCHAR(4))
RETURNS VARCHAR(40)
NOT DETERMINISTIC
NO SQL
BEGIN
    RETURN CONCAT(UPPER(p_prefixo), '-', HEX(RANDOM_BYTES(16)));
END$$

-- Idade em anos completos a partir de uma data (usada na listagem de pets).
-- NOT DETERMINISTIC porque depende de CURDATE(): o resultado muda com o tempo.
CREATE FUNCTION fn_calcular_idade(p_data DATE)
RETURNS INT
NOT DETERMINISTIC
NO SQL
BEGIN
    IF p_data IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN TIMESTAMPDIFF(YEAR, p_data, CURDATE());
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- TABELAS
-- ON DELETE RESTRICT em quase tudo: histórico clínico não pode sumir
-- em cascata. Para "apagar" usamos a coluna ativo (exclusão lógica).
-- ---------------------------------------------------------------------

CREATE TABLE grupos_usuarios (
    id_grupo   VARCHAR(40) PRIMARY KEY,
    nome       VARCHAR(60) NOT NULL UNIQUE,
    descricao  VARCHAR(255),
    criado_em  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE usuarios (
    id_usuario     VARCHAR(40) PRIMARY KEY,
    id_grupo       VARCHAR(40) NOT NULL,
    nome           VARCHAR(120) NOT NULL,
    email          VARCHAR(160) NOT NULL UNIQUE,
    senha_hash     VARCHAR(255) NOT NULL,
    telefone       VARCHAR(20),
    ativo          BOOLEAN DEFAULT TRUE,
    criado_em      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                   ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (id_grupo) REFERENCES grupos_usuarios(id_grupo)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Tutor e veterinário "são" usuários (relação 1:1 com usuarios).
-- Os dados comuns (nome, e-mail, senha) ficam só em usuarios.
CREATE TABLE tutores (
    id_tutor         VARCHAR(40) PRIMARY KEY,
    id_usuario       VARCHAR(40) NOT NULL UNIQUE,
    cpf              CHAR(11) NOT NULL UNIQUE,
    data_nascimento  DATE,
    logradouro       VARCHAR(140),
    numero           VARCHAR(20),
    complemento      VARCHAR(80),
    bairro           VARCHAR(80),
    cidade           VARCHAR(80),
    uf               CHAR(2),
    cep              CHAR(8),

    FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE veterinarios (
    id_veterinario  VARCHAR(40) PRIMARY KEY,
    id_usuario      VARCHAR(40) NOT NULL UNIQUE,
    crmv            VARCHAR(30) NOT NULL UNIQUE,
    especialidade   VARCHAR(100),
    ativo           BOOLEAN DEFAULT TRUE,

    FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE pets (
    id_pet           VARCHAR(40) PRIMARY KEY,
    id_tutor         VARCHAR(40) NOT NULL,
    nome             VARCHAR(80) NOT NULL,
    especie          VARCHAR(40) NOT NULL,
    raca             VARCHAR(80),
    sexo             ENUM('MACHO','FEMEA','NAO_INFORMADO') DEFAULT 'NAO_INFORMADO',
    data_nascimento  DATE,
    peso_kg          DECIMAL(6,2),
    porte            ENUM('PEQUENO','MEDIO','GRANDE','NAO_INFORMADO') DEFAULT 'NAO_INFORMADO',
    alergias         TEXT,
    observacoes      TEXT,
    ativo            BOOLEAN DEFAULT TRUE,
    criado_em        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (id_tutor) REFERENCES tutores(id_tutor)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CHECK (peso_kg IS NULL OR peso_kg > 0)
) ENGINE=InnoDB;

CREATE TABLE consultas (
    id_consulta     VARCHAR(40) PRIMARY KEY,
    id_pet          VARCHAR(40) NOT NULL,
    id_veterinario  VARCHAR(40) NOT NULL,
    data_hora       DATETIME NOT NULL,
    motivo          VARCHAR(255) NOT NULL,
    status          ENUM('AGENDADA','CONFIRMADA','EM_ATENDIMENTO',
                         'CONCLUIDA','CANCELADA','FALTOU') DEFAULT 'AGENDADA',
    valor           DECIMAL(10,2),
    observacoes     TEXT,
    criado_em       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (id_pet) REFERENCES pets(id_pet)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (id_veterinario) REFERENCES veterinarios(id_veterinario)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CHECK (valor IS NULL OR valor >= 0)
) ENGINE=InnoDB;

-- 1:1 com consultas (id_consulta UNIQUE): cada consulta tem no máximo um prontuário.
CREATE TABLE prontuarios (
    id_prontuario  VARCHAR(40) PRIMARY KEY,
    id_consulta    VARCHAR(40) NOT NULL UNIQUE,
    anamnese       TEXT,
    diagnostico    TEXT,
    conduta        TEXT,
    observacoes    TEXT,
    registrado_em  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (id_consulta) REFERENCES consultas(id_consulta)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Catálogo de vacinas.
CREATE TABLE vacinas (
    id_vacina         VARCHAR(40) PRIMARY KEY,
    nome              VARCHAR(100) NOT NULL,
    fabricante        VARCHAR(100),
    especie_indicada  VARCHAR(40),
    descricao         TEXT,
    ativo             BOOLEAN DEFAULT TRUE
) ENGINE=InnoDB;

-- Aplicações: tabela associativa N:N entre pets e vacinas, com dados próprios.
CREATE TABLE vacinacoes (
    id_vacinacao    VARCHAR(40) PRIMARY KEY,
    id_pet          VARCHAR(40) NOT NULL,
    id_vacina       VARCHAR(40) NOT NULL,
    id_veterinario  VARCHAR(40),
    data_aplicacao  DATE NOT NULL,
    proxima_dose    DATE,
    lote            VARCHAR(60),
    observacoes     TEXT,

    FOREIGN KEY (id_pet) REFERENCES pets(id_pet)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (id_vacina) REFERENCES vacinas(id_vacina)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    -- Se o veterinário for removido, a aplicação continua registrada.
    FOREIGN KEY (id_veterinario) REFERENCES veterinarios(id_veterinario)
        ON UPDATE CASCADE ON DELETE SET NULL,

    CHECK (proxima_dose IS NULL OR proxima_dose >= data_aplicacao)
) ENGINE=InnoDB;

-- Catálogo de medicamentos.
CREATE TABLE medicamentos (
    id_medicamento   VARCHAR(40) PRIMARY KEY,
    nome             VARCHAR(120) NOT NULL,
    principio_ativo  VARCHAR(120),
    apresentacao     VARCHAR(80),
    observacoes      TEXT,
    ativo            BOOLEAN DEFAULT TRUE
) ENGINE=InnoDB;

-- Associativa N:N entre consultas e medicamentos.
CREATE TABLE prescricoes (
    id_prescricao   VARCHAR(40) PRIMARY KEY,
    id_consulta     VARCHAR(40) NOT NULL,
    id_medicamento  VARCHAR(40) NOT NULL,
    dosagem         VARCHAR(100) NOT NULL,
    frequencia      VARCHAR(100) NOT NULL,
    duracao_dias    INT,
    instrucoes      TEXT,

    FOREIGN KEY (id_consulta) REFERENCES consultas(id_consulta)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (id_medicamento) REFERENCES medicamentos(id_medicamento)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CHECK (duracao_dias IS NULL OR duracao_dias > 0)
) ENGINE=InnoDB;

CREATE TABLE exames (
    id_exame          VARCHAR(40) PRIMARY KEY,
    id_consulta       VARCHAR(40) NOT NULL,
    tipo              VARCHAR(100) NOT NULL,
    data_solicitacao  DATE NOT NULL,
    data_resultado    DATE,
    resultado         TEXT,
    arquivo_url       VARCHAR(500),
    status            ENUM('SOLICITADO','EM_ANDAMENTO','CONCLUIDO','CANCELADO')
                      DEFAULT 'SOLICITADO',

    FOREIGN KEY (id_consulta) REFERENCES consultas(id_consulta)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CHECK (data_resultado IS NULL OR data_resultado >= data_solicitacao)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ÍNDICES
-- PK, UNIQUE e FK já ganham índice automático no InnoDB.
-- Os abaixo são compostos e seguem as consultas reais da aplicação:
-- a coluna do filtro de igualdade vem primeiro, a de ordenação/intervalo depois.
-- ---------------------------------------------------------------------

-- Tela "pets do tutor": WHERE id_tutor = ? AND ativo = TRUE.
CREATE INDEX idx_pets_tutor_ativo ON pets(id_tutor, ativo);

-- Agenda do dia/semana: WHERE data_hora BETWEEN ... (e filtro por status).
CREATE INDEX idx_consultas_data_status ON consultas(data_hora, status);

-- Agenda de um veterinário: WHERE id_veterinario = ? ORDER BY data_hora.
CREATE INDEX idx_consultas_vet_data ON consultas(id_veterinario, data_hora);

-- Histórico de um pet: WHERE id_pet = ? ORDER BY data_hora DESC.
CREATE INDEX idx_consultas_pet_data ON consultas(id_pet, data_hora);

-- Carteira de vacinação do pet: WHERE id_pet = ? ORDER BY data_aplicacao.
CREATE INDEX idx_vacinacoes_pet_data ON vacinacoes(id_pet, data_aplicacao);

-- Lembrete de vacinas que vencem: WHERE proxima_dose BETWEEN hoje AND +30 dias.
CREATE INDEX idx_vacinacoes_proxima_dose ON vacinacoes(proxima_dose);

-- Fila de exames pendentes: WHERE status = 'SOLICITADO' ORDER BY data_solicitacao.
CREATE INDEX idx_exames_status_data ON exames(status, data_solicitacao);

-- Listagem de usuários por grupo (tela de administração).
CREATE INDEX idx_usuarios_grupo_ativo ON usuarios(id_grupo, ativo);
