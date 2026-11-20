# Importação silenciosa (coexistência do WhatsApp): o que é criado dentro do bloco não vira lead, não
# dispara funil, fluxo, automação, webhook nem notificação, a IA não responde e nada volta ao WhatsApp.
# O Dispatcher e Message#execute_after_create_commit_callbacks leem Current.importacao_silenciosa.
#
# Todo create! precisa acontecer DENTRO do bloco e fora de transação externa: os after_commit rodam no
# commit, e se ele cair depois do bloco a flag já desligou.
module Ramon::Silencio
  def self.executar
    anterior = Current.importacao_silenciosa
    Current.importacao_silenciosa = true
    yield
  ensure
    Current.importacao_silenciosa = anterior
  end
end
