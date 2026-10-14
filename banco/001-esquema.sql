-- =====================================================================
-- RACHA DA SEGUNDA - esquema do banco (Supabase, plano gratuito)
-- Como usar: Supabase > SQL Editor > New query > colar tudo > Run.
-- Seguro para rodar uma vez em um projeto novo.
-- Fuso fixo: America/Fortaleza. Todo horario de regra vem do servidor.
-- =====================================================================

-- ---------- TABELAS ----------

create table public.jogadores (
  id uuid primary key default gen_random_uuid(),
  auth_id uuid unique references auth.users(id) on delete set null,
  nome text not null check (char_length(trim(nome)) between 2 and 40),
  idade int check (idade between 10 and 90),
  posicao text check (posicao in ('ZAG','LAT','VOL','MEI','ATA')),
  is_admin boolean not null default false,
  banido boolean not null default false,
  estrelas numeric(3,2) not null default 3.00 check (estrelas between 0.5 and 5),
  convite text unique,               -- preenchido ate o jogador resgatar
  criado_em timestamptz not null default now()
);

create table public.notas (          -- uma nota por admin por jogador
  jogador_id uuid not null references public.jogadores(id) on delete cascade,
  admin_id uuid not null references public.jogadores(id) on delete cascade,
  valor numeric(2,1) not null check (valor between 0.5 and 5 and mod(valor * 2, 1) = 0),
  atualizado_em timestamptz not null default now(),
  primary key (jogador_id, admin_id)
);

create table public.rachas (
  id uuid primary key default gen_random_uuid(),
  criador_id uuid references public.jogadores(id) on delete set null,
  inicio timestamptz not null,       -- horario do jogo
  abre_em timestamptz not null,      -- quando a lista aceita nomes
  vagas int not null default 12 check (vagas between 2 and 40),
  semanal boolean not null default false,
  cancelado boolean not null default false,
  criado_em timestamptz not null default now()
);
create unique index rachas_semanal_unico on public.rachas (inicio) where semanal;

create table public.inscricoes (     -- nada e apagado: sair = preencher saiu_em
  id uuid primary key default gen_random_uuid(),
  racha_id uuid not null references public.rachas(id) on delete cascade,
  jogador_id uuid not null references public.jogadores(id) on delete cascade,
  ordem int not null,
  entrou_em timestamptz not null default clock_timestamp(),
  garantida boolean not null default false,   -- vaga de quem puxou o racha apos a abertura
  saiu_em timestamptz,
  saiu_por uuid references public.jogadores(id)
);
create unique index inscricoes_ativa_unica on public.inscricoes (racha_id, jogador_id) where saiu_em is null;
create unique index inscricoes_ordem_unica on public.inscricoes (racha_id, ordem);

create table public.sessoes (        -- uma sessao ativa por jogador
  jogador_id uuid primary key references public.jogadores(id) on delete cascade,
  token text not null,
  atualizado_em timestamptz not null default now()
);

create table public.sessoes_log (    -- historico de trocas de aparelho
  id bigint generated always as identity primary key,
  jogador_id uuid not null references public.jogadores(id) on delete cascade,
  em timestamptz not null default now()
);

create table public.sorteios (
  id uuid primary key default gen_random_uuid(),
  racha_id uuid not null references public.rachas(id) on delete cascade,
  time_a uuid[] not null,
  time_b uuid[] not null,
  soma_a numeric not null,
  soma_b numeric not null,
  criado_por uuid references public.jogadores(id),
  criado_em timestamptz not null default now()
);

-- ---------- FUNCOES AUXILIARES ----------

create function public.meu_jogador() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.jogadores where auth_id = auth.uid() and not banido
$$;

create function public.eh_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.jogadores where auth_id = auth.uid() and not banido), false)
$$;

create function public.sessao_valida(p_jogador uuid, p_token text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sessoes where jogador_id = p_jogador and token = p_token)
$$;

-- Abertura padrao: 12h (Fortaleza) do dia anterior ao jogo
create function public.abertura_padrao(p_inicio timestamptz) returns timestamptz
language sql immutable as $$
  select (((p_inicio at time zone 'America/Fortaleza')::date - 1) + time '12:00') at time zone 'America/Fortaleza'
$$;

-- ---------- LOGIN, CONVITE E SESSAO ----------

