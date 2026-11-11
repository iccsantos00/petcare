# Contrato da API — para o frontend

Base: `http://localhost:8080/api` · JSON · CORS liberado.

O mínimo que o enunciado exige no front: **exibir 1 view e 1 entidade**. Sugestão de telas:

1. **Agenda** (VIEW) — tabela com `GET /consultas/agenda`.
2. **Pets do tutor** (ENTIDADE) — combo de tutores (`GET /tutores`) → tabela com `GET /tutores/{idTutor}/pets`.
3. *(opcional, ajuda muito na apresentação)* botão **Histórico** em cada pet → `GET /pets/{idPet}/historico-clinico` (2ª view); formulário de **agendar consulta** para mostrar o erro do trigger.

## Erros

Todo erro volta como `{ "erro": "mensagem" }`. Mostre `erro` na tela:

- **422** — regra de negócio do banco (trigger/procedure). Ex.: `"Consulta não pode ser agendada no passado."`
- **400** — dado inválido no JSON ou erro genérico do banco.

## Leitura

| Método | Rota | Retorna |
|---|---|---|
| GET | `/info` | `{ usuario_mysql, role_ativa }` — prova que não é root |
| GET | `/tutores` | `[{ id_tutor, nome, email, telefone, cidade, uf }]` |
| GET | `/veterinarios` | `[{ id_veterinario, nome, crmv, especialidade }]` |
| GET | `/vacinas` | `[{ id_vacina, nome, fabricante, especie_indicada }]` |
| GET | `/pets` | `[{ id_pet, nome, especie, raca, sexo, data_nascimento, idade, peso_kg, porte, alergias, tutor }]` (todos os ativos) |
| GET | `/tutores/{idTutor}/pets` | `[{ id_pet, nome, especie, raca, sexo, data_nascimento, idade, peso_kg, porte, alergias, observacoes }]` |
| GET | `/pets/{idPet}/vacinacoes` | `[{ id_vacinacao, vacina, data_aplicacao, proxima_dose, lote }]` |
| GET | `/consultas/agenda` | **VIEW** `[{ id_consulta, data_hora, status, motivo, id_pet, pet, especie, idade_pet, tutor, telefone_tutor, veterinario, valor }]` |
| GET | `/pets/{idPet}/historico-clinico` | **VIEW** `[{ id_pet, pet, id_consulta, data_hora, status, motivo, veterinario, anamnese, diagnostico, conduta, observacoes_clinicas }]` |

Datas chegam como `"2026-11-10"` e data/hora como `"2026-11-10T14:30:00"`.

## Escrita

**Cadastrar pet** — `POST /tutores/{idTutor}/pets` → 201 `{ idPet }`
```json
{ "nome": "Bob", "especie": "Cachorro", "raca": "Beagle", "sexo": "MACHO",
  "dataNascimento": "2024-01-15", "pesoKg": 10.5, "porte": "MEDIO",
  "alergias": null, "observacoes": null }
```
`sexo`: MACHO | FEMEA | NAO_INFORMADO · `porte`: PEQUENO | MEDIO | GRANDE | NAO_INFORMADO

**Editar pet** — `PUT /pets/{idPet}` → 204 (mesmo JSON do cadastro; o tutor não muda)

**Desativar pet** — `DELETE /pets/{idPet}` → 204 (exclusão lógica: `ativo = FALSE`)

**Agendar consulta** — `POST /consultas` → 201 `{ idConsulta }`
```json
{ "idPet": "PET-...", "idVeterinario": "VET-...",
  "dataHora": "2026-12-01T10:00:00", "motivo": "Rotina", "valor": 150.00 }
```

**Mudar status** — `PATCH /consultas/{idConsulta}/status?valor=EM_ATENDIMENTO` → 204
Valores: AGENDADA, CONFIRMADA, EM_ATENDIMENTO, CANCELADA, FALTOU.

**Finalizar atendimento** (transação) — `POST /consultas/{idConsulta}/finalizar` → 201 `{ idProntuario }`
```json
{ "anamnese": "...", "diagnostico": "...", "conduta": "...", "observacoes": null }
```
Só funciona com consulta CONFIRMADA ou EM_ATENDIMENTO. Sem `diagnostico` → 422 e nada é gravado.

**Registrar vacinação** — `POST /vacinacoes` → 201 `{ idVacinacao }`
```json
{ "idPet": "PET-...", "idVacina": "VCN-...", "idVeterinario": "VET-...",
  "dataAplicacao": "2026-11-10", "proximaDose": null, "lote": "L-123" }
```
Sem `proximaDose`, o banco calcula +1 ano.

## Exemplo em JS puro

```js
const API = 'http://localhost:8080/api';

async function carregarAgenda() {
  const resp = await fetch(`${API}/consultas/agenda`);
  const consultas = await resp.json();
  document.querySelector('#agenda tbody').innerHTML = consultas.map(c => `
    <tr>
      <td>${new Date(c.data_hora).toLocaleString('pt-BR')}</td>
      <td>${c.pet}</td><td>${c.tutor}</td><td>${c.veterinario}</td><td>${c.status}</td>
    </tr>`).join('');
}

async function agendar(dados) {
  const resp = await fetch(`${API}/consultas`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(dados)
  });
  const corpo = await resp.json();
  if (!resp.ok) alert(corpo.erro);   // mensagem do trigger aparece aqui
  return corpo;
}
```
