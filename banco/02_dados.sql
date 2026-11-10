-- =====================================================================
-- PETCARE - 02: DADOS DE EXEMPLO
-- Roda ANTES dos triggers (03) de propósito: o histórico tem consultas
-- no passado, que o trigger de agendamento bloquearia.
-- As datas são relativas a NOW(), então a agenda sempre tem consultas futuras.
-- A carga inteira é uma transação: ou entra tudo, ou nada.
-- =====================================================================

-- Garante acentuação correta (ã, é, ç) independente do cliente usado.
SET NAMES utf8mb4;

USE petcare;

START TRANSACTION;

-- Grupos (IDs fixos: são poucos, estáveis e referenciados pela aplicação)
INSERT INTO grupos_usuarios (id_grupo, nome, descricao) VALUES
('GRP-ADMIN', 'ADMINISTRADOR', 'Administração do sistema'),
('GRP-VET',   'VETERINARIO',   'Atendimento e registros clínicos veterinários'),
('GRP-ATEND', 'ATENDIMENTO',   'Cadastro de tutores, pets e agendamento'),
('GRP-TUTOR', 'TUTOR',         'Responsável pelo animal (acesso futuro ao portal)');

-- IDs gerados pela função e guardados em variáveis para montar as FKs
SET @u_admin = fn_gerar_id('USR');
SET @u_vet1  = fn_gerar_id('USR');
SET @u_vet2  = fn_gerar_id('USR');
SET @u_aten  = fn_gerar_id('USR');
SET @u_tut1  = fn_gerar_id('USR');
SET @u_tut2  = fn_gerar_id('USR');
SET @u_tut3  = fn_gerar_id('USR');

-- senha_hash: texto ilustrativo no formato BCrypt (não é senha real)
INSERT INTO usuarios (id_usuario, id_grupo, nome, email, senha_hash, telefone) VALUES
(@u_admin, 'GRP-ADMIN', 'Carla Administradora', 'admin@petcare.com',      '$2a$10$hashIlustrativoAdmin000000000000000000000000000000', '61999990000'),
(@u_vet1,  'GRP-VET',   'Dr. Rafael Souza',     'rafael@petcare.com',     '$2a$10$hashIlustrativoVet1000000000000000000000000000000', '61999990001'),
(@u_vet2,  'GRP-VET',   'Dra. Juliana Lima',    'juliana@petcare.com',    '$2a$10$hashIlustrativoVet2000000000000000000000000000000', '61999990002'),
(@u_aten,  'GRP-ATEND', 'Marcos Recepção',      'recepcao@petcare.com',   '$2a$10$hashIlustrativoAten000000000000000000000000000000', '61999990003'),
(@u_tut1,  'GRP-TUTOR', 'Ana Paula Ferreira',   'ana.ferreira@email.com', '$2a$10$hashIlustrativoTut1000000000000000000000000000000', '61988880001'),
(@u_tut2,  'GRP-TUTOR', 'Bruno Carvalho',       'bruno.c@email.com',      '$2a$10$hashIlustrativoTut2000000000000000000000000000000', '61988880002'),
(@u_tut3,  'GRP-TUTOR', 'Camila Rocha',         'camila.r@email.com',     '$2a$10$hashIlustrativoTut3000000000000000000000000000000', '61988880003');

SET @vet1 = fn_gerar_id('VET');
SET @vet2 = fn_gerar_id('VET');

INSERT INTO veterinarios (id_veterinario, id_usuario, crmv, especialidade) VALUES
(@vet1, @u_vet1, 'CRMV-DF 1234', 'Clínica geral'),
(@vet2, @u_vet2, 'CRMV-DF 5678', 'Dermatologia');

SET @tut1 = fn_gerar_id('TUT');
SET @tut2 = fn_gerar_id('TUT');
SET @tut3 = fn_gerar_id('TUT');

-- CPFs fictícios
INSERT INTO tutores (id_tutor, id_usuario, cpf, data_nascimento, logradouro, numero, bairro, cidade, uf, cep) VALUES
(@tut1, @u_tut1, '11111111111', '1990-04-12', 'QNM 10 Conjunto A', '15', 'Ceilândia', 'Brasília', 'DF', '72210100'),
(@tut2, @u_tut2, '22222222222', '1985-09-30', 'Rua 12 Chácara 3',  '7',  'Vicente Pires', 'Brasília', 'DF', '72005120'),
(@tut3, @u_tut3, '33333333333', '1998-01-05', 'Quadra 205',        '40', 'Águas Claras', 'Brasília', 'DF', '71925000');

SET @pet1 = fn_gerar_id('PET');
SET @pet2 = fn_gerar_id('PET');
SET @pet3 = fn_gerar_id('PET');
SET @pet4 = fn_gerar_id('PET');

INSERT INTO pets (id_pet, id_tutor, nome, especie, raca, sexo, data_nascimento, peso_kg, porte, alergias) VALUES
(@pet1, @tut1, 'Thor',  'Cachorro', 'Labrador',      'MACHO', '2019-06-10', 32.50, 'GRANDE',  NULL),
(@pet2, @tut1, 'Mel',   'Gato',     'Siamês',        'FEMEA', '2021-02-20',  4.10, 'PEQUENO', 'Dipirona'),
(@pet3, @tut2, 'Paçoca','Cachorro', 'Vira-lata',     'FEMEA', '2020-11-03', 12.00, 'MEDIO',   NULL),
(@pet4, @tut3, 'Luna',  'Cachorro', 'Shih-tzu',      'FEMEA', '2023-03-15',  6.30, 'PEQUENO', 'Frango');

