Você é um engenheiro de dados sênior. Temos 4 schemas OLTP de empresas de locação de veículos que precisam ser integrados em um único Data Warehouse dimensional.

## Estrutura do repositório
- 01_fontes/grupo_mhscardoso/   → nosso schema (create_table.sql)
- 01_fontes/grupo_tadeupires/   → schema do grupo Tadeu (schema.sql)
- 01_fontes/grupo_gupessanha/   → schema do grupo Gustavo (schema.sql)
- 01_fontes/grupo_valviesse/    → schema do grupo Valviesse (01_create_table.sql + 02_constraints.sql)
- 02_dw_schema/create_dw.sql   → modelo estrela já criado (dimensões e fatos)

## Divergências críticas que você deve tratar no ETL

1. **mhscardoso (nosso)**: reserva não tem patio_retirada nem grupo_id diretamente — passa por CentroCusto. Locação referencia Vaga, não Pátio diretamente. Cliente não tem cidade_origem. Veículo não tem marca nem mecanizacao explícita.

2. **tadeupires**: schema mais completo e compatível. grupo_veiculo, patio, cliente com cidade, reserva e locação com pátios diretos. Movimentação via tabela movimentacao_patio.

3. **gupessanha**: muito compatível. grupo, patio com endereco e capacidade_vagas. Reserva e locação com pátios diretos. Não tem tabela de movimentação explícita — derivar da locacao (patio_retirada_id → patio_devolucao_id).

4. **valviesse**: também compatível. GRUPO_VEICULO, PATIO com localizacao e empresa. Reserva e locação com pátios diretos. Tem MOVIMENTACAO_PATIO explícita.

## Modelo do DW (02_dw_schema/create_dw.sql)
Esquema estrela com schema 'dw':
- dim_tempo, dim_patio, dim_cliente, dim_grupo, dim_veiculo
- fato_locacao, fato_reserva, fato_movimentacao_patio

## Sua tarefa — gere os seguintes arquivos em ordem:

### 03_etl/01_extracao/
Gere um arquivo SQL por grupo. Cada arquivo cria tabelas no schema 'staging' copiando exatamente os dados da fonte, sem transformação. Use INSERT INTO staging.X SELECT ... FROM fonte.X. Adicione comentário com o tempo de acionamento recomendado (cron).

### 03_etl/02_transformacao/transform_staging.sql
Crie tabelas staging.std_* (padronizadas) resolvendo:
- tipo_cliente → sempre 'PF' ou 'PJ'
- mecanizacao → sempre 'MANUAL' ou 'AUTOMATICO'
- Para mhscardoso: resolva o patio via JOIN Locacao→Vaga→Patio e o grupo via JOIN Reserva→CentroCusto (se não houver grupo direto, use NULL com comentário)
- Para gupessanha: gere movimentacao derivada de locacao (cada locacao concluída = 1 movimentação origem→destino)
- Adicione coluna id_sistema_origem em todas as tabelas std com o valor literal do grupo (ex: 'GRUPO_MHSCARDOSO')

### 03_etl/03_carga/
- load_dimensoes.sql: INSERT nas dim_* a partir das std_*, com UPSERT (ON CONFLICT DO NOTHING ou UPDATE)
- load_fatos.sql: INSERT nas fato_* fazendo JOIN com as dimensões para resolver as surrogate keys (sk_*)

### 04_relatorios/
- rel_controle_patio.sql → veículos no pátio por grupo e origem (frota própria vs associada)
- rel_controle_locacoes.sql → locações ativas por grupo, tempo restante de devolução
- rel_controle_reservas.sql → reservas por grupo, pátio, cidade do cliente, antecedência
- rel_grupos_mais_alugados.sql → ranking de grupos por total de locações, cruzado com cidade do cliente
- matriz_markov.sql → para cada pátio de origem, percentual de veículos entregues em cada pátio de destino (use fato_movimentacao_patio)

## Regras gerais
- Todos os scripts em PostgreSQL (ANSI SQL:1999+)
- Cada arquivo começa com um cabeçalho comentado com nome do arquivo e descrição
- Não use TRUNCATE nas cargas — use UPSERT ou INSERT ... ON CONFLICT
- Leia os arquivos fonte antes de escrever qualquer SQL para garantir que os nomes de tabelas e colunas estão corretos

Comece lendo todos os arquivos em 01_fontes/ e 02_dw_schema/, depois execute as tarefas na ordem acima.