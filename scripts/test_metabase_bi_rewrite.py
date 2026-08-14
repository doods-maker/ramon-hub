"""Self-check da unica logica de parsing do script (nada de rede, so asserts).
Rodar: python scripts/test_metabase_bi_rewrite.py
"""
from metabase_bi_rewrite import transform_placar_sql

# caso real: alias 'l.', predicado seguido de AND (como o mb_faxina.py inseriu)
sql_com_alias = "SELECT COUNT(*) FROM leads l WHERE l.source IS DISTINCT FROM 'calculo-advbox' AND l.account_id = 2"
assert transform_placar_sql(sql_com_alias) == \
    "SELECT COUNT(*) FROM bi_leads l WHERE l.account_id = 2", transform_placar_sql(sql_com_alias)

# caso real: sem alias (card 47, conforme doc historico)
sql_sem_alias = "SELECT COUNT(*) FROM leads WHERE source IS DISTINCT FROM 'calculo-advbox' AND account_id = 2"
assert transform_placar_sql(sql_sem_alias) == \
    "SELECT COUNT(*) FROM bi_leads WHERE account_id = 2", transform_placar_sql(sql_sem_alias)

# caso limite: predicado e a UNICA condicao do WHERE (sem AND de nenhum lado)
sql_sozinho = "SELECT COUNT(*) FROM leads l WHERE l.source IS DISTINCT FROM 'calculo-advbox'"
assert transform_placar_sql(sql_sozinho) == \
    "SELECT COUNT(*) FROM bi_leads l WHERE TRUE", transform_placar_sql(sql_sozinho)

# ja aplicado (idempotente): sem 'leads'/'calculo-advbox' -> sql intocado
sql_ja_ok = "SELECT COUNT(*) FROM bi_leads l WHERE l.account_id = 2"
assert transform_placar_sql(sql_ja_ok) == sql_ja_ok

print("OK — 4/4 casos passaram")
