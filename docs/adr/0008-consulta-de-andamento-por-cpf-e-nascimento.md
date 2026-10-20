# Consulta de andamento identifica o cliente por CPF + data de nascimento

A LiderHub tinha um agente ("Andamentilson") que pedia o CPF e devolvia o
andamento do ADVBOX. No hub, a Consulta de andamento roda em qualquer caixa,
quando quem escreve diz que já é cliente. A pergunta é como saber que quem
pergunta é o próprio cliente.

Decidimos (Eduardo, 2026-10-14) que **a IA pede CPF + data de nascimento e só
responde se os dois conferem com o cadastro do cliente no ADVBOX**. Não
confere → humano. A resposta é a fase do processo em linguagem simples + o
link do Painel do Cliente; pergunta específica (valor, data de pagamento,
prazo) → humano. CPF e nascimento são usados na hora e não ficam gravados no
lead.

Consequências: o cliente digita dois dados; quem tem só o CPF de alguém não vê
o processo; o ADVBOX precisa ter a data de nascimento no cadastro (sem ela →
humano).

Alternativas descartadas:

- **Só o CPF** (como a LiderHub): CPF circula fácil; qualquer um com o CPF
  veria o processo de outra pessoa.
- **Pelo telefone já vinculado ao cliente**: dispensa digitar, mas só funciona
  para quem escreve do número cadastrado; o Eduardo preferiu a consulta por
  documento, que vale para qualquer número.
- **Só mandar o link do Painel**: o login cuida da identidade, mas a IA não
  responde nada — pior que a LiderHub para o cliente.

## Revisão (Eduardo, 2026-10-20): só o CPF

No smoke de 20/10 o Eduardo decidiu que a IA pede **só o CPF** (o cliente não
digita a data de nascimento), aceitando o risco descrito na alternativa
"Só o CPF" acima: quem tiver o CPF de um cliente vê a fase do processo dele. O
Claude recomendou CPF + conferir o número do WhatsApp com o telefone do
cadastro; ficou registrado como o caminho para endurecer, se precisar.

Junto entrou a **segunda chance**: no 1º CPF que não confere na conversa a IA
pede para conferir e mandar de novo (erro de digitação); do 2º em diante passa
para humano. A trava de 3 falhas por hora na conversa continua.
