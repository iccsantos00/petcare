-- =====================================================================
-- DEMO CONTROLE DE ACESSO - para a apresentação
-- Abra uma conexão para cada usuário (no Workbench, uma aba por conexão).
-- Os comandos marcados com "NEGADO" devem dar ERROR 1142/1143 (sem permissão).
-- =====================================================================

-- Garante acentuação correta (ã, é, ç) independente do cliente usado.
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 1) Conectado como petcare_app_atendimento (recepção)
-- ---------------------------------------------------------------------
SELECT CURRENT_USER(), CURRENT_ROLE();
-- petcare_app_atendimento@%  |  `petcare_atendimento_role`@`%`

USE petcare;

SELECT data_hora, pet, tutor, veterinario, status
FROM vw_agenda_consultas;                         -- OK: vê a agenda

SELECT * FROM prontuarios;                        -- NEGADO: dado clínico
SELECT * FROM vw_historico_clinico;               -- NEGADO: dado clínico
DELETE FROM pets WHERE nome = 'Thor';             -- NEGADO: ninguém da recepção apaga
DROP TABLE pets;                                  -- NEGADO: estrutura não muda pela aplicação

-- ---------------------------------------------------------------------
-- 2) Conectado como petcare_app_vet (usuário que a API usa)
-- ---------------------------------------------------------------------
SELECT CURRENT_USER(), CURRENT_ROLE();

USE petcare;

SELECT * FROM vw_historico_clinico LIMIT 5;       -- OK: veterinário vê histórico
SELECT nome, email FROM usuarios;                 -- OK: colunas liberadas
SELECT nome, senha_hash FROM usuarios;            -- NEGADO: permissão por coluna
DELETE FROM consultas;                            -- NEGADO: histórico é preservado

-- ---------------------------------------------------------------------
-- 3) Conectado como administrador do MySQL (só para MOSTRAR a configuração)
-- ---------------------------------------------------------------------
SELECT u.User AS usuario, u.Host AS host, d.DEFAULT_ROLE_USER AS role_padrao
FROM mysql.user u
LEFT JOIN mysql.default_roles d ON d.USER = u.User AND d.HOST = u.Host
WHERE u.User LIKE 'petcare%';

SHOW GRANTS FOR 'petcare_app_vet'@'%' USING 'petcare_vet_role';
SHOW GRANTS FOR 'petcare_app_atendimento'@'%' USING 'petcare_atendimento_role';

-- Evidência pela aplicação: GET http://localhost:8080/api/info
-- devolve o usuário com que a API está conectada (petcare_app_vet, não root).
