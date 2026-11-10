# PetCare

Sistema de clínica veterinária feito para a disciplina de Banco de Dados (UCB).
Banco em MySQL, API em Spring Boot e frontend web.

## Pastas

- `banco/` – scripts do MySQL, executados na ordem 01 a 04
- `banco/demos/` – scripts usados na apresentação (transações, acessos e índices)
- `backend/` – API em Java 17 com Spring Boot
- `docs/` – DER, documentação da API e roteiro da apresentação

## Como rodar (Mac)

### 1. MySQL

```bash
brew install mysql@8.4
brew services start mysql@8.4
echo 'export PATH="/opt/homebrew/opt/mysql@8.4/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Criar o banco:

```bash
cd banco
for f in 01_estrutura.sql 02_dados.sql 03_programacao.sql 04_seguranca.sql; do
  mysql -u root < $f
done
```

O root só é usado para criar o banco. A aplicação usa o usuário `petcare_app_vet`.

Para recriar o banco do zero, é só rodar os scripts de novo.

### 2. API

```bash
brew install openjdk@17 maven
echo 'export JAVA_HOME=/opt/homebrew/opt/openjdk@17' >> ~/.zshrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

cd backend
mvn spring-boot:run
```

A API fica em `http://localhost:8080/api`. Para testar, abra `http://localhost:8080/api/info`, que mostra o usuário do banco que está conectado.

As rotas estão em `docs/API.md`.

### Docker (opcional)

Quem tiver Docker pode subir o MySQL com `docker compose up -d` na raiz do projeto, no lugar do passo 1.

## Usuários do banco

| Usuário | Senha | Perfil |
|---|---|---|
| `petcare_app_admin` | `Admin@PetCare2026` | administrador |
| `petcare_app_vet` | `Vet@PetCare2026` | veterinário (usado pela API) |
| `petcare_app_atendimento` | `Atend@PetCare2026` | recepção |

## O que tem no banco

- 12 tabelas, incluindo `usuarios` e `grupos_usuarios`
- IDs gerados pela função `fn_gerar_id`, sem AUTO_INCREMENT
- 8 índices
- 3 triggers, 2 views, 3 procedures e 2 functions
- Transação com COMMIT/ROLLBACK na procedure `sp_finalizar_atendimento`
- 3 perfis de acesso com permissões diferentes
