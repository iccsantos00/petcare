# PetCare — Sistema de Clínica Veterinária

Trabalho de Banco de Dados (UCB). Banco MySQL 8 + API REST em Spring Boot + frontend web.

## Estrutura

```
petcare/
├── banco/                     scripts do MySQL (rodar em ordem)
│   ├── 01_estrutura.sql       banco, funções de ID, tabelas, índices
│   ├── 02_dados.sql           dados de exemplo (antes dos triggers, ver comentário)
│   ├── 03_programacao.sql     3 triggers, 2 views, 3 procedures
│   ├── 04_seguranca.sql       roles e usuários (controle de acesso)
│   └── demos/                 scripts para a apresentação (TCL, acesso, índices)
├── backend/                   API Spring Boot (Java 17)
│   ├── src/main/java/br/com/petcare/PetCareController.java   todos os endpoints
│   ├── src/main/resources/application.properties             conexão (usuário da aplicação)
│   └── requests.http          chamadas prontas para testar a API
├── docs/
│   ├── API.md                 contrato da API (para quem faz o frontend)
│   ├── der.puml               DER em PlantUML (editável) + DER_PetCare.png
│   ├── JUSTIFICATIVAS.md      justificativa de cada item (base para o artigo)
│   └── ROTEIRO_APRESENTACAO.md  roteiro de 5 min + perguntas prováveis
└── docker-compose.yml         sobe o MySQL já instalado (opcional)
```

## Como rodar

### 1. Banco de dados

**Opção A — Docker (mais simples):**

```bash
docker compose up -d
```

Os 4 scripts de `banco/` rodam sozinhos na primeira subida. Para reinstalar do zero: `docker compose down -v && docker compose up -d`.

**Opção B — MySQL instalado na máquina (8.0.16 ou superior):**

Abra os scripts no MySQL Workbench conectado como administrador e execute na ordem 01 → 02 → 03 → 04. Ou pelo terminal:

```bash
cd banco
for f in 01_estrutura.sql 02_dados.sql 03_programacao.sql 04_seguranca.sql; do
  mysql -u root -p < $f
done
```

> O administrador (root) é usado **só para instalar** o banco. A aplicação conecta com `petcare_app_vet`.

### 2. Backend

Requer Java 17+. Na pasta `backend/`:

```bash
mvn spring-boot:run
```

Teste: `http://localhost:8080/api/info` deve devolver `petcare_app_vet@%`.

Para usar outro usuário/senha sem mexer no código: variáveis de ambiente `DB_URL`, `DB_USER`, `DB_PASSWORD`.

### 3. Frontend

Ver `docs/API.md`. A API já libera CORS, então o front pode rodar em qualquer porta (ex.: Live Server do VS Code). Alternativa: colocar os arquivos HTML/CSS/JS em `backend/src/main/resources/static/` e acessar `http://localhost:8080`.

## Usuários do banco

| Usuário MySQL | Senha (ambiente de aula) | Role | Uso |
|---|---|---|---|
| `petcare_app_admin` | `Admin@PetCare2026` | `petcare_admin_role` | administração dos dados |
| `petcare_app_vet` | `Vet@PetCare2026` | `petcare_vet_role` | **usado pela API** |
| `petcare_app_atendimento` | `Atend@PetCare2026` | `petcare_atendimento_role` | recepção (demo de acesso negado) |

## Checklist do enunciado

| Requisito | Onde está |
|---|---|
| Tabelas com relacionamentos (incl. `usuarios` e `grupos_usuarios`) | `01_estrutura.sql` — 12 tabelas |
| Índices justificados | `01_estrutura.sql` (comentários) + `demos/demo_indices.sql` |
| ≥ 2 triggers | `trg_validar_consulta`, `trg_validar_prontuario`, `trg_bloquear_consulta_encerrada` |
| ≥ 2 views | `vw_agenda_consultas`, `vw_historico_clinico` |
| ≥ 2 procedures/functions | `sp_agendar_consulta`, `sp_registrar_vacinacao`, `sp_finalizar_atendimento`, `fn_gerar_id`, `fn_calcular_idade` |
| Usuários e níveis de acesso, sem root | `04_seguranca.sql` + `demos/demo_acesso.sql` + `GET /api/info` |
| Função própria de geração de ID, sem AUTO_INCREMENT | `fn_gerar_id` |
| TCL (COMMIT/ROLLBACK) | `sp_finalizar_atendimento` + `demos/demo_tcl.sql` |
| Exibir 1 view e 1 entidade | `GET /api/consultas/agenda` (view) e `GET /api/tutores/{id}/pets` (entidade) |
