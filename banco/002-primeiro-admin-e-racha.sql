-- Rode DEPOIS do 001, um comando por vez (selecione o trecho e clique em Run).
-- Se o painel mostrar "already exists", voce rodou o 001 de novo: nao rode.

-- 1) Primeiro admin. Troque SEU NOME. Guarde o codigo que aparecer.
insert into public.jogadores (nome, posicao, is_admin, convite)
values ('SEU NOME', 'MEI', true, upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)))
returning convite;

-- 2) Racha da proxima segunda, 19h.
select public.criar_racha_semanal();

-- 3) Conferir.
select inicio at time zone 'America/Fortaleza' as jogo,
       abre_em at time zone 'America/Fortaleza' as abre
from public.rachas;