create function public.resgatar_convite(p_codigo text, p_idade int, p_posicao text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from jogadores where auth_id = auth.uid()) then
    raise exception 'Esta conta já está vinculada a um jogador.';
  end if;
  update jogadores
     set auth_id = auth.uid(), convite = null,
         idade = coalesce(p_idade, idade), posicao = coalesce(p_posicao, posicao)
   where convite = upper(trim(p_codigo)) and auth_id is null
   returning id into v_id;
  if v_id is null then raise exception 'Convite inválido ou já usado.'; end if;
  return v_id;
end $$;

create function public.registrar_sessao(p_token text) returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := public.meu_jogador();
begin
  if v is null then raise exception 'Conta não vinculada ou banida.'; end if;
  insert into sessoes (jogador_id, token) values (v, p_token)
  on conflict (jogador_id) do update set token = excluded.token, atualizado_em = now()
  where sessoes.token <> excluded.token;
  if found then insert into sessoes_log (jogador_id) values (v); end if;
end $$;

create function public.sessao_ativa(p_token text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.sessoes s join public.jogadores j on j.id = s.jogador_id
    where j.auth_id = auth.uid() and not j.banido and s.token = p_token)
$$;

-- ---------- LISTA ----------

create function public.entrar_na_lista(p_racha uuid, p_sessao text) returns int
language plpgsql security definer set search_path = public as $$
declare v_j uuid := public.meu_jogador(); r public.rachas; v_ordem int;
begin
  if v_j is null then raise exception 'Conta não vinculada ou banida.'; end if;
  if not public.sessao_valida(v_j, p_sessao) then
    raise exception 'Sessão encerrada: você entrou em outro aparelho.';
  end if;
  select * into r from rachas where id = p_racha for update;  -- trava: fila em ordem
  if not found or r.cancelado then raise exception 'Racha não encontrado ou cancelado.'; end if;
  if now() < r.abre_em then raise exception 'A lista ainda não abriu.'; end if;
  if now() > r.inicio + interval '3 hours' then raise exception 'Este racha já passou.'; end if;
  if exists (select 1 from inscricoes where racha_id = p_racha and jogador_id = v_j and saiu_em is null) then
    raise exception 'Seu nome já está na lista.';
  end if;
  select coalesce(max(ordem), 0) + 1 into v_ordem from inscricoes where racha_id = p_racha;
  insert into inscricoes (racha_id, jogador_id, ordem) values (p_racha, v_j, v_ordem);
  return v_ordem;
end $$;

create function public.sair_da_lista(p_racha uuid, p_sessao text) returns void
language plpgsql security definer set search_path = public as $$
declare v_j uuid := public.meu_jogador();
begin
  if v_j is null then raise exception 'Conta não vinculada ou banida.'; end if;
  if not public.sessao_valida(v_j, p_sessao) then
    raise exception 'Sessão encerrada: você entrou em outro aparelho.';
  end if;
  update inscricoes set saiu_em = clock_timestamp(), saiu_por = v_j
   where racha_id = p_racha and jogador_id = v_j and saiu_em is null;
  if not found then raise exception 'Seu nome não está na lista.'; end if;
end $$;

-- Qualquer jogador pode puxar um racha.
-- Abre no mais tarde entre "agora" e "12h do dia anterior ao jogo".
-- Se puxou depois das 12h do dia anterior, a vaga dele ja fica garantida (1o nome).
create function public.puxar_racha(p_inicio timestamptz, p_sessao text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_j uuid := public.meu_jogador(); v_padrao timestamptz; v_abre timestamptz; v_id uuid; v_abertos int;
begin
  if v_j is null then raise exception 'Conta não vinculada ou banida.'; end if;
  if not public.sessao_valida(v_j, p_sessao) then
    raise exception 'Sessão encerrada: você entrou em outro aparelho.';
  end if;
  if p_inicio <= now() then raise exception 'Escolha uma data e hora futuras.'; end if;
  select count(*) into v_abertos from rachas
   where criador_id = v_j and not cancelado and not semanal and inicio > now();
  if v_abertos >= 2 then raise exception 'Você já tem 2 rachas puxados em aberto.'; end if;
  v_padrao := public.abertura_padrao(p_inicio);
  v_abre := greatest(now(), v_padrao);
  insert into rachas (criador_id, inicio, abre_em) values (v_j, p_inicio, v_abre) returning id into v_id;
  if now() >= v_padrao then
    insert into inscricoes (racha_id, jogador_id, ordem, garantida) values (v_id, v_j, 1, true);
  end if;
  return v_id;
end $$;

-- Racha fixo de segunda 19h (Fortaleza). Chamada todo dia pelo pg_cron.
create function public.criar_racha_semanal() returns void
language plpgsql security definer set search_path = public as $$
declare v_local timestamp; v_inicio timestamptz;
begin
  v_local := date_trunc('week', now() at time zone 'America/Fortaleza') + interval '19 hours';
  if v_local <= (now() at time zone 'America/Fortaleza') then v_local := v_local + interval '7 days'; end if;
  v_inicio := v_local at time zone 'America/Fortaleza';
  insert into rachas (inicio, abre_em, semanal)
  values (v_inicio, public.abertura_padrao(v_inicio), true)
  on conflict do nothing;
end $$;

-- ---------- LEITURA (views com so o necessario) ----------

create view public.jogadores_publicos as
  select id, nome, posicao, estrelas from public.jogadores where auth_id is not null and not banido;

create view public.lista_racha as
  select i.racha_id, i.jogador_id, j.nome, j.posicao, j.estrelas, i.entrou_em, i.garantida,
         row_number() over (partition by i.racha_id order by i.ordem) as vaga,
         row_number() over (partition by i.racha_id order by i.ordem) <= r.vagas as titular
    from public.inscricoes i
    join public.jogadores j on j.id = i.jogador_id
    join public.rachas r on r.id = i.racha_id
   where i.saiu_em is null;

-- ---------- ADMIN ----------

create function public.admin_criar_jogador(p_nome text, p_posicao text default null, p_admin boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare v_cod text;
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  insert into jogadores (nome, posicao, is_admin, convite)
  values (trim(p_nome), p_posicao, p_admin, upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)))
  returning convite into v_cod;
  return v_cod;
