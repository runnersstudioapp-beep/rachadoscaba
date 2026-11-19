-- Corrige estrelas influenciadas por notas de admins anteriores à restrição.
-- Rode depois das migrações 001 a 009.

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
  update public.jogadores set estrelas = p_valor where id = p_jogador;
  if not found then raise exception 'Jogador nao encontrado.'; end if;
end $$;

revoke all on function public.admin_dar_nota(uuid,numeric) from public, anon;
grant execute on function public.admin_dar_nota(uuid,numeric) to authenticated;

-- Para quem já recebeu nota do master, aplica a nota dele. Os demais voltam
-- ao padrão até serem avaliados pelo master.
update public.jogadores j
   set estrelas = coalesce((
     select n.valor
       from public.notas n
       join public.jogadores a on a.id = n.admin_id
      where n.jogador_id = j.id and a.is_admin and a.is_admin_master
      order by n.atualizado_em desc
      limit 1
   ), 3.00);
