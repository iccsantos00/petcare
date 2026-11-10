package br.com.petcare;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * API do PetCare. Toda a regra pesada fica no banco (triggers, procedures,
 * views); a API só recebe o JSON, valida o formato e repassa ao MySQL.
 */
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class PetCareController {

    private final JdbcTemplate banco;

    public PetCareController(JdbcTemplate banco) {
        this.banco = banco;
    }

    // ===================== DADOS RECEBIDOS (JSON) =====================

    public record PetRequest(
        @NotBlank @Size(max = 80) String nome,
        @NotBlank @Size(max = 40) String especie,
        @Size(max = 80) String raca,
        @Pattern(regexp = "(?i)MACHO|FEMEA|NAO_INFORMADO") String sexo,
        @PastOrPresent LocalDate dataNascimento,
        @DecimalMin("0.01") BigDecimal pesoKg,
        @Pattern(regexp = "(?i)PEQUENO|MEDIO|GRANDE|NAO_INFORMADO") String porte,
        String alergias,
        String observacoes
    ) {}

    public record ConsultaRequest(
        @NotBlank String idPet,
        @NotBlank String idVeterinario,
        @NotNull LocalDateTime dataHora,   // "não pode ser no passado" é validado pelo TRIGGER 1
        @NotBlank @Size(max = 255) String motivo,
        @DecimalMin("0.00") BigDecimal valor
    ) {}

    public record FinalizarRequest(
        String anamnese,
        String diagnostico,
        String conduta,
        String observacoes
    ) {}

    public record VacinacaoRequest(
        @NotBlank String idPet,
        @NotBlank String idVacina,
        String idVeterinario,
        @NotNull LocalDate dataAplicacao,
        LocalDate proximaDose,
        @Size(max = 60) String lote,
        String observacoes
    ) {}

    // ===================== INFORMAÇÃO DA CONEXÃO =====================

    // Evidência para a apresentação: com qual usuário do MySQL a API está conectada.
    @GetMapping("/info")
    public Map<String, Object> info() {
        return banco.queryForMap("SELECT CURRENT_USER() AS usuario_mysql, CURRENT_ROLE() AS role_ativa");
    }

    // ===================== CADASTROS (ENTIDADES) =====================

    @GetMapping("/tutores")
    public List<Map<String, Object>> listarTutores() {
        return banco.queryForList("""
            SELECT t.id_tutor, u.nome, u.email, u.telefone, t.cidade, t.uf
            FROM tutores t
            JOIN usuarios u ON u.id_usuario = t.id_usuario
            WHERE u.ativo = TRUE
            ORDER BY u.nome
            """);
    }

    @GetMapping("/veterinarios")
    public List<Map<String, Object>> listarVeterinarios() {
        return banco.queryForList("""
            SELECT v.id_veterinario, u.nome, v.crmv, v.especialidade
            FROM veterinarios v
            JOIN usuarios u ON u.id_usuario = v.id_usuario
            WHERE v.ativo = TRUE
            ORDER BY u.nome
            """);
    }

    @GetMapping("/vacinas")
    public List<Map<String, Object>> listarVacinas() {
        return banco.queryForList("""
            SELECT id_vacina, nome, fabricante, especie_indicada
            FROM vacinas
            WHERE ativo = TRUE
            ORDER BY nome
            """);
    }

    // Todos os pets ativos (para preencher combos de agendamento/vacinação)
    @GetMapping("/pets")
    public List<Map<String, Object>> listarTodosPets() {
        return banco.queryForList("""
            SELECT p.id_pet, p.nome, p.especie, u.nome AS tutor
            FROM pets p
            JOIN tutores t  ON t.id_tutor = p.id_tutor
            JOIN usuarios u ON u.id_usuario = t.id_usuario
            WHERE p.ativo = TRUE
            ORDER BY p.nome
            """);
    }

    // Pets de um tutor (usa o índice idx_pets_tutor_ativo e a função fn_calcular_idade)
    @GetMapping("/tutores/{idTutor}/pets")
    public List<Map<String, Object>> listarPetsDoTutor(@PathVariable String idTutor) {
        return banco.queryForList("""
            SELECT id_pet, nome, especie, raca, sexo, data_nascimento,
                   fn_calcular_idade(data_nascimento) AS idade,
                   peso_kg, porte, alergias, observacoes
            FROM pets
            WHERE id_tutor = ? AND ativo = TRUE
            ORDER BY nome
            """, idTutor);
    }

    @PostMapping("/tutores/{idTutor}/pets")
    public ResponseEntity<Map<String, String>> cadastrarPet(
        @PathVariable String idTutor,
        @Valid @RequestBody PetRequest pet
    ) {
        String id = gerarId("PET");

        banco.update("""
            INSERT INTO pets (id_pet, id_tutor, nome, especie, raca, sexo,
                              data_nascimento, peso_kg, porte, alergias, observacoes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            id, idTutor, pet.nome(), pet.especie(), pet.raca(),
            maiusculoOuPadrao(pet.sexo(), "NAO_INFORMADO"),
            pet.dataNascimento(), pet.pesoKg(),
            maiusculoOuPadrao(pet.porte(), "NAO_INFORMADO"),
            pet.alergias(), pet.observacoes());

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("idPet", id));
    }

    // Exclusão lógica: o pet some das listas, mas o histórico clínico continua.
    @DeleteMapping("/pets/{idPet}")
    public ResponseEntity<Void> desativarPet(@PathVariable String idPet) {
        int linhas = banco.update("UPDATE pets SET ativo = FALSE WHERE id_pet = ?", idPet);
        return linhas > 0 ? ResponseEntity.noContent().build() : ResponseEntity.notFound().build();
    }

    // Carteira de vacinação do pet
    @GetMapping("/pets/{idPet}/vacinacoes")
    public List<Map<String, Object>> listarVacinacoes(@PathVariable String idPet) {
        return banco.queryForList("""
            SELECT va.id_vacinacao, v.nome AS vacina, va.data_aplicacao,
                   va.proxima_dose, va.lote
            FROM vacinacoes va
            JOIN vacinas v ON v.id_vacina = va.id_vacina
            WHERE va.id_pet = ?
            ORDER BY va.data_aplicacao DESC
            """, idPet);
    }

    // ===================== CONSULTAS (VIEWS E PROCEDURES) =====================

    // VIEW 1
    @GetMapping("/consultas/agenda")
    public List<Map<String, Object>> consultarAgenda() {
        return banco.queryForList("SELECT * FROM vw_agenda_consultas ORDER BY data_hora");
    }

    // PROCEDURE 1 (o trigger trg_validar_consulta valida a data, o vet e o pet)
    @PostMapping("/consultas")
    public ResponseEntity<Map<String, String>> agendarConsulta(@Valid @RequestBody ConsultaRequest c) {
        String id = banco.queryForObject(
            "CALL sp_agendar_consulta(?, ?, ?, ?, ?)",
            String.class,
            c.idPet(), c.idVeterinario(), c.dataHora(), c.motivo(), c.valor());

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("idConsulta", id));
    }

    // Muda o status (ex.: CONFIRMADA, EM_ATENDIMENTO, CANCELADA).
    // O trigger trg_bloquear_consulta_encerrada impede mexer em consulta encerrada.
    @PatchMapping("/consultas/{idConsulta}/status")
    public ResponseEntity<Map<String, String>> atualizarStatus(
        @PathVariable String idConsulta,
        @RequestParam String valor
    ) {
        Set<String> permitidos = Set.of("AGENDADA", "CONFIRMADA", "EM_ATENDIMENTO", "CANCELADA", "FALTOU");
        String status = valor.toUpperCase();

        if (!permitidos.contains(status)) {
            return ResponseEntity.badRequest().body(Map.of("erro",
                "Status inválido. Para concluir use POST /consultas/{id}/finalizar."));
        }

        int linhas = banco.update("UPDATE consultas SET status = ? WHERE id_consulta = ?", status, idConsulta);
        return linhas > 0 ? ResponseEntity.noContent().build() : ResponseEntity.notFound().build();
    }

    // PROCEDURE 3 - transação: conclui a consulta E grava o prontuário (tudo ou nada)
    @PostMapping("/consultas/{idConsulta}/finalizar")
    public ResponseEntity<Map<String, String>> finalizarAtendimento(
        @PathVariable String idConsulta,
        @RequestBody FinalizarRequest f
    ) {
        String id = banco.queryForObject(
            "CALL sp_finalizar_atendimento(?, ?, ?, ?, ?)",
            String.class,
            idConsulta, f.anamnese(), f.diagnostico(), f.conduta(), f.observacoes());

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("idProntuario", id));
    }

    // VIEW 2
    @GetMapping("/pets/{idPet}/historico-clinico")
    public List<Map<String, Object>> consultarHistorico(@PathVariable String idPet) {
        return banco.queryForList(
            "SELECT * FROM vw_historico_clinico WHERE id_pet = ? ORDER BY data_hora DESC",
            idPet);
    }

    // PROCEDURE 2
    @PostMapping("/vacinacoes")
    public ResponseEntity<Map<String, String>> registrarVacinacao(@Valid @RequestBody VacinacaoRequest v) {
        String id = banco.queryForObject(
            "CALL sp_registrar_vacinacao(?, ?, ?, ?, ?, ?, ?)",
            String.class,
            v.idPet(), v.idVacina(), v.idVeterinario(), v.dataAplicacao(),
            v.proximaDose(), v.lote(), v.observacoes());

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("idVacinacao", id));
    }

    // ===================== AUXILIARES =====================

    // FUNCTION fn_gerar_id: o ID é gerado pelo banco, não pelo Java.
    private String gerarId(String prefixo) {
        return banco.queryForObject("SELECT fn_gerar_id(?)", String.class, prefixo);
    }

    private String maiusculoOuPadrao(String valor, String padrao) {
        return valor == null || valor.isBlank() ? padrao : valor.toUpperCase();
    }

    // ===================== TRATAMENTO DE ERROS =====================

    // Erros do banco. SQLSTATE 45000 = erro de regra de negócio lançado por
    // SIGNAL nos triggers/procedures: a mensagem é nossa, pode ir para a tela.
    // Os demais (FK inexistente, permissão negada...) viram mensagem genérica,
    // para não expor detalhes internos do banco.
    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<Map<String, String>> tratarErroBanco(DataAccessException erro) {
        if (erro.getMostSpecificCause() instanceof SQLException sql && "45000".equals(sql.getSQLState())) {
            return ResponseEntity.unprocessableEntity().body(Map.of("erro", sql.getMessage()));
        }
        return ResponseEntity.badRequest().body(Map.of("erro",
            "Não foi possível concluir a operação. Verifique os dados informados."));
    }

    // Erros de validação do JSON (@NotBlank, @Future...)
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, String>> tratarValidacao(MethodArgumentNotValidException erro) {
        var campo = erro.getBindingResult().getFieldErrors().get(0);
        return ResponseEntity.badRequest().body(Map.of("erro",
            campo.getField() + ": " + campo.getDefaultMessage()));
    }
}
