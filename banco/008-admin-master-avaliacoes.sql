-- Somente o admin master define estrelas e velocidade.
-- Rode depois das migracoes 001 a 007.

alter table public.jogadores
  add column if not exists is_admin_master boolean not null default false;

create or replace function public.eh_admin_master() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select is_admin_master and is_admin
      from public.jogadores
     where auth_id = auth.uid() and not banido
  ), false)
$$;

create or replace function public.admin_dar_nota(p_jogador uuid, p_valor numeric) returns void
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := public.meu_jogador();
begin
  if not public.eh_admin_master() then raise exception 'Apenas o admin master pode avaliar jogadores.'; end if;
  if p_valor not between 0.5 and 5 or mod(p_valor * 2, 1) <> 0 then
    raise exception 'A nota deve ser de 0,5 a 5, em intervalos de 0,5.';
  end if;
  insert into public.notas (jogador_id, admin_id, valor) values (p_jogador, v_admin, p_valor)
  on conflict (jogador_id, admin_id) do update set valor = excluded.valor, atualizado_em = now();
  update public.jogadores
     set estrelas = p_valor
   where id = p_jogador;
  if not found then raise exception 'Jogador nao encontrado.'; end if;
end $$;

create or replace function public.admin_definir_velocidade(p_jogador uuid, p_velocidade int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_admin_master() then raise exception 'Apenas o admin master pode definir velocidade.'; end if;
  if p_velocidade not between 1 and 3 then raise exception 'Velocidade deve ser 1, 2 ou 3.'; end if;
  update public.jogadores set velocidade = p_velocidade where id = p_jogador;
  if not found then raise exception 'Jogador nao encontrado.'; end if;
end $$;

create or replace function public.admin_listar_velocidades()
returns table(jogador_id uuid, velocidade smallint)
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_admin_master() then raise exception 'Apenas o admin master pode consultar velocidades.'; end if;
  return query select j.id,j.velocidade from public.jogadores j order by j.nome;
end $$;

revoke all on function public.eh_admin_master() from public, anon;
grant execute on function public.eh_admin_master() to authenticated;
revoke all on function public.admin_dar_nota(uuid,numeric) from public, anon;
grant execute on function public.admin_dar_nota(uuid,numeric) to authenticated;
revoke all on function public.admin_definir_velocidade(uuid,int) from public, anon;
grant execute on function public.admin_definir_velocidade(uuid,int) to authenticated;
revoke all on function public.admin_listar_velocidades() from public, anon;
grant execute on function public.admin_listar_velocidades() to authenticated;

-- Permite identificar o papel no cliente; velocidade continua fora da leitura direta.
grant select(is_admin_master) on public.jogadores to authenticated;

-- Define a conta escolhida como admin master.
update public.jogadores
   set is_admin = true, is_admin_master = true
 where auth_id = '289611c9-b641-4681-8d27-f7b8894abf50';
