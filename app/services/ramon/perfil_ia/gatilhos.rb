# Gatilhos de equipe (Ramon::PerfilIa::GATILHOS): chave => nome na tela + texto da linha no prompt da conversa.
# rubocop:disable Layout/LineLength -- os textos são as linhas aprovadas, não se quebram
module Ramon::PerfilIa::Gatilhos
  # Ordem = a da tela. texto nil = pendente de aprovação (a tela não deixa ligar); texto = linha do prompt da conversa.
  TODOS = {
    'pediu_pessoa' => {
      'nome' => 'Pediu para falar com uma pessoa',
      'texto' => 'Se o lead pedir para falar com uma pessoa ou com um advogado, passe para humano.'
    },
    'juridica' => {
      'nome' => 'Dúvida ou decisão jurídica',
      'texto' => 'Sempre que uma dúvida exigir decisão jurídica sobre o caso concreto, passe para humano.'
    },
    'outra_area' => {
      'nome' => 'Outra área do direito',
      'texto' => 'Você atende a banca inteira (previdenciário e trabalhista). Se o assunto for outra área do direito, acolha e passe para humano, sem pedir detalhes desse outro assunto.'
    },
    'fora_do_tema' => {
      'nome' => 'Fora do tema da tese',
      'texto' => 'Se o lead contar um caso ou pedir ajuda num assunto diferente da tese desta conversa (ex.: chegou pelo número de acidente do trabalho e conta que o salário está atrasado, ou pergunta de aposentadoria), não tente encaixar no roteiro: acolha e passe para humano, dizendo no motivo qual é o outro assunto. Dúvida sobre o escritório, o honorário ou como funciona o atendimento não é outro assunto: responda pela FAQ.'
    },
    'honorario_de_novo' => {
      'nome' => 'Perguntou o honorário de novo',
      'texto' => 'Se o lead perguntar o valor do honorário pela segunda vez depois da sua resposta, passe para humano.'
    },
    'nao_le' => {
      'nome' => 'Não consegue ler ou escrever',
      'texto' => 'Se o lead disser que não sabe ler ou tiver dificuldade com mensagem escrita, passe para humano informando esse motivo.'
    },
    'irritado' => {
      'nome' => 'Lead irritado',
      'texto' => nil
    },
    'tem_advogado' => {
      'nome' => 'Já tem advogado',
      'texto' => nil
    },
    'desconto' => {
      'nome' => 'Pediu desconto',
      'texto' => nil
    },
    'clausula' => {
      'nome' => 'Quer mudar cláusula',
      'texto' => nil
    },
    # Etapa Documentos (spec §6; textos aprovados pelo Eduardo em 07/11): só nas etapas conduzidas (DOCUMENTOS abaixo).
    'govbr_senha_recebida' => {
      'nome' => 'Senha do gov.br recebida',
      'texto' => 'Quando o cliente mandar a senha do gov.br, agradeça sem repetir e passe para uma pessoa da equipe entrar no Meu INSS.'
    },
    'govbr_codigo' => {
      'nome' => 'Código de verificação do gov.br',
      'texto' => 'Se o acesso pedir o código de verificação do gov.br, ou o cliente precisar mandar um código, passe para uma pessoa da equipe.'
    },
    'govbr_sem_acesso' => {
      'nome' => 'Sem acesso ao gov.br',
      'texto' => 'Se o cliente não conseguir criar a conta, entrar ou recuperar a senha do gov.br depois do passo a passo, passe para uma pessoa da equipe.'
    },
    'sem_documento' => {
      'nome' => 'Cliente não tem o documento',
      'texto' => 'Se o cliente disser que não tem o documento, ou que só a empresa ou o médico tem, passe para uma pessoa da equipe.'
    }
  }.freeze

  # Só existem nas etapas conduzidas (Documentos): fora dos perfis prontos das abertas e escondidos delas na tela.
  DOCUMENTOS = %w[govbr_senha_recebida govbr_codigo govbr_sem_acesso sem_documento].freeze
  # Ligados em Documentos enquanto o alvo não gravou a lista da etapa (vale para qualquer base).
  PADRAO_DOCUMENTOS = (DOCUMENTOS + %w[pediu_pessoa irritado juridica]).freeze

  # Os ligados numa Etapa sem lista gravada no alvo (Ramon::PerfilIa#gatilhos).
  def self.padrao(etapa, pronto) = Ramon::EtapaDeGanho.conduzida?(etapa) ? PADRAO_DOCUMENTOS : pronto['gatilhos']
end
# rubocop:enable Layout/LineLength
