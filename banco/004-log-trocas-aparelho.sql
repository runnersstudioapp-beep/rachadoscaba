-- Registra identificador local da instalação e user-agent nas trocas de sessão.
-- Rode no SQL Editor do Supabase depois das migrações anteriores.

alter table public.sessoes_log
  add column if not exists instalacao_id text,
  add column if not exists user_agent text;

drop function if exists public.registrar_sessao(text);

create function public.registrar_sessao(p_token text, p_user_agent text) returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := public.meu_jogador();
begin
  if v is null then raise exception 'Conta não vinculada ou banida.'; end if;
  insert into sessoes (jogador_id, token) values (v, p_token)
  on conflict (jogador_id) do update set token = excluded.token, atualizado_em = now()
  where sessoes.token <> excluded.token;
  if found then
    insert into sessoes_log (jogador_id, instalacao_id, user_agent)
    values (v, p_token, left(p_user_agent, 500));
  end if;
end $$;

revoke all on function public.registrar_sessao(text, text) from public, anon;
grant execute on function public.registrar_sessao(text, text) to authenticated;