end $$;

create function public.admin_novo_convite(p_jogador uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_cod text;
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  if p_jogador = public.meu_jogador() then raise exception 'Peça a outro admin para refazer o seu convite.'; end if;
  update jogadores set auth_id = null,
         convite = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
   where id = p_jogador returning convite into v_cod;
  if v_cod is null then raise exception 'Jogador não encontrado.'; end if;
  delete from sessoes where jogador_id = p_jogador;
  return v_cod;
end $$;

create function public.admin_dar_nota(p_jogador uuid, p_valor numeric) returns void
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := public.meu_jogador();
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  insert into notas (jogador_id, admin_id, valor) values (p_jogador, v_admin, p_valor)
  on conflict (jogador_id, admin_id) do update set valor = excluded.valor, atualizado_em = now();
  update jogadores set estrelas = (select round(avg(valor), 2) from notas where jogador_id = p_jogador)
   where id = p_jogador;
end $$;

create function public.admin_banir(p_jogador uuid, p_banir boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := public.meu_jogador();
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  if p_jogador = v_admin then raise exception 'Você não pode banir a si mesmo.'; end if;
  update jogadores set banido = p_banir where id = p_jogador;
  if p_banir then
    update inscricoes set saiu_em = clock_timestamp(), saiu_por = v_admin
     where jogador_id = p_jogador and saiu_em is null
       and racha_id in (select id from rachas where inicio > now());
    delete from sessoes where jogador_id = p_jogador;
  end if;
end $$;

create function public.admin_promover(p_jogador uuid, p_admin boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  if p_jogador = public.meu_jogador() then raise exception 'Você não pode alterar o seu próprio perfil.'; end if;
  update jogadores set is_admin = p_admin where id = p_jogador;
end $$;

create function public.admin_cancelar_racha(p_racha uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  update rachas set cancelado = true where id = p_racha;
end $$;

create function public.admin_remover_da_lista(p_racha uuid, p_jogador uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  update inscricoes set saiu_em = clock_timestamp(), saiu_por = public.meu_jogador()
   where racha_id = p_racha and jogador_id = p_jogador and saiu_em is null;
end $$;

create function public.admin_adicionar_na_lista(p_racha uuid, p_jogador uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_ordem int;
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  perform 1 from rachas where id = p_racha and not cancelado for update;
  if not found then raise exception 'Racha não encontrado ou cancelado.'; end if;
  if not exists (select 1 from jogadores where id = p_jogador and not banido) then
    raise exception 'Jogador não encontrado ou banido.';
  end if;
  if exists (select 1 from inscricoes where racha_id = p_racha and jogador_id = p_jogador and saiu_em is null) then
    raise exception 'Já está na lista.';
  end if;
  select coalesce(max(ordem), 0) + 1 into v_ordem from inscricoes where racha_id = p_racha;
  insert into inscricoes (racha_id, jogador_id, ordem) values (p_racha, p_jogador, v_ordem);
end $$;

-- Sorteio: testa TODAS as divisoes em dois times iguais e escolhe uma de menor
-- diferenca de estrelas (sorteia entre as empatadas). Resultado fica salvo.
create function public.admin_sortear(p_racha uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  ids uuid[]; est numeric[]; n int; m int; i int; c int; s numeric; tot numeric; d numeric;
  melhor numeric := 1e9; melhores int[] := '{}'; esc int;
  ta uuid[] := '{}'; tb uuid[] := '{}'; sa numeric := 0; sb numeric := 0; v_id uuid;
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  select array_agg(l.jogador_id order by l.vaga), array_agg(l.estrelas order by l.vaga)
    into ids, est from public.lista_racha l where l.racha_id = p_racha and l.titular;
  n := coalesce(array_length(ids, 1), 0);
  if n < 4 or n > 16 or n % 2 <> 0 then
    raise exception 'Preciso de um número par de titulares (4 a 16). Há % na lista.', n;
  end if;
  tot := (select sum(e) from unnest(est) e);
  for m in 1..((1 << n) - 1) by 2 loop
    c := 0; s := 0;
    for i in 0..n - 1 loop
      if ((m >> i) & 1) = 1 then c := c + 1; s := s + est[i + 1]; end if;
    end loop;
    if c <> n / 2 then continue; end if;
    d := abs(2 * s - tot);
    if d < melhor then melhor := d; melhores := array[m];
    elsif d = melhor then melhores := melhores || m;
    end if;
  end loop;
  esc := melhores[1 + floor(random() * array_length(melhores, 1))::int];
  for i in 0..n - 1 loop
    if ((esc >> i) & 1) = 1 then ta := ta || ids[i + 1]; sa := sa + est[i + 1];
    else tb := tb || ids[i + 1]; sb := sb + est[i + 1]; end if;
  end loop;
  insert into sorteios (racha_id, time_a, time_b, soma_a, soma_b, criado_por)
  values (p_racha, ta, tb, sa, sb, public.meu_jogador()) returning id into v_id;
  return v_id;
end $$;

-- ---------- SEGURANCA: NEGAR TUDO, LIBERAR O MINIMO ----------

alter table public.jogadores    enable row level security;
alter table public.notas        enable row level security;
alter table public.rachas       enable row level security;
alter table public.inscricoes   enable row level security;
alter table public.sessoes      enable row level security;
alter table public.sessoes_log  enable row level security;
alter table public.sorteios     enable row level security;

create policy jogadores_proprio on public.jogadores for select to authenticated using (auth_id = auth.uid());
create policy jogadores_admin   on public.jogadores for select to authenticated using (public.eh_admin());
create policy notas_admin       on public.notas for select to authenticated using (public.eh_admin());
create policy sessoes_log_admin on public.sessoes_log for select to authenticated using (public.eh_admin());
create policy rachas_ler        on public.rachas for select to authenticated using (public.meu_jogador() is not null);
create policy inscricoes_ler    on public.inscricoes for select to authenticated using (public.meu_jogador() is not null);
create policy sorteios_ler      on public.sorteios for select to authenticated using (public.meu_jogador() is not null);
-- sessoes: sem policy (so as funcoes acessam)

-- Nenhuma escrita direta: tudo passa pelas funcoes acima.
revoke all on all tables in schema public from anon;
revoke insert, update, delete, truncate on all tables in schema public from authenticated;
grant select on public.jogadores_publicos, public.lista_racha to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.sessao_valida(uuid, text) from authenticated;
revoke execute on function public.criar_racha_semanal() from authenticated;

-- ---------- AUTOMACOES OPCIONAIS ----------

do $$ begin   -- lista em tempo real
  alter publication supabase_realtime add table public.inscricoes;
exception when others then raise notice 'Realtime: ative a tabela inscricoes em Database > Replication.';
end $$;

do $$ begin   -- cria o racha de segunda sozinho, todo dia as 06:00 UTC
  create extension if not exists pg_cron;
  perform cron.schedule('racha-semanal', '0 6 * * *', 'select public.criar_racha_semanal()');
exception when others then
  raise notice 'pg_cron indisponivel: ative em Database > Extensions e rode o agendamento depois.';
end $$;

-- =====================================================================
-- DEPOIS DE RODAR (um por vez):
-- 1) Primeiro admin (troque o nome) - copie o codigo que aparecer:
--    insert into public.jogadores (nome, posicao, is_admin, convite)
--    values ('SEU NOME', 'MEI', true, upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)))
--    returning convite;
-- 2) Primeiro racha de segunda:
--    select public.criar_racha_semanal();
-- =====================================================================
