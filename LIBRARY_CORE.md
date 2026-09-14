# Hiki Traits Library — Core API v1

O Core fica dentro do mod `HikiTraits` e fornece a infraestrutura compartilhada
para o pacote principal, Unhinged e futuros pacotes de traits.

Os traits devem carregar apenas a entrada pública:

```lua
require "HikiTraits/Library"

local Library = HikiTraits.Library
```

Não é necessário importar cada arquivo interno separadamente.

## Estrutura

```text
HikiTraits/Library.lua
HikiTraits/Library/Core.lua
HikiTraits/Library/Core/
├── Conditions.lua
├── Effects.lua
├── Logger.lua
├── Network.lua
├── Runtime.lua
├── State.lua
├── Stats.lua
├── Traits.lua
├── Triggers.lua
└── Util.lua
```

## Regra periódica declarativa

Equivalente ao comportamento atual de `Meditate`:

```lua
require "HikiTraits/Library"

local L = HikiTraits.Library

L.Runtime.registerMinute({
    id = "hikitraits:meditate:recovery",
    traitId = "hikitraits:meditate",
    when = L.Conditions.sitting(),
    effects = {
        L.Effects.removeStat(CharacterStat.STRESS, 0.015),
        L.Effects.removeStat(CharacterStat.PANIC, 1.5),
    },
})
```

O Runtime automaticamente:

- ignora personagens mortos;
- confirma que o personagem possui o trait;
- executa no servidor em multiplayer e localmente em singleplayer;
- percorre a lista de jogadores por meio do loop central;
- isola erros de uma regra para não interromper as demais.

`Effects` automaticamente limita os valores ao intervalo do `CharacterStat` e
sincroniza apenas os stats realmente alterados.

Para efeitos que pertencem exatamente à virada de cada hora, use
`L.Runtime.registerHour({ ... })`. Regras de minuto, hora e intervalo real
compartilham um único dispatcher por agenda; nenhuma delas cria seu próprio
loop de jogadores.

## Trigger rearmável

Equivalente ao comportamento atual de `Shrug It Off`:

```lua
L.Triggers.registerStatHigh({
    id = "hikitraits:shrug_it_off:pain",
    traitId = "hikitraits:shrug_it_off",
    stat = CharacterStat.PAIN,
    atMaximum = true,
    rearmAt = 1,
    rearmInclusive = false,
    intervalMs = 100,
    stateMode = "persistent",
    effects = {
        L.Effects.setStat(CharacterStat.PAIN, 50),
    },
})
```

O trigger é desarmado antes de aplicar o efeito. Isso impede que callbacks
aninhados ou sincronização disparem o mesmo efeito duas vezes.

## Dano e stat no mesmo efeito

Uma futura definição correta de `Cardiac Patient` pode ficar compartilhada e
autoritativa:

```lua
L.Runtime.registerMinute({
    id = "hikitraitsunhinged:cardiac_patient:episode",
    traitId = "hikitraitsunhinged:cardiac_patient",
    when = L.Conditions.any(
        L.Conditions.statAtLeast(CharacterStat.STRESS, 0.999),
        L.Conditions.statAtLeast(CharacterStat.PANIC, 99.9)
    ),
    effects = {
        L.Effects.damageHealth(1),
        L.Effects.setStat(CharacterStat.PAIN, 100),
    },
})
```

Isso corrige a arquitetura antiga na qual um arquivo dentro de `lua/client`
tentava executar alterações que pertencem ao servidor.

## Condições incluídas

- composição com `all`, `any` e `none`;
- comparações de `CharacterStat`;
- mínimo e máximo de `CharacterStat`;
- comparações de nível de moodle;
- sentado no chão ou em mobília;
- dirigindo;
- do lado de fora;
- problema de peso segundo `Nutrition`;
- trait adicional;
- predicado customizado.

## Efeitos incluídos

- adicionar, remover ou definir `CharacterStat`;
- garantir valor mínimo ou máximo;
- causar dano geral;
- efeito customizado;
- valor fixo ou calculado por função;
- condição opcional por efeito.

## Escopos do Runtime

| Escopo | Execução |
|---|---|
| `AUTHORITATIVE` | servidor em MP; processo local em SP |
| `LOCAL` | jogadores locais do cliente ou SP |
| `SERVER` | somente servidor multiplayer |
| `CLIENT` | somente cliente multiplayer |
| `ANY` | processo atual |

O padrão é `AUTHORITATIVE`.

Eventos e agendas incompatíveis com o processo atual nem sequer são
instalados. Assim, regras autoritativas não deixam `OnTick` ocioso em clientes,
e eventos locais não tentam carregar APIs de apresentação no servidor dedicado.

## Estado

Estado persistente:

```lua
L.State.Persistent.set(character, TRAIT_ID, "used", true)
local used = L.State.Persistent.get(character, TRAIT_ID, "used", false)
```

Estado apenas da sessão:

```lua
L.State.Session.set(character, TRAIT_ID, "snapshot", snapshot)
```

Temporizadores baseados no relógio do mundo:

```lua
local elapsed = L.State.elapsedWorldHours(
    character,
    TRAIT_ID,
    "lastUseHour",
    "persistent"
)

L.State.markWorldTime(
    character,
    TRAIT_ID,
    "lastUseHour",
    "persistent"
)
```

Timestamps ausentes ou localizados no futuro são reinicializados com segurança.

## Rede

Toda a library usa um único módulo de comandos e um dispatcher em cada direção.
Handlers enviados ao servidor podem exigir trait, validação e cooldown:

```lua
L.Network.registerServerHandler({
    id = "meumod:acao",
    traitId = "meumod:trait",
    cooldownMs = 1000,
    validate = function(context, args)
        return tonumber(args.amount) ~= nil
    end,
    handle = function(context, args)
        -- alteração autoritativa
    end,
})
```

Envio:

```lua
L.Network.sendToServer(character, "meumod:acao", {
    amount = 1,
})
```

Em singleplayer, a mesma chamada atravessa a fronteira lógica diretamente, sem
exigir uma conexão de rede fictícia.

## Systems

As integrações de gameplay foram construídas em `Library/Systems` sobre este
Core:

- `InjuryManager`;
- `TimedActionManager`;
- `ConsumptionManager`;
- `ModifierManager`;
- `ClothingManager`;
- `NutritionManager`.

Consulte `LIBRARY_SYSTEMS.md` para a API e os exemplos de migração. O Core
continua independente: os Systems usam suas funções, mas não duplicam loops,
estado, logging, rede ou setters de stats.
