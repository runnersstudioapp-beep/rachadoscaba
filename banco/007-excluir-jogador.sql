-- Banir agora remove definitivamente o jogador da tabela de jogadores.
-- Rode depois da migracao 006.

-- Estas referencias nao devem impedir a exclusao de um jogador.
alter table public.inscricoes
  drop constraint if exists inscricoes_saiu_por_fkey;
alter table public.inscricoes
  add constraint inscricoes_saiu_por_fkey
  foreign key (saiu_por) references public.jogadores(id) on delete set null;

alter table public.sorteios
  drop constraint if exists sorteios_criado_por_fkey;
alter table public.sorteios
  add constraint sorteios_criado_por_fkey
  foreign key (criado_por) references public.jogadores(id) on delete set null;

create or replace function public.admin_excluir_jogador(p_jogador uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := public.meu_jogador();
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  if p_jogador = v_admin then raise exception 'Voce nao pode excluir a si mesmo.'; end if;

  perform 1 from public.jogadores where id = p_jogador for update;
  if not found then raise exception 'Jogador nao encontrado.'; end if;

  -- Gera eventos de remocao antes das inscricoes dependentes serem apagadas.
  update public.inscricoes
     set saiu_em = clock_timestamp(), saiu_por = v_admin
   where jogador_id = p_jogador and saiu_em is null;

  -- Recalcula as medias dos jogadores que perderao as notas deste admin.
  update public.jogadores j
     set estrelas = coalesce((
       select round(avg(n.valor), 2)
         from public.notas n
        where n.jogador_id = j.id and n.admin_id <> p_jogador
     ), 3.00)
   where j.id <> p_jogador
     and exists (select 1 from public.notas n where n.jogador_id = j.id and n.admin_id = p_jogador);

  delete from public.jogadores where id = p_jogador;
end $$;

-- Compatibilidade com clientes antigos: o comando de banir tambem exclui.
create or replace function public.admin_banir(p_jogador uuid, p_banir boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not p_banir then raise exception 'Jogadores excluidos nao podem ser reativados.'; end if;
  perform public.admin_excluir_jogador(p_jogador);
end $$;

revoke all on function public.admin_excluir_jogador(uuid) from public, anon;
grant execute on function public.admin_excluir_jogador(uuid) to authenticated;
revoke all on function public.admin_banir(uuid, boolean) from public, anon;
grant execute on function public.admin_banir(uuid, boolean) to authenticated;

-- Retira os registros ja marcados como banidos e preserva o evento de remocao.
update public.inscricoes
   set saiu_em = clock_timestamp(), saiu_por = null
 where jogador_id in (select id from public.jogadores where banido)
   and saiu_em is null;

update public.jogadores j
   set estrelas = coalesce((
     select round(avg(n.valor), 2)
       from public.notas n
      where n.jogador_id = j.id
        and n.admin_id not in (select id from public.jogadores where banido)
   ), 3.00)
 where not j.banido
   and exists (
     select 1 from public.notas n
      where n.jogador_id = j.id
        and n.admin_id in (select id from public.jogadores where banido)
   );

delete from public.jogadores where banido;
