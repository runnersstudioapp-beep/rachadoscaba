# Racha da Segunda

App (PWA) para organizar o racha de futebol: lista de 12 titulares com abertura automática,
suplentes, rachas puxados em outros dias, ranking por estrelas e sorteio equilibrado de times.

- **Front-end:** um único `index.html` (sem build), em `docs/`
- **Banco e login:** Supabase (plano gratuito)
- **Hospedagem:** GitHub Pages (pasta `docs/`)

## Estrutura

```
docs/                  o app (é isso que vai ao ar)
  index.html           telas e lógica
  manifest.webmanifest instalação como app
  sw.js                service worker
  icon-*.png           ícones
banco/                 SQL do Supabase, em ordem
  001-esquema.sql      tabelas, regras de acesso e funções (rodar UMA vez)
  002-primeiro-admin-e-racha.sql
.vscode/               configurações do VS Code
```

## Rodar no computador

1. Abra esta pasta no VS Code e instale a extensão **Live Server** (o VS Code sugere).
2. Clique em **Go Live** no canto inferior direito. O app abre em `http://127.0.0.1:5500`.
3. Ele usa o Supabase real, então login, lista e sorteio funcionam normalmente.

## Publicar (GitHub Pages)

1. Crie um repositório no GitHub (público, para o Pages gratuito) e envie esta pasta.
2. No repositório: **Settings → Pages → Build and deployment**: *Deploy from a branch*,
   branch `main`, pasta **/docs**.
3. O endereço sai em alguns minutos. Cada envio de alteração (`git push`) atualiza o app.

## Banco de dados

- O `001-esquema.sql` **já foi aplicado** no projeto. **Não rode de novo** (dá erro "already exists").
- Mudanças futuras: crie arquivos novos (`003-...sql`, `004-...sql`) só com a alteração
  e rode-os no SQL Editor do Supabase. Mantenha-os aqui para ter o histórico.
- Supabase: Authentication → Providers → Email → **desligar "Confirm email"**.
- Recomendado: ativar a extensão `pg_cron` (Database → Extensions) e agendar a criação do racha de segunda:
  `select cron.schedule('racha-semanal','0 6 * * *','select public.criar_racha_semanal()');`

## Regras do racha (resumo)

- Fixo: segunda 19h. A lista abre no domingo às 12h (fuso de Fortaleza, horário do servidor).
- 12 titulares; do 13º em diante são suplentes e sobem quando alguém sai.
- Qualquer jogador pode puxar um racha em outro dia (máx. 2 abertos por vez). A lista abre às 12h do dia anterior;
  se puxar depois disso, abre na hora e a vaga de quem puxou fica garantida.
- Cadastro só por convite dos admins; uma sessão ativa por jogador (entrar em outro aparelho derruba o anterior).
- Ranking por estrelas (média das notas dos admins). Sorteio testa todas as divisões e escolhe a mais equilibrada.
- Ninguém coloca o nome de terceiros: a entrada na lista só existe para o próprio usuário logado.

## Segurança

- A chave **anon** em `docs/index.html` é pública por design; quem protege os dados são as regras do banco.
- **Nunca** colocar no repositório: chave `service_role`, senha do banco, tokens.

## Próximos passos

Botão do admin para adicionar nome manualmente na lista, tela de trocas de aparelho,
súmula (gols e assistências), card do jogador em imagem, músicas livres de direitos e o mini jogo.
