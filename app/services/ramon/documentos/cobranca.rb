# Cobrança da etapa Documentos (spec Etapa Documentos §7): a configuração (config/ramon/documentos_cobranca.yml: ritmo, horário,
# textos aprovados, modelo da Meta e preço) e a sub-chave do lead onde mora o estado do relógio.
module Ramon::Documentos::Cobranca
  CHAVE = 'documentos_cobranca'.freeze
  CONFIG = YAML.safe_load_file(Rails.root.join('config/ramon/documentos_cobranca.yml')).freeze
end
