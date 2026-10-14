-- Rode depois das migracoes 001 e 002 no SQL Editor do Supabase.
-- No cadastro, o jogador escolhe o nome ao resgatar o convite.
drop function if exists public.resgatar_convite(text, int, text);

create function public.resgatar_convite(
  p_codigo text,
  p_nome text,
  p_idade int,
  p_posicao text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if char_length(trim(coalesce(p_nome, ''))) not between 2 and 40 then
    raise exception 'O nome deve ter entre 2 e 40 caracteres.';
  end if;
  if exists (select 1 from jogadores where auth_id = auth.uid()) then
    raise exception 'Esta conta já está vinculada a um jogador.';
  end if;
  update jogadores
     set auth_id = auth.uid(), convite = null, nome = trim(p_nome),
         idade = coalesce(p_idade, idade), posicao = coalesce(p_posicao, posicao)
   where convite = upper(trim(p_codigo)) and auth_id is null
   returning id into v_id;
  if v_id is null then raise exception 'Convite inválido ou já usado.'; end if;
  return v_id;
end $$;

create function public.atualizar_meu_perfil(
  p_nome text,
  p_idade int,
  p_posicao text
) returns void
language plpgsql security definer set search_path = public as $$
declare v_id uuid := public.meu_jogador();
begin
  if v_id is null then raise exception 'Conta não vinculada ou banida.'; end if;
  if char_length(trim(coalesce(p_nome, ''))) not between 2 and 40 then
    raise exception 'O nome deve ter entre 2 e 40 caracteres.';
  end if;
  if p_idade is not null and p_idade not between 10 and 90 then
    raise exception 'A idade deve estar entre 10 e 90.';
  end if;
  update jogadores
     set nome = trim(p_nome), idade = p_idade, posicao = p_posicao
   where id = v_id and auth_id = auth.uid();
end $$;

revoke all on function public.resgatar_convite(text, text, int, text) from public, anon;
grant execute on function public.resgatar_convite(text, text, int, text) to authenticated;
revoke all on function public.atualizar_meu_perfil(text, int, text) from public, anon;
grant execute on function public.atualizar_meu_perfil(text, int, text) to authenticated;
