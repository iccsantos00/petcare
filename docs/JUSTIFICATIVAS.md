# Justificativas técnicas — base para o artigo

> O enunciado tira até 50% da nota do item que estiver sem justificativa. Cada item abaixo tem o "o quê" e o "por quê".

## Tecnologias

| Camada | Escolha | Por quê |
|---|---|---|
| SGBD | MySQL 8.0 | Exigido; versão 8 traz **roles** (controle de acesso por perfil) e **CHECK** (a partir da 8.0.16). Engine InnoDB: transações ACID e chaves estrangeiras. |
| Backend | Java 17 + Spring Boot 3 + JdbcTemplate | Spring Boot sobe uma API REST com pouco código. JdbcTemplate (e não JPA/Hibernate) porque o SQL fica explícito: a API chama as views e procedures pelo nome, e as regras ficam no banco, que é o foco da disciplina. Parâmetros com `?` evitam SQL injection. |
| Frontend | (preencher pelo responsável) | |
| Infra | Docker Compose (opcional) | Qualquer membro do grupo sobe o mesmo banco com um comando. |

## Modelagem

- **12 tabelas**, 3FN. Dados comuns de pessoa (nome, e-mail, senha) ficam só em `usuarios`; `tutores` e `veterinarios` são especializações 1:1 (FK `id_usuario` UNIQUE). Evita duplicar e-mail/senha em duas tabelas.
- `grupos_usuarios` (1:N com `usuarios`) classifica o usuário no **sistema** (admin, veterinário, atendimento, tutor). As **roles do MySQL** controlam o acesso ao **banco**. São camadas diferentes: uma é dado da aplicação, a outra é segurança do SGBD.
- **N:N resolvidas por tabelas associativas com atributos próprios**: `vacinacoes` (pet × vacina, com data, lote e próxima dose) e `prescricoes` (consulta × medicamento, com dosagem e frequência).
- `prontuarios` é 1:1 com `consultas` (`id_consulta` UNIQUE): uma consulta gera no máximo um prontuário.
- **ON DELETE RESTRICT** em quase todas as FKs: prontuário e histórico de vacinas são documentos clínicos e não podem sumir em cascata. Para tirar algo de circulação usa-se **exclusão lógica** (`ativo = FALSE`). Exceção: `vacinacoes.id_veterinario` é `SET NULL`; se o veterinário for removido, a aplicação da vacina continua registrada.
- **ENUM** para domínios fechados (status, sexo, porte): o banco recusa valores fora da lista.
- **CHECK** para regras simples de coluna: peso > 0, valor ≥ 0, próxima dose ≥ aplicação, resultado ≥ solicitação.

## Geração de IDs — `fn_gerar_id(prefixo)`

Formato `PREFIXO-<32 hex>`, ex.: `PET-9F3A1C...`. Não usamos AUTO_INCREMENT porque:
1. **Segurança:** ID sequencial é previsível (quem vê `/pets/10` tenta `/pets/11`). Os 32 hex vêm de `RANDOM_BYTES(16)`, gerador criptográfico com 128 bits: não dá para adivinhar.
2. **O ID existe antes do INSERT:** a procedure já devolve o ID criado, sem `LAST_INSERT_ID()`.
3. **Sem colisão em migração/integração** com outro banco.
4. **Legibilidade:** o prefixo mostra a entidade (PET, CON, PRO, VAC...).

Por que não `UUID()`: no MySQL ele é UUID versão 1, montado com relógio + MAC da máquina, ou seja, parcialmente previsível.
Custo assumido: chave de 37 caracteres ocupa mais espaço que um INT e gera inserções em posição aleatória no índice; no volume de uma clínica isso é irrelevante frente ao ganho de segurança.
Exceção: `grupos_usuarios` usa IDs fixos (`GRP-ADMIN`...) por serem poucos, estáveis e referenciados pela aplicação.

## Índices

PK, UNIQUE e FK já ganham índice automático. Os criados são **compostos** e seguem as consultas reais: coluna de igualdade primeiro, de intervalo/ordenação depois.

| Índice | Consulta atendida | Impacto |
|---|---|---|
| `idx_pets_tutor_ativo (id_tutor, ativo)` | pets ativos de um tutor | filtro inteiro resolvido no índice |
| `idx_consultas_pet_data (id_pet, data_hora)` | histórico do pet ordenado | evita *filesort* (já sai ordenado) |
| `idx_consultas_vet_data (id_veterinario, data_hora)` | agenda de um veterinário | idem |
| `idx_consultas_data_status (data_hora, status)` | agenda por período | busca por intervalo (*range*) |
| `idx_vacinacoes_pet_data (id_pet, data_aplicacao)` | carteira de vacinação | evita *filesort* |
| `idx_vacinacoes_proxima_dose (proxima_dose)` | vacinas a vencer | busca por intervalo |
| `idx_exames_status_data (status, data_solicitacao)` | fila de exames pendentes | filtro + ordenação |
| `idx_usuarios_grupo_ativo (id_grupo, ativo)` | usuários por perfil | filtro no índice |

