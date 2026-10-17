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
    }
  }.freeze
end
# rubocop:enable Layout/LineLength