-- Consultas: 3 no passado (concluídas), 1 em atendimento agora, 3 futuras
SET @con1 = fn_gerar_id('CON');
SET @con2 = fn_gerar_id('CON');
SET @con3 = fn_gerar_id('CON');
SET @con4 = fn_gerar_id('CON');
SET @con5 = fn_gerar_id('CON');
SET @con6 = fn_gerar_id('CON');
SET @con7 = fn_gerar_id('CON');

INSERT INTO consultas (id_consulta, id_pet, id_veterinario, data_hora, motivo, status, valor) VALUES
(@con1, @pet1, @vet1, DATE_SUB(NOW(), INTERVAL 60 DAY),  'Check-up anual',            'CONCLUIDA',      150.00),
(@con2, @pet2, @vet2, DATE_SUB(NOW(), INTERVAL 20 DAY),  'Queda de pelo',             'CONCLUIDA',      180.00),
(@con3, @pet1, @vet1, DATE_SUB(NOW(), INTERVAL 7 DAY),   'Vômito e falta de apetite', 'CONCLUIDA',      150.00),
(@con4, @pet3, @vet1, DATE_SUB(NOW(), INTERVAL 30 MINUTE),'Mancando da pata traseira','EM_ATENDIMENTO', 150.00),
(@con5, @pet4, @vet2, DATE_ADD(NOW(), INTERVAL 1 DAY),   'Coceira nas orelhas',       'CONFIRMADA',     180.00),
(@con6, @pet2, @vet1, DATE_ADD(NOW(), INTERVAL 3 DAY),   'Vacinação anual',           'AGENDADA',       120.00),
(@con7, @pet1, @vet1, DATE_ADD(NOW(), INTERVAL 10 DAY),  'Retorno',                   'AGENDADA',        NULL);

INSERT INTO prontuarios (id_prontuario, id_consulta, anamnese, diagnostico, conduta) VALUES
(fn_gerar_id('PRO'), @con1, 'Animal ativo, sem queixas.',                'Saudável.',                      'Manter vacinação e vermifugação em dia.'),
(fn_gerar_id('PRO'), @con2, 'Queda de pelo há 3 semanas, coceira leve.', 'Dermatite alérgica.',            'Shampoo terapêutico e troca de ração.'),
(fn_gerar_id('PRO'), @con3, 'Vômitos há 2 dias após comer lixo.',        'Gastroenterite alimentar.',      'Dieta leve por 5 dias e antiemético.');

-- Catálogos
SET @vac1 = fn_gerar_id('VCN');
SET @vac2 = fn_gerar_id('VCN');
SET @vac3 = fn_gerar_id('VCN');

INSERT INTO vacinas (id_vacina, nome, fabricante, especie_indicada, descricao) VALUES
(@vac1, 'V10 (Polivalente)', 'Zoetis',  'Cachorro', 'Cinomose, parvovirose, leptospirose e outras'),
(@vac2, 'Antirrábica',       'MSD',     NULL,       'Raiva - cães e gatos'),
(@vac3, 'V4 Felina',         'Zoetis',  'Gato',     'Rinotraqueíte, calicivirose, panleucopenia e clamidiose');

SET @med1 = fn_gerar_id('MED');
SET @med2 = fn_gerar_id('MED');

INSERT INTO medicamentos (id_medicamento, nome, principio_ativo, apresentacao) VALUES
(@med1, 'Ondansetrona 4mg', 'Ondansetrona',     'Comprimido'),
(@med2, 'Shampoo Clorexidina', 'Clorexidina 2%','Frasco 200 ml');

INSERT INTO vacinacoes (id_vacinacao, id_pet, id_vacina, id_veterinario, data_aplicacao, proxima_dose, lote) VALUES
(fn_gerar_id('VAC'), @pet1, @vac1, @vet1, DATE_SUB(CURDATE(), INTERVAL 60 DAY), DATE_ADD(CURDATE(), INTERVAL 305 DAY), 'L2026-001'),
(fn_gerar_id('VAC'), @pet1, @vac2, @vet1, DATE_SUB(CURDATE(), INTERVAL 60 DAY), DATE_ADD(CURDATE(), INTERVAL 305 DAY), 'L2026-002'),
(fn_gerar_id('VAC'), @pet2, @vac3, @vet2, DATE_SUB(CURDATE(), INTERVAL 340 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), 'L2025-117');

INSERT INTO prescricoes (id_prescricao, id_consulta, id_medicamento, dosagem, frequencia, duracao_dias, instrucoes) VALUES
(fn_gerar_id('PRC'), @con3, @med1, '1 comprimido', 'A cada 12 horas', 5, 'Dar 30 min antes da refeição'),
(fn_gerar_id('PRC'), @con2, @med2, 'Banho completo', '2 vezes por semana', 30, 'Deixar agir 10 minutos');

INSERT INTO exames (id_exame, id_consulta, tipo, data_solicitacao, data_resultado, resultado, status) VALUES
(fn_gerar_id('EXA'), @con3, 'Hemograma completo', DATE_SUB(CURDATE(), INTERVAL 7 DAY), DATE_SUB(CURDATE(), INTERVAL 6 DAY), 'Sem alterações relevantes.', 'CONCLUIDO'),
(fn_gerar_id('EXA'), @con4, 'Raio-X membro posterior', CURDATE(), NULL, NULL, 'SOLICITADO');

COMMIT;
