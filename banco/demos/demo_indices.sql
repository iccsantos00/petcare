-- =====================================================================
-- DEMO ÍNDICES - para a apresentação
-- EXPLAIN mostra o plano de execução: em "key" aparece o índice usado
-- e em "rows" quantas linhas o MySQL estima ler.
-- type = ref/range (usa índice)  x  type = ALL (lê a tabela inteira).
-- =====================================================================

-- Garante acentuação correta (ã, é, ç) independente do cliente usado.
SET NAMES utf8mb4;

USE petcare;

SHOW INDEX FROM consultas;
-- Repare: não existe índice separado para a FK id_pet. O InnoDB reaproveita
-- idx_consultas_pet_data, porque id_pet é a 1ª coluna dele (prefixo à esquerda).

-- Histórico de um pet (consulta usada pela tela de histórico)
SELECT id_pet INTO @pet FROM pets WHERE nome = 'Thor';

EXPLAIN
SELECT * FROM consultas
WHERE id_pet = @pet
ORDER BY data_hora DESC;
-- key = idx_consultas_pet_data, sem "Using filesort": o índice já entrega ordenado

EXPLAIN
SELECT * FROM consultas IGNORE INDEX (idx_consultas_pet_data)
WHERE id_pet = @pet
ORDER BY data_hora DESC;
-- type = ALL + Using filesort: varre tudo e ainda ordena (o que o índice evita)

-- Agenda da semana
EXPLAIN
SELECT * FROM consultas
WHERE data_hora BETWEEN NOW() AND NOW() + INTERVAL 7 DAY;
-- type = range, key = idx_consultas_data_status: lê só o intervalo de datas.
-- Obs.: com tabela muito pequena o otimizador às vezes prefere ALL;
-- o ganho real aparece com milhares de linhas.

-- Pets ativos de um tutor
EXPLAIN
SELECT * FROM pets
WHERE id_tutor = (SELECT id_tutor FROM pets WHERE nome = 'Thor')
  AND ativo = TRUE;
-- key = idx_pets_tutor_ativo (as duas colunas do WHERE estão no índice)
