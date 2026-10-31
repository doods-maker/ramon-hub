# Peticionamento: esteira no hub, executor trocável, credenciais no cofre do hub

Queríamos protocolar petições de dentro do hub, como o Legis faz. A via oficial de máquina (MNI) do eproc e do PJe
é só para instituições: o TJSC e o PJe-JT a oferecem a órgão público conveniado, e no TRF4 o acesso institucional
exige convênio, que a Res. TRF4 17/2010 só prevê para órgão público (pesquisas de 30 e 31/10/2026). O Eduardo
descartou o MNI em 31/10/2026. Todo o mercado
(Legis, Intima.ai, Oystr, PeticionaMais) protocola com robô usando as credenciais do advogado.

Decidimos: o hub constrói a **esteira** (petição, pacote, regras do tribunal, aprovação do advogado, fila,
comprovante, auditoria) e o protocolo em si fica com um **executor trocável**: manual primeiro, robô do eproc depois
(TRF4/JFSC e TJSC são o mesmo sistema e assinam por login + senha, sem certificado), e API
contratada para o PJe-JT. Trocar o executor não mexe na esteira.

As credenciais (senha, **semente do 2FA** e, se um dia preciso, o A1) ficam num **cofre dentro do hub**, cifradas com
Active Record Encryption, com as chaves no `chatwoot.env` da VPS. Rejeitamos um serviço de cofre separado (Vault,
Infisical): mais uma peça para manter na mesma VPS, sem ganho real de segurança. Guardar a semente do 2FA põe os dois
fatores no hub; aceitamos isso porque é o que permite fila e lote para 300–1.000 petições/mês. A alternativa (o
advogado digita o código do tribunal a cada protocolo) fica registrada para o caso de o Eduardo preferir.

Nenhum protocolo sai sem o clique do advogado responsável (princípio de aprovação do estatuto).
