-- =====================================================================
-- DEMO TCL (COMMIT / ROLLBACK) - para a apresentação
-- Conecte como petcare_app_vet (NÃO como root) e rode um bloco por vez.
-- No Workbench: selecione o bloco e Ctrl+Shift+Enter.
-- =====================================================================

-- Garante acentuação correta (ã, é, ç) independente do cliente usado.
SET NAMES utf8mb4;

USE petcare;

-- ---------------------------------------------------------------------
-- CENÁRIO 1 - ROLLBACK manual: desfazendo um erro de digitação
-- ---------------------------------------------------------------------
SELECT nome, peso_kg FROM pets WHERE nome = 'Thor';      -- 32.50

START TRANSACTION;
UPDATE pets SET peso_kg = 325.00 WHERE nome = 'Thor';    -- digitou errado
SELECT nome, peso_kg FROM pets WHERE nome = 'Thor';      -- 325.00 (só nesta sessão)
ROLLBACK;

SELECT nome, peso_kg FROM pets WHERE nome = 'Thor';      -- voltou para 32.50

-- ---------------------------------------------------------------------
-- CENÁRIO 2 - COMMIT: confirmando a alteração
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE pets SET peso_kg = 33.10 WHERE nome = 'Thor';
COMMIT;

SELECT nome, peso_kg FROM pets WHERE nome = 'Thor';      -- 33.10 gravado de vez

-- ---------------------------------------------------------------------
-- CENÁRIO 3 - ROLLBACK automático dentro da procedure
-- sp_finalizar_atendimento faz 2 operações: UPDATE da consulta + INSERT do
-- prontuário. Sem diagnóstico, ela falha DEPOIS do UPDATE -> ROLLBACK.
-- ---------------------------------------------------------------------
SELECT id_consulta INTO @consulta
FROM consultas WHERE status = 'EM_ATENDIMENTO' LIMIT 1;

SELECT id_consulta, pet, status FROM vw_agenda_consultas WHERE id_consulta = @consulta;
-- status = EM_ATENDIMENTO

CALL sp_finalizar_atendimento(@consulta, 'Mancando há 2 dias', '', 'Repouso', NULL);
-- ERRO: Diagnóstico é obrigatório para finalizar o atendimento.

SELECT id_consulta, pet, status FROM vw_agenda_consultas WHERE id_consulta = @consulta;
-- continua EM_ATENDIMENTO: o UPDATE foi desfeito (atomicidade)

SELECT COUNT(*) AS prontuarios FROM prontuarios WHERE id_consulta = @consulta;
-- 0

-- ---------------------------------------------------------------------
-- CENÁRIO 4 - COMMIT dentro da procedure (caminho feliz)
-- ---------------------------------------------------------------------
CALL sp_finalizar_atendimento(@consulta, 'Mancando há 2 dias',
     'Entorse leve no membro posterior esquerdo', 'Repouso e anti-inflamatório por 5 dias', NULL);

SELECT id_consulta, pet, status FROM vw_agenda_consultas WHERE id_consulta = @consulta;
-- CONCLUIDA

SELECT diagnostico FROM prontuarios WHERE id_consulta = @consulta;
-- as duas operações foram gravadas juntas

-- ---------------------------------------------------------------------
-- BÔNUS - SAVEPOINT: desfazer só parte da transação
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE pets SET observacoes = 'Medroso no banho' WHERE nome = 'Mel';
SAVEPOINT depois_da_mel;
UPDATE pets SET observacoes = 'TEXTO ERRADO' WHERE nome = 'Luna';
ROLLBACK TO SAVEPOINT depois_da_mel;   -- desfaz só a Luna
COMMIT;

SELECT nome, observacoes FROM pets WHERE nome IN ('Mel', 'Luna');
-- Mel com observação, Luna sem
