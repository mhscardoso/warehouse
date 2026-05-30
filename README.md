# BigData | Criação do Data Warehouse


Trabalho desenvolvido pelos alunos da UFRJ.

Período: 2026.1

Cadeira: BigData

Integrantes:                                    

```
Lucas Garcia Santiago de Abreu          - DRE: 121039536
Matheus Henrique Sant’ Anna Cardoso     - DRE: 121073530
Patrick Mucio Rodrigues Pereira         - DRE: 120055979
```

## Link para o PDF com o relatório do que foi feito

https://docs.google.com/document/d/1kl8n7E8uOt-68rjTjrOL9Yz9G_ie7nokEPJ7WDQLPUM/edit?tab=t.0

## Fontes dos outros grupos e nosso

É preciso realizar o git clone dos outros projetos na pasta 01_fontes:

1. Crie uma pasta ```01_fontes``` na raiz do projeto.
2. Execute os códigos abaixo para entrar na pasta e clonar os repositórios:

Repare que o primeiro ```https://github.com/mhscardoso/bigdata``` é o nosso grupo.

```sh
cd 01_fontes
git clone https://github.com/mhscardoso/bigdata
git clone https://github.com/valviessejoao/mae016-bdd-dwh-projeto1
git clone https://github.com/gupessanha/locadora-dw-parte1
git clone https://github.com/tadeupires21-sketch/locadora-db
```

## Ordem de execução

1. 02_dw_schema/create_dw_v2.sql
2. 03_etl/01_extracao/extract_grupo_*.sql  (qualquer ordem)
3. 03_etl/02_transformacao/transform_staging.sql
4. 03_etl/03_carga/load_dimensoes.sql
5. 03_etl/03_carga/load_fatos.sql
6. 04_relatorios/*.sql

## Limitações conhecidas
- sk_grupo em fato_reserva é NULL — extract não preservou id_grupo na staging de reserva
- dt_devolucao_prevista NULL em mhscardoso e valviesse usa sentinela 99991231
- ~5% das locações descartadas por valor_diaria irresolvível