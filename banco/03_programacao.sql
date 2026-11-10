-- =====================================================================
-- PETCARE - 03: TRIGGERS, VIEWS E PROCEDURES
-- =====================================================================

-- Garante acentuação correta (ã, é, ç) independente do cliente usado.
SET NAMES utf8mb4;

USE petcare;

DELIMITER $$

-- ---------------------------------------------------------------------
-- TRIGGER 1 - trg_validar_consulta (BEFORE INSERT em consultas)
-- Regra de negócio que vale para QUALQUER cliente do banco (API, Workbench,
-- outro sistema): não agenda no passado, nem com veterinário inativo,
-- nem para pet desativado.
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_validar_consulta
BEFORE INSERT ON consultas
FOR EACH ROW
BEGIN
    IF NEW.data_hora < NOW() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Consulta não pode ser agendada no passado.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM veterinarios
        WHERE id_veterinario = NEW.id_veterinario AND ativo = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Veterinário inexistente ou inativo.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pets
        WHERE id_pet = NEW.id_pet AND ativo = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Pet inexistente ou desativado.';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- TRIGGER 2 - trg_validar_prontuario (BEFORE INSERT em prontuarios)
-- Prontuário só existe para consulta que de fato aconteceu.
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_validar_prontuario
BEFORE INSERT ON prontuarios
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM consultas
        WHERE id_consulta = NEW.id_consulta
          AND status IN ('EM_ATENDIMENTO', 'CONCLUIDA')
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Consulta precisa estar em atendimento ou concluída.';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- TRIGGER 3 - trg_bloquear_consulta_encerrada (BEFORE UPDATE em consultas)
-- Consulta CONCLUIDA, CANCELADA ou FALTOU é registro histórico:
-- não pode mudar de status nem de data (protege auditoria e faturamento).
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_bloquear_consulta_encerrada
BEFORE UPDATE ON consultas
FOR EACH ROW
BEGIN
    IF OLD.status IN ('CONCLUIDA', 'CANCELADA', 'FALTOU')
       AND (NEW.status <> OLD.status OR NEW.data_hora <> OLD.data_hora) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Consulta encerrada não pode ser alterada.';
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- VIEW 1 - vw_agenda_consultas
-- Junta 6 tabelas (consulta, pet, tutor, veterinário e os 2 usuários)
-- num formato pronto para a tela de agenda. Vantagens:
--  * a aplicação faz um SELECT simples em vez de repetir 5 JOINs;
--  * segurança: o perfil ATENDIMENTO vê a agenda (nome do vet, do tutor)
--    sem ter permissão nas tabelas usuarios/veterinarios.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_agenda_consultas AS
SELECT
    c.id_consulta,
    c.data_hora,
    c.status,
    c.motivo,
    p.id_pet,
    p.nome    AS pet,
    p.especie,
    fn_calcular_idade(p.data_nascimento) AS idade_pet,
    ut.nome   AS tutor,
    ut.telefone AS telefone_tutor,
    uv.nome   AS veterinario,
    c.valor
FROM consultas c
JOIN pets p          ON p.id_pet = c.id_pet
JOIN tutores t       ON t.id_tutor = p.id_tutor
JOIN usuarios ut     ON ut.id_usuario = t.id_usuario
JOIN veterinarios v  ON v.id_veterinario = c.id_veterinario
JOIN usuarios uv     ON uv.id_usuario = v.id_usuario;

-- ---------------------------------------------------------------------
-- VIEW 2 - vw_historico_clinico
-- Linha do tempo clínica do pet: consultas + prontuário (LEFT JOIN, porque
-- consulta futura ainda não tem prontuário). Só o perfil VETERINÁRIO tem
-- acesso: é aqui que estão os dados sensíveis.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_historico_clinico AS
SELECT
    p.id_pet,
    p.nome AS pet,
    c.id_consulta,
    c.data_hora,
    c.status,
    c.motivo,
    uv.nome AS veterinario,
    pr.anamnese,
    pr.diagnostico,
    pr.conduta,
    pr.observacoes AS observacoes_clinicas
FROM pets p
JOIN consultas c     ON c.id_pet = p.id_pet
JOIN veterinarios v  ON v.id_veterinario = c.id_veterinario
JOIN usuarios uv     ON uv.id_usuario = v.id_usuario
LEFT JOIN prontuarios pr ON pr.id_consulta = c.id_consulta;

-- ---------------------------------------------------------------------
-- PROCEDURES
-- SQL SECURITY INVOKER: a procedure roda com as permissões de QUEM CHAMA,
-- não do criador. Assim ela não vira um "atalho" para burlar o controle
-- de acesso (o atendente não consegue registrar prontuário via procedure).
-- ---------------------------------------------------------------------

DELIMITER $$

-- PROCEDURE 1 - sp_agendar_consulta
-- Gera o ID, insere a consulta (o trigger 1 valida) e devolve o ID criado.
CREATE PROCEDURE sp_agendar_consulta(
    IN p_id_pet          VARCHAR(40),
    IN p_id_veterinario  VARCHAR(40),
    IN p_data_hora       DATETIME,
    IN p_motivo          VARCHAR(255),
    IN p_valor           DECIMAL(10,2)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_id VARCHAR(40);

    SET v_id = fn_gerar_id('CON');

    INSERT INTO consultas (id_consulta, id_pet, id_veterinario, data_hora, motivo, valor)
    VALUES (v_id, p_id_pet, p_id_veterinario, p_data_hora, p_motivo, p_valor);

    SELECT v_id AS id_consulta;
END$$

-- PROCEDURE 2 - sp_registrar_vacinacao
-- Registra a aplicação. Se a próxima dose não for informada, calcula
-- automaticamente para 1 ano depois (reforço anual padrão).
CREATE PROCEDURE sp_registrar_vacinacao(
    IN p_id_pet          VARCHAR(40),
    IN p_id_vacina       VARCHAR(40),
    IN p_id_veterinario  VARCHAR(40),
    IN p_data            DATE,
    IN p_proxima         DATE,
    IN p_lote            VARCHAR(60),
    IN p_observacoes     TEXT
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_id VARCHAR(40);

    SET v_id = fn_gerar_id('VAC');

    INSERT INTO vacinacoes (id_vacinacao, id_pet, id_vacina, id_veterinario,
                            data_aplicacao, proxima_dose, lote, observacoes)
    VALUES (v_id, p_id_pet, p_id_vacina, p_id_veterinario,
            p_data, COALESCE(p_proxima, DATE_ADD(p_data, INTERVAL 1 YEAR)),
            p_lote, p_observacoes);

    SELECT v_id AS id_vacinacao;
END$$

-- PROCEDURE 3 - sp_finalizar_atendimento  (CONTROLE DE TRANSAÇÃO - TCL)
-- Finalizar um atendimento são DUAS operações que precisam andar juntas:
--   1) mudar a consulta para CONCLUIDA
--   2) gravar o prontuário
-- Se a 2 falhar e a 1 ficar gravada, teríamos consulta "concluída" sem
-- prontuário. Por isso: START TRANSACTION ... COMMIT, e qualquer erro
-- cai no HANDLER, que faz ROLLBACK (desfaz a 1) e repassa o erro (RESIGNAL).
CREATE PROCEDURE sp_finalizar_atendimento(
    IN p_id_consulta  VARCHAR(40),
    IN p_anamnese     TEXT,
    IN p_diagnostico  TEXT,
    IN p_conduta      TEXT,
    IN p_observacoes  TEXT
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_id VARCHAR(40);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

        -- Operação 1
        UPDATE consultas
        SET status = 'CONCLUIDA'
        WHERE id_consulta = p_id_consulta
          AND status IN ('CONFIRMADA', 'EM_ATENDIMENTO');

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Consulta inexistente ou fora de atendimento.';
        END IF;

        -- Regra: não se conclui atendimento sem diagnóstico.
        -- Se cair aqui, o UPDATE acima é desfeito pelo ROLLBACK.
        IF p_diagnostico IS NULL OR TRIM(p_diagnostico) = '' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Diagnóstico é obrigatório para finalizar o atendimento.';
        END IF;

        -- Operação 2
        SET v_id = fn_gerar_id('PRO');

        INSERT INTO prontuarios (id_prontuario, id_consulta, anamnese, diagnostico, conduta, observacoes)
        VALUES (v_id, p_id_consulta, p_anamnese, p_diagnostico, p_conduta, p_observacoes);

    COMMIT;

    SELECT v_id AS id_prontuario;
END$$

DELIMITER ;
