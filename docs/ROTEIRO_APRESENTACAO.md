# Roteiro da apresentação — 5 minutos

**Antes de começar (deixe aberto):** banco recém-instalado (`docker compose down -v && docker compose up -d`, ou rode 01→04 de novo), API rodando, front aberto, Workbench com 3 abas: `petcare_app_vet`, `petcare_app_atendimento` e uma de administrador.

> Reinstale o banco antes de apresentar: os demos mudam dados (o demo de TCL conclui a consulta da Paçoca).

| Tempo | O que mostrar | O que falar |
|---|---|---|
| 0:00–0:30 | slide/DER | "PetCare: clínica veterinária. 12 tabelas. Usuário pode ser tutor ou veterinário (1:1). Pet tem consultas, consulta gera prontuário. Vacinação e prescrição são N:N com atributos." |
| 0:30–1:30 | **Aplicação** | Agenda (view 1) → pets do tutor (entidade) → histórico do pet (view 2) → tentar agendar no passado: aparece o erro **do trigger**. Abrir `/api/info`: "a API está conectada como `petcare_app_vet`, não root." |
| 1:30–2:00 | **IDs + índices** | `fn_gerar_id`: "128 bits aleatórios, não dá para adivinhar o próximo, ao contrário do AUTO_INCREMENT". Rodar 2 EXPLAIN de `demo_indices.sql`: com índice `ref`, sem índice `ALL + filesort`. |
| 2:00–2:40 | **Views + stored objects** | Mostrar `03_programacao.sql`: 3 triggers (uma frase cada), 2 views (simplificam JOIN + segurança), procedures INVOKER. |
| 2:40–3:40 | **TCL** (aba vet) | `demo_tcl.sql` cenário 3: consulta EM_ATENDIMENTO → CALL sem diagnóstico → erro → status **continua** EM_ATENDIMENTO = ROLLBACK. Cenário 4: com diagnóstico → CONCLUIDA + prontuário = COMMIT. |
| 3:40–4:40 | **Acesso** | Aba atendimento: agenda OK, `SELECT * FROM prontuarios` → **negado**. Aba vet: `SELECT senha_hash` → **negado** (permissão por coluna). Aba admin: `SHOW GRANTS ... USING role`. |
| 4:40–5:00 | fechamento | "Regras no banco valem para qualquer cliente; menor privilégio; transação garante consistência." |

## Perguntas prováveis

**Por que não AUTO_INCREMENT?** Previsível (dá para enumerar registros alheios), depende do INSERT para existir e colide em migração. Usamos 128 bits aleatórios com prefixo da entidade.

**Por que não `UUID()`?** O UUID do MySQL é versão 1 (relógio + MAC), parcialmente previsível.

**Desvantagem do seu ID?** Mais espaço que INT e inserção em posição aleatória no índice (B-Tree). Para o volume de uma clínica é irrelevante.

**Por que trigger e não validar só no Java?** A regra vale para qualquer cliente que acesse o banco, não só para a nossa API.

**BEFORE ou AFTER?** BEFORE, porque o objetivo é impedir a gravação. AFTER serviria para auditoria/log.

**O que acontece se der erro no meio do `sp_finalizar_atendimento`?** O EXIT HANDLER faz ROLLBACK (desfaz o UPDATE) e RESIGNAL (repassa o erro para a API mostrar).

**Diferença entre ROLLBACK e SAVEPOINT?** ROLLBACK desfaz a transação inteira; `ROLLBACK TO SAVEPOINT` desfaz só o que veio depois do ponto marcado.

**Precisa de transação para um INSERT só?** Não: com autocommit, um comando sozinho já é atômico. Transação é para **várias** operações que precisam andar juntas.

**Por que esses índices e não em todas as colunas?** Cada índice deixa INSERT/UPDATE mais lento e ocupa espaço. Criamos só os que atendem consultas reais da aplicação, compostos na ordem igualdade → intervalo/ordenação.

**Por que o EXPLAIN às vezes mostra ALL mesmo com índice?** Com poucas linhas, ler a tabela inteira é mais barato; o otimizador decide por custo.

**Por que não existe índice separado na FK `id_pet` de consultas?** O InnoDB reaproveita o índice composto que começa por `id_pet`.

**Por que a view ajuda na segurança?** O atendimento tem SELECT na view da agenda, mas não nas tabelas de usuários/veterinários; vê só as colunas que a view expõe.

**SQL SECURITY INVOKER x DEFINER?** INVOKER usa a permissão de quem chama a procedure; DEFINER usa a de quem a criou. Escolhemos INVOKER para a procedure não virar atalho de permissão.

**Diferença entre `grupos_usuarios` e as roles do MySQL?** Grupos são dado da aplicação (perfil da pessoa no sistema); roles são segurança do SGBD (o que a conexão pode fazer no banco).

**Por que o vet não pode dar DELETE?** Prontuário é documento clínico; o histórico deve ser preservado. Desativação é lógica (`ativo = FALSE`).

**Por que host `'%'`?** A API pode rodar em outra máquina/contêiner. Em produção, restringiríamos ao IP do servidor da API.

**Por que JdbcTemplate e não JPA?** O foco é o banco: SQL explícito, chamando views e procedures pelo nome. Parâmetros com `?` evitam SQL injection.
