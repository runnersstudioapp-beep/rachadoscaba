-- Velocidade individual (admin) e trilha de eventos da lista.
-- Rode no SQL Editor depois das migracoes 001 a 005.

alter table public.jogadores
  add column if not exists velocidade smallint not null default 2
  check (velocidade between 1 and 3);

create or replace function public.admin_definir_velocidade(p_jogador uuid, p_velocidade int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  if p_velocidade not between 1 and 3 then raise exception 'Velocidade deve ser 1, 2 ou 3.'; end if;
  update public.jogadores set velocidade = p_velocidade where id = p_jogador;
  if not found then raise exception 'Jogador nao encontrado.'; end if;
end $$;

create or replace function public.admin_listar_velocidades()
returns table(jogador_id uuid, velocidade smallint)
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  return query select j.id,j.velocidade from public.jogadores j order by j.nome;
end $$;

create table if not exists public.eventos_lista (
  id bigint generated always as identity primary key,
  racha_id uuid not null references public.rachas(id) on delete cascade,
  jogador_id uuid,
  jogador_nome text not null,
  ator_id uuid,
  ator_nome text,
  tipo text not null check (tipo in ('entrou','saiu','removido','extra','adicionado_admin')),
  em timestamptz not null default clock_timestamp(),
  inicio_racha timestamptz not null
);
alter table public.eventos_lista enable row level security;
drop policy if exists eventos_lista_admin on public.eventos_lista;
create policy eventos_lista_admin on public.eventos_lista for select to authenticated using (public.eh_admin());
revoke all on public.eventos_lista from anon, authenticated;
grant select on public.eventos_lista to authenticated;

create or replace function public.registrar_evento_lista() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ator uuid := public.meu_jogador();
  v_tipo text;
  v_jogador text;
  v_ator_nome text;
  v_inicio timestamptz;
begin
  if tg_op = 'INSERT' then
    v_tipo := case when new.adicionado_por is not null then 'extra'
                   when public.eh_admin() and v_ator is distinct from new.jogador_id then 'adicionado_admin'
                   else 'entrou' end;
    v_jogador := (select nome from public.jogadores where id = new.jogador_id);
    v_inicio := (select inicio from public.rachas where id = new.racha_id);
    v_ator_nome := (select nome from public.jogadores where id = v_ator);
    insert into public.eventos_lista(racha_id,jogador_id,jogador_nome,ator_id,ator_nome,tipo,inicio_racha)
    values(new.racha_id,new.jogador_id,coalesce(v_jogador,'Jogador removido'),v_ator,v_ator_nome,v_tipo,v_inicio);
    return new;
  end if;
  if old.saiu_em is null and new.saiu_em is not null then
    v_tipo := case when new.saiu_por = new.jogador_id then 'saiu' else 'removido' end;
    v_jogador := (select nome from public.jogadores where id = new.jogador_id);
    v_inicio := (select inicio from public.rachas where id = new.racha_id);
    v_ator_nome := (select nome from public.jogadores where id = new.saiu_por);
    insert into public.eventos_lista(racha_id,jogador_id,jogador_nome,ator_id,ator_nome,tipo,inicio_racha)
    values(new.racha_id,new.jogador_id,coalesce(v_jogador,'Jogador removido'),new.saiu_por,v_ator_nome,v_tipo,v_inicio);
  end if;
  return new;
end $$;

drop trigger if exists inscricoes_evento_lista on public.inscricoes;
create trigger inscricoes_evento_lista
after insert or update on public.inscricoes
for each row execute function public.registrar_evento_lista();

-- Habilidade segue como criterio principal. Empates sao comparados por rapidos,
-- lentos, soma dos niveis; somente as divisoes ainda empatadas usam acaso.
create or replace function public.admin_sortear(p_racha uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  ids uuid[]; est numeric[]; vel int[]; n int; m int; i int; c int;
  soma_h numeric; total_h numeric; dif_h numeric;
  rap_a int; rap_b int; lent_a int; lent_b int; vel_a int; vel_b int;
  dif_rap int; dif_lent int; dif_vel int;
  melhor_h numeric := 1e9; melhor_rap int := 2147483647;
  melhor_lent int := 2147483647; melhor_vel int := 2147483647;
  melhores int[] := '{}'; esc int; ta uuid[] := '{}'; tb uuid[] := '{}';
  sa numeric := 0; sb numeric := 0; v_id uuid;
begin
  if not public.eh_admin() then raise exception 'Apenas admins.'; end if;
  select array_agg(l.jogador_id order by l.vaga), array_agg(l.estrelas order by l.vaga),
         array_agg(j.velocidade order by l.vaga)
    into ids, est, vel
    from public.lista_racha l join public.jogadores j on j.id=l.jogador_id
    where l.racha_id=p_racha and l.titular;
  n := coalesce(array_length(ids,1),0);
  if n < 4 or n > 16 or n % 2 <> 0 then
    raise exception 'Preciso de um numero par de titulares (4 a 16). Ha % na lista.', n;
  end if;
  total_h := (select sum(e) from unnest(est) e);
  for m in 1..((1 << n)-1) by 2 loop
    c:=0; soma_h:=0; rap_a:=0; lent_a:=0; vel_a:=0;
    for i in 0..n-1 loop
      if ((m >> i)&1)=1 then
        c:=c+1; soma_h:=soma_h+est[i+1]; vel_a:=vel_a+vel[i+1];
        if vel[i+1]=3 then rap_a:=rap_a+1; end if;
        if vel[i+1]=1 then lent_a:=lent_a+1; end if;
      end if;
    end loop;
    if c<>n/2 then continue; end if;
    dif_h:=abs(2*soma_h-total_h);
    rap_b:=0; lent_b:=0; vel_b:=0;
    for i in 1..n loop
      vel_b:=vel_b+vel[i];
      if vel[i]=3 then rap_b:=rap_b+1; end if;
      if vel[i]=1 then lent_b:=lent_b+1; end if;
    end loop;
    rap_b:=rap_b-rap_a; lent_b:=lent_b-lent_a; vel_b:=vel_b-vel_a;
    dif_rap:=abs(rap_a-(rap_a+rap_b));
    dif_lent:=abs(lent_a-(lent_a+lent_b));
    dif_vel:=abs(vel_a-vel_b);
    if (dif_h,dif_rap,dif_lent,dif_vel)<(melhor_h,melhor_rap,melhor_lent,melhor_vel) then
      melhor_h:=dif_h; melhor_rap:=dif_rap; melhor_lent:=dif_lent; melhor_vel:=dif_vel; melhores:=array[m];
    elsif (dif_h,dif_rap,dif_lent,dif_vel)=(melhor_h,melhor_rap,melhor_lent,melhor_vel) then
      melhores:=melhores||m;
    end if;
  end loop;
  esc:=melhores[1+floor(random()*array_length(melhores,1))::int];
  for i in 0..n-1 loop
    if ((esc >> i)&1)=1 then ta:=ta||ids[i+1]; sa:=sa+est[i+1];
    else tb:=tb||ids[i+1]; sb:=sb+est[i+1]; end if;
  end loop;
  insert into sorteios(racha_id,time_a,time_b,soma_a,soma_b,criado_por)
  values(p_racha,ta,tb,sa,sb,public.meu_jogador()) returning id into v_id;
  return v_id;
end $$;

revoke all on function public.admin_definir_velocidade(uuid,int) from public,anon;
grant execute on function public.admin_definir_velocidade(uuid,int) to authenticated;
revoke all on function public.admin_listar_velocidades() from public,anon;
grant execute on function public.admin_listar_velocidades() to authenticated;
revoke all on function public.registrar_evento_lista() from public,anon,authenticated;

-- Velocidade nao pode ser lida pela consulta normal do proprio jogador.
revoke select on public.jogadores from authenticated;
grant select(id,auth_id,nome,idade,posicao,is_admin,banido,estrelas,convite,criado_em)
  on public.jogadores to authenticated;
