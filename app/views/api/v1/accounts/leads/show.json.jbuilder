json.partial! 'lead', lead: @lead
# resumo do CNIS só no show (não no index — evita inchar o payload do Kanban):
# faz a página Cálculos reconhecer, a frio, que o lead já tem CNIS processado
json.cnis_resumo @lead.cnis_resumo
