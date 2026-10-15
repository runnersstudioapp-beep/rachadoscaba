-- Permite que cada jogador inclua uma pessoa em cada racha avulso.
-- Rode no SQL Editor do Supabase depois das migrações anteriores.

alter table public.inscricoes
  add column if not exists adicionado_por uuid references public.jogadores(id);

drop index if exists public.inscricoes_um_extra_por_conta_racha;
create unique index inscricoes_um_extra_por_conta_racha
  on public.inscricoes (racha_id, adicionado_por)
  where adicionado_por is not null and saiu_em is null;

create or replace view public.lista_racha as
  select i.racha_id, i.jogador_id, j.nome, j.posicao, j.estrelas, i.entrou_em, i.garantida,
         row_number() over (partition by i.racha_id order by i.ordem) as vaga,
         row_number() over (partition by i.racha_id order by i.ordem) <= r.vagas as titular,
         i.adicionado_por
    from public.inscricoes i
    join public.jogadores j on j.id = i.jogador_id
    join public.rachas r on r.id = i.racha_id
   where i.saiu_em is null;

drop function if exists public.adicionar_jogador_extra(uuid, uuid, text);
drop function if exists public.remover_jogador_extra(uuid, uuid, text);

create function public.adicionar_jogador_extra(
  p_racha uuid,
  p_jogador uuid,
  p_sessao text
) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_j uuid := public.meu_jogador();
  v_racha public.rachas;
  v_ordem int;
begin
  if v_j is null then raise exception 'Conta não vinculada ou banida.'; end if;
  if not public.sessao_valida(v_j, p_sessao) then
    raise exception 'Sessão encerrada: você entrou em outro aparelho.';
  end if;

  select * into v_racha from public.rachas where id = p_racha for update;
  if not found or v_racha.cancelado then raise exception 'Racha não encontrado ou cancelado.'; end if;
  if v_racha.semanal then raise exception 'Só é permitido incluir outro jogador em rachas avulsos.'; end if;
  if now() < v_racha.abre_em then raise exception 'A lista ainda não abriu.'; end if;
  if now() > v_racha.inicio + interval '3 hours' then raise exception 'Este racha já passou.'; end if;
  if p_jogador = v_j then raise exception 'Escolha outro jogador do grupo.'; end if;
  if not exists (select 1 from public.inscricoes where racha_id = p_racha and jogador_id = v_j and saiu_em is null) then
    raise exception 'Entre na lista com seu nome antes de adicionar outro jogador.';
  end if;
  if exists (select 1 from public.inscricoes where racha_id = p_racha and adicionado_por = v_j and saiu_em is null) then
    raise exception 'Você já tem um jogador extra ativo neste racha.';
  end if;
  if not exists (
    select 1 from public.jogadores
     where id = p_jogador and auth_id is not null and not banido
  ) then raise exception 'Jogador não encontrado, sem conta ativa ou banido.'; end if;
  if exists (select 1 from public.inscricoes where racha_id = p_racha and jogador_id = p_jogador and saiu_em is null) then
    raise exception 'Esse jogador já está na lista.';
  end if;

  select coalesce(max(ordem), 0) + 1 into v_ordem
    from public.inscricoes where racha_id = p_racha;
  insert into public.inscricoes (racha_id, jogador_id, ordem, adicionado_por)
  values (p_racha, p_jogador, v_ordem, v_j);
  return v_ordem;
end $$;

create function public.remover_jogador_extra(
  p_racha uuid,
  p_jogador uuid,
  p_sessao text
) returns void
language plpgsql security definer set search_path = public as $$
declare v_j uuid := public.meu_jogador();
begin
  if v_j is null then raise exception 'Conta não vinculada ou banida.'; end if;
  if not public.sessao_valida(v_j, p_sessao) then
    raise exception 'Sessão encerrada: você entrou em outro aparelho.';
  end if;
  if not exists (select 1 from public.rachas where id = p_racha and not semanal) then
    raise exception 'Só é permitido remover o jogador extra de um racha avulso.';
  end if;
  update public.inscricoes
     set saiu_em = clock_timestamp(), saiu_por = v_j
   where racha_id = p_racha and jogador_id = p_jogador
     and adicionado_por = v_j and saiu_em is null;
  if not found then raise exception 'Jogador extra não encontrado na lista.'; end if;
end $$;

revoke all on function public.adicionar_jogador_extra(uuid, uuid, text) from public, anon;
grant execute on function public.adicionar_jogador_extra(uuid, uuid, text) to authenticated;
revoke all on function public.remover_jogador_extra(uuid, uuid, text) from public, anon;
grant execute on function public.remover_jogador_extra(uuid, uuid, text) to authenticated;

grant select on public.lista_racha to authenticated;