Evidência (`demos/demo_indices.sql`): com o índice, `EXPLAIN` mostra `type=ref`, `key=idx_consultas_pet_data`; forçando sem ele, `type=ALL` + `Using filesort`.
Observação: o InnoDB **reaproveita** `idx_consultas_pet_data` para a FK `id_pet` (é a 1ª coluna), então não existe índice duplicado.
Trade-off: cada índice deixa INSERT/UPDATE um pouco mais lento; por isso só foram criados os ligados a consultas que a aplicação faz.

## Triggers

| Trigger | Quando | Função |
|---|---|---|
| `trg_validar_consulta` | BEFORE INSERT em consultas | bloqueia data no passado, veterinário inativo e pet desativado |
| `trg_validar_prontuario` | BEFORE INSERT em prontuarios | só aceita prontuário de consulta EM_ATENDIMENTO ou CONCLUIDA |
| `trg_bloquear_consulta_encerrada` | BEFORE UPDATE em consultas | consulta CONCLUIDA/CANCELADA/FALTOU não muda status nem data |

Por que trigger e não só validação na API: a regra vale para **qualquer** cliente do banco (API, Workbench, outro sistema). Erros usam `SIGNAL SQLSTATE '45000'`; a API reconhece esse código e mostra a mensagem na tela.

## Views

| View | Finalidade | Uso |
|---|---|---|
| `vw_agenda_consultas` | junta 6 tabelas em um formato de agenda; calcula a idade do pet | `GET /api/consultas/agenda` |
| `vw_historico_clinico` | linha do tempo de consultas + prontuário (LEFT JOIN: consulta futura ainda sem prontuário) | `GET /api/pets/{id}/historico-clinico` |

Benefícios: (1) **simplificação**: a API faz um SELECT simples em vez de repetir JOINs; (2) **segurança**: o atendimento lê a agenda sem ter permissão em `usuarios`/`veterinarios`, e o histórico clínico só é liberado ao veterinário.

## Functions e Procedures

| Objeto | Para quê |
|---|---|
| `fn_gerar_id` | IDs próprios (ver acima) |
| `fn_calcular_idade` | idade do pet; usada na view da agenda e na listagem de pets. `NOT DETERMINISTIC` porque depende da data atual |
| `sp_agendar_consulta` | gera ID + insere + devolve o ID; o trigger 1 valida |
| `sp_registrar_vacinacao` | registra aplicação; sem próxima dose informada, calcula +1 ano |
| `sp_finalizar_atendimento` | **transação**: conclui a consulta e grava o prontuário juntos (ver TCL) |

Procedures usam `SQL SECURITY INVOKER`: rodam com a permissão de **quem chama**. Assim não viram atalho para burlar o controle de acesso (o atendimento não consegue registrar prontuário por meio de procedure).

## Controle de transações (TCL)

Cenário que exige transação: **finalizar atendimento** são duas escritas que só fazem sentido juntas (UPDATE da consulta para CONCLUIDA + INSERT do prontuário). Se a segunda falhar e a primeira ficar, teríamos consulta concluída sem prontuário.

`sp_finalizar_atendimento`: `START TRANSACTION` → UPDATE → validações → INSERT → `COMMIT`. Um `EXIT HANDLER FOR SQLEXCEPTION` faz `ROLLBACK` e `RESIGNAL` (repassa o erro para a API). Atomicidade do ACID.

Outros usos: a carga de dados (`02_dados.sql`) é uma transação única; `demos/demo_tcl.sql` mostra ROLLBACK manual, COMMIT e SAVEPOINT.

## Controle de acesso

Princípio do **menor privilégio**. Permissões ficam nas **roles**; usuários só recebem a role (`SET DEFAULT ROLE` ativa ao conectar).

| Role | Pode | Não pode |
|---|---|---|
| `petcare_admin_role` | SELECT/INSERT/UPDATE/DELETE/EXECUTE em tudo | DDL (DROP, ALTER, CREATE), GRANT |
| `petcare_vet_role` | ler cadastros; ler/gravar dados clínicos; views; procedures | DELETE; ler `senha_hash` (**permissão por coluna**) |
| `petcare_atendimento_role` | cadastrar usuários/tutores/pets; agendar; ver agenda | prontuários, prescrições, exames, histórico clínico; DELETE |

- Nenhum perfil tem DDL: a estrutura só muda por script de instalação.
- A API conecta como `petcare_app_vet` (evidência: `GET /api/info` → `petcare_app_vet@%`). Root é usado só para instalar o banco.
- Host `'%'` permite que a API rode em outra máquina/contêiner; em produção seria o IP do servidor da API.
- Senhas nos scripts são do ambiente de aula; a API aceita `DB_PASSWORD` por variável de ambiente para não fixar senha no código.
