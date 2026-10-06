# Registro de ações (LGPD): a tabela audits vira somente-inclusão. UPDATE e
# DELETE falham com erro claro, venha de onde vier (app, console, SQL solto).
# Única exceção: a redação LGPD do Ramon::ContactAnonymizer, que liga
# `ramon.redacao_lgpd` só dentro da própria transação e só pode reescrever
# audited_changes — quem, quando, o quê e de quem ficam intactos.
# ponytail: sem expurgo automático — a trilha fica no mínimo 5 anos (LGPD);
# expurgo só se for pedido (e aí entra como exceção explícita aqui).
# ponytail: TRUNCATE não passa por trigger de linha; bloquear só se precisar.
class TornarAuditsSomenteInclusao < ActiveRecord::Migration[7.1]
  CORPO = <<~SQL_ACTIONS.freeze
    IF TG_OP = 'UPDATE'
       AND current_setting('ramon.redacao_lgpd', true) = 'on'
       AND (to_jsonb(NEW) - 'audited_changes') = (to_jsonb(OLD) - 'audited_changes') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Registro de ações: audits é somente-inclusão (% bloqueado no id %)', TG_OP, OLD.id
      USING HINT = 'A trilha fica guardada por 5 anos (LGPD). Só a redação LGPD do anonimizador reescreve audited_changes.';
  SQL_ACTIONS

  def up
    create_trigger('audits_somente_inclusao', generated: true, compatibility: 1)
      .on('audits').before(:update, :delete).for_each(:row) { CORPO }
  end

  def down
    drop_trigger('audits_somente_inclusao', 'audits', generated: true)
  end
end
