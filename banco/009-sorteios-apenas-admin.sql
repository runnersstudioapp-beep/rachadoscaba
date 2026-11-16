-- Somente admins podem consultar os times sorteados.
drop policy if exists sorteios_ler on public.sorteios;
create policy sorteios_ler on public.sorteios
  for select to authenticated using (public.eh_admin());

-- A funcao ja verifica eh_admin(); reaplica a protecao para projetos que
-- ainda usam a definicao inicial e mantem execucao apenas para autenticados.
revoke all on function public.admin_sortear(uuid) from public, anon;
grant execute on function public.admin_sortear(uuid) to authenticated;
