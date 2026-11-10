-- =====================================================================
-- PETCARE - 04: CONTROLE DE ACESSO (roles e usuários)
-- Princípio do menor privilégio: cada perfil recebe só o que precisa.
-- Nenhum perfil tem DROP, ALTER, CREATE ou GRANT OPTION: estrutura do
-- banco só muda por script de instalação, executado pelo DBA.
-- A aplicação NUNCA usa root.
-- =====================================================================

-- Garante acentuação correta (ã, é, ç) independente do cliente usado.
SET NAMES utf8mb4;

USE petcare;

DROP USER IF EXISTS 'petcare_app_admin'@'%', 'petcare_app_vet'@'%', 'petcare_app_atendimento'@'%';
DROP ROLE IF EXISTS 'petcare_admin_role', 'petcare_vet_role', 'petcare_atendimento_role';

CREATE ROLE 'petcare_admin_role', 'petcare_vet_role', 'petcare_atendimento_role';

-- ---------------------------------------------------------------------
-- ADMINISTRADOR: manipula todos os dados (inclusive DELETE), mas não a estrutura.
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, SHOW VIEW
ON petcare.* TO 'petcare_admin_role';

-- ---------------------------------------------------------------------
-- VETERINÁRIO: dados clínicos completos; sem DELETE (histórico é preservado).
-- ---------------------------------------------------------------------
-- Permissão por COLUNA: vê nome e contato dos usuários, mas NÃO a senha_hash.
GRANT SELECT (id_usuario, id_grupo, nome, email, telefone, ativo)
ON petcare.usuarios TO 'petcare_vet_role';

GRANT SELECT ON petcare.tutores       TO 'petcare_vet_role';
GRANT SELECT ON petcare.veterinarios  TO 'petcare_vet_role';
GRANT SELECT ON petcare.vacinas       TO 'petcare_vet_role';
GRANT SELECT ON petcare.medicamentos  TO 'petcare_vet_role';

GRANT SELECT, INSERT, UPDATE ON petcare.pets        TO 'petcare_vet_role';
GRANT SELECT, INSERT, UPDATE ON petcare.consultas   TO 'petcare_vet_role';
GRANT SELECT, INSERT, UPDATE ON petcare.prontuarios TO 'petcare_vet_role';
GRANT SELECT, INSERT, UPDATE ON petcare.vacinacoes  TO 'petcare_vet_role';
GRANT SELECT, INSERT, UPDATE ON petcare.prescricoes TO 'petcare_vet_role';
GRANT SELECT, INSERT, UPDATE ON petcare.exames      TO 'petcare_vet_role';

GRANT SELECT ON petcare.vw_agenda_consultas  TO 'petcare_vet_role';
GRANT SELECT ON petcare.vw_historico_clinico TO 'petcare_vet_role';

GRANT EXECUTE ON PROCEDURE petcare.sp_agendar_consulta      TO 'petcare_vet_role';
GRANT EXECUTE ON PROCEDURE petcare.sp_registrar_vacinacao   TO 'petcare_vet_role';
GRANT EXECUTE ON PROCEDURE petcare.sp_finalizar_atendimento TO 'petcare_vet_role';
GRANT EXECUTE ON FUNCTION  petcare.fn_gerar_id              TO 'petcare_vet_role';
GRANT EXECUTE ON FUNCTION  petcare.fn_calcular_idade        TO 'petcare_vet_role';

-- ---------------------------------------------------------------------
-- ATENDIMENTO (recepção): cadastro e agenda. SEM acesso a prontuários,
-- prescrições, exames e ao histórico clínico.
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON petcare.usuarios TO 'petcare_atendimento_role';
GRANT SELECT, INSERT, UPDATE ON petcare.tutores  TO 'petcare_atendimento_role';
GRANT SELECT, INSERT, UPDATE ON petcare.pets     TO 'petcare_atendimento_role';
GRANT SELECT ON petcare.veterinarios             TO 'petcare_atendimento_role';

-- Pode agendar, confirmar e cancelar consultas (INSERT/UPDATE), mas não apagar.
GRANT SELECT, INSERT, UPDATE ON petcare.consultas TO 'petcare_atendimento_role';

GRANT SELECT ON petcare.vw_agenda_consultas TO 'petcare_atendimento_role';

GRANT EXECUTE ON PROCEDURE petcare.sp_agendar_consulta TO 'petcare_atendimento_role';
GRANT EXECUTE ON FUNCTION  petcare.fn_gerar_id         TO 'petcare_atendimento_role';
GRANT EXECUTE ON FUNCTION  petcare.fn_calcular_idade   TO 'petcare_atendimento_role';

-- ---------------------------------------------------------------------
-- CONTAS (uma por perfil). O usuário só recebe a role; as permissões
-- ficam na role. Trocar o perfil de alguém = trocar a role, não refazer GRANTs.
-- Host '%': permite conexão de outra máquina/contêiner (a API pode rodar
-- fora do servidor do banco). Em produção, troque '%' pelo IP do servidor da API.
-- Troque as senhas antes de usar fora do ambiente de aula.
-- ---------------------------------------------------------------------
CREATE USER 'petcare_app_admin'@'%'       IDENTIFIED BY 'Admin@PetCare2026';
CREATE USER 'petcare_app_vet'@'%'         IDENTIFIED BY 'Vet@PetCare2026';
CREATE USER 'petcare_app_atendimento'@'%' IDENTIFIED BY 'Atend@PetCare2026';

GRANT 'petcare_admin_role'       TO 'petcare_app_admin'@'%';
GRANT 'petcare_vet_role'         TO 'petcare_app_vet'@'%';
GRANT 'petcare_atendimento_role' TO 'petcare_app_atendimento'@'%';

-- Sem SET DEFAULT ROLE a role existe mas fica desligada ao conectar.
SET DEFAULT ROLE 'petcare_admin_role'       TO 'petcare_app_admin'@'%';
SET DEFAULT ROLE 'petcare_vet_role'         TO 'petcare_app_vet'@'%';
SET DEFAULT ROLE 'petcare_atendimento_role' TO 'petcare_app_atendimento'@'%';

FLUSH PRIVILEGES;
