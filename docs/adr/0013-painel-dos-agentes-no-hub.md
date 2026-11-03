# 0013. Painel dos agentes dentro do hub

Data: 02/11/2026. Decisão do Eduardo: ver o foreman-vision da esteira como uma tela do hub, sem túnel SSH.

## Decisão

O foreman-vision continua igual e fora do hub. A tela `Agentes` abre o painel em um iframe servido pelo Caddy em
`https://chat.ramonantonio.adv.br:8443`.

- **Portão:** a cada requisição, o `forward_auth` do Caddy pergunta a `GET /ramon_painel_agentes/portao`, que valida o
  cookie de sessão do hub e a lista `RAMON_PAINEL_AGENTES_EMAILS`. Sem a env, ninguém entra.
- **Porta própria, não subdomínio:** o painel usa caminhos absolutos (`/api`, `/assets`, `/events`), que colidem com os
  do hub, então não cabe em um caminho do mesmo endereço. Cookie não separa por porta, então a sessão do hub chega ao
  portão sem emitir bilhete nem criar registro de DNS.
- **Socket Unix até o painel:** o foreman-vision não tem login e lê transcripts com dado de cliente. Só o container do
  Caddy monta o socket; os outros containers da rede não alcançam o painel.
- **Sem tela refeita:** nada é reimplementado em Vue, e o painel pode ser atualizado sem mexer no hub.

## Consequências

- Rede que bloqueia a porta 8443 não abre o painel. Se isso aparecer, trocar por um subdomínio (exige DNS e bilhete de
  entrada, porque o cookie do hub não vale em outro host).
- Conexão de eventos já aberta continua até recarregar a tela, mesmo depois do logout: o portão só olha a abertura.
- O portão faz uma consulta e uma comparação de token por requisição. O painel faz poucas requisições, então o custo é
  o mesmo de uma chamada comum à API do hub.
- Aprovar permissões da esteira pelo hub é outra decisão, fora deste registro.
