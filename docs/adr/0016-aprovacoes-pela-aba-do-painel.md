# 0016. Aprovações pela aba do painel

Data: 07/11/2026. Pedido do Eduardo: agir pelo painel dos agentes (aprovar, digitar na sessão, pausar, dar nota), e só ele;
o Dr. Ramon continua só vendo.

## Decisão

As aprovações saem de cima do iframe e viram uma aba do painel. O painel mostra e pede; quem lê e decide continua sendo a
página `Agentes` do hub, com a sessão de quem está logado.

- **Ponte por `postMessage`:** o painel manda `ouvir` e `decidir` para a página do hub; a página responde `aprovacoes` (a
  cada 5 s enquanto houve `ouvir` no último minuto) e `decidida`. Os dois lados conferem a origem e a janela de quem
  manda e ignoram mensagem com `fonte` errada. O contrato está no plano C do painel (repo da esteira).
- **Decisores separados de quem vê:** ver continua em `RAMON_PAINEL_AGENTES_EMAILS`; decidir e escrever no painel exige
  também `RAMON_AGENTES_DECISORES_EMAILS`. Sem a env, ninguém decide. A lista de pedidos diz `pode_decidir`, e decidir
  sem estar na lista dá 403.
- **Identidade ao painel pelo portão:** no 204, o portão responde `X-Painel-Usuario` (e-mail) e `X-Painel-Escreve`
  (`1` ou `0`). O Caddy apaga esses cabeçalhos e o `X-Painel-Segredo` vindos do navegador antes de tudo, copia os do
  portão e põe a senha interna (`PAINEL_SEGREDO`, de `/etc/esteira/painel.env`) em cada pedido ao painel. O painel só
  aceita escrita com a senha certa e o "escreve" do portão.

## O que a ADR 0014 continua garantindo

- Nenhuma credencial que decide aprovação fica na VPS da esteira: decidir é a página do hub chamando a API do hub com a
  sessão do usuário. A senha interna só prova ao painel que o pedido passou pelo Caddy; ela não decide nada no hub.
- Vazar o token do hook (`RAMON_ESTEIRA_APROVACOES_TOKEN`) continua não aprovando nada.
- Dado de cliente apagado ao decidir, motivo entregue uma vez e apagado, regra `deny` da esteira acima de tudo.

## Consequências

- Pela ponte, a origem do painel passa a conseguir disparar aprovações com a sessão do hub de quem decide e está logado.
  A fronteira é a CSP do painel (`default-src 'self'`) e o código dele: um XSS no painel agora importa.
- O `env_file` do Caddy usa a forma longa com `required: false` (compose >= 2.24): sem o arquivo da esteira, o compose
  do hub continua subindo e o painel recusa escrita, porque a senha chega vazia.
- Sem a aba Aprovações aberta, o hub não consulta nada: o pedido espera, como antes, até 12 horas.
- O hub passa a mandar ao painel o título e as linhas já traduzidos (via `descreverPedido`) e a entrada cortada em 4000
  caracteres; o painel não precisa conhecer as ferramentas.
- Instalar exige antes o `install.sh` da esteira (cria a senha); o `instalar.sh` do hub para com essa instrução se não a
  encontrar.
