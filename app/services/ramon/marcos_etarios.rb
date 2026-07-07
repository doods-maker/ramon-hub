module Ramon
  # Calendário de direitos por idade — radar de OPORTUNIDADE, não parecer jurídico.
  # Tabela versionada das idades-alvo (pós-EC 103/2019). Não consulta o motor:
  # idade é aritmética de data + tabela fixa.
  class MarcosEtarios
    MARCOS = [
      { key: 'aposentadoria_idade_urbana', idades: { 'M' => 65, 'F' => 62 } },
      { key: 'aposentadoria_idade_rural',  idades: { 'M' => 60, 'F' => 55 } },
      { key: 'bpc_loas_idoso',             idades: { 'M' => 65, 'F' => 65 } }
    ].freeze

    def self.para(data_nascimento:, sexo: nil)
      return [] if data_nascimento.blank?

      sexo = nil unless %w[M F].include?(sexo)
      MARCOS.flat_map { |marco| entries_for(marco, data_nascimento, sexo) }
            .sort_by { |m| m[:data] }
    end

    def self.entries_for(marco, nascimento, sexo)
      idades = marco[:idades]
      return [build(marco, nascimento, sexo, idades[sexo])] if sexo.present?
      return [build(marco, nascimento, nil, idades.values.first)] if idades.values.uniq.one?

      idades.map { |s, idade| build(marco, nascimento, s, idade) }
    end

    def self.build(marco, nascimento, sexo, idade)
      data = nascimento + idade.years
      { key: marco[:key], sexo: sexo, idade: idade, data: data, atingido: data <= Time.zone.today }
    end

    private_class_method :entries_for, :build
  end
end
