# Hiki Traits Library — Systems API v1

Os sistemas ficam dentro do próprio `HikiTraits`. O pacote principal, o
Unhinged e futuros pacotes só precisam carregar a entrada pública:

```lua
require "HikiTraits/Library"

local L = HikiTraits.Library
```

Nenhum mod adicional passa a ser requisito dos saves.

## Estrutura

```text
HikiTraits/Library/Systems.lua
HikiTraits/Library/Systems/
├── ClothingManager.lua
├── ConsumptionManager.lua
├── InjuryManager.lua
├── ModifierManager.lua
├── NutritionManager.lua
└── TimedActionManager.lua
```

Os hooks são instalados de maneira preguiçosa: carregar a library não inicia
scanners de ferimentos, wrappers de consumo ou loops de modificadores. Cada
sistema ativa somente a infraestrutura exigida pela primeira regra registrada.

## TimedActionManager

Vários traits podem observar o mesmo método sem empilhar wrappers próprios. O
original é chamado uma única vez, os callbacks seguem prioridade e todos os
valores de retorno são preservados.

```lua
L.TimedActionManager.register({
    id = "meumod:leitura-concluida",
    module = "TimedActions/ISReadABook",
    className = "ISReadABook",
    method = "complete",
    traitId = "meumod:bookworm",
    after = function(context)
        if context.completed then
            -- context.action, character, progress, arguments e returns
        end
    end,
})
```

Para uma ação detectada no cliente que deve causar efeito no servidor, use a
ponte pronta. Uma versão modular de `Task Fixation` pode ser apenas:

```lua
L.TimedActionManager.registerAuthoritative({
    id = "hikitraits:task_fixation:interruption",
    module = "TimedActions/ISBaseTimedAction",
    className = "ISBaseTimedAction",
    method = "stop",
    traitId = "hikitraits:task_fixation",
    whenAction = function(context)
        return context.progress >= 0.25
    end,
    validate = function(_, args)
        return tonumber(args.progress) >= 0.25
    end,
    cooldownMs = 250,
    effects = {
        L.Effects.addStat(CharacterStat.STRESS, 0.10),
    },
})
```

O payload é capturado antes do método vanilla apagar o estado da ação e enviado
depois que ele retorna. Em singleplayer, a mesma fronteira lógica é executada
diretamente.

## ConsumptionManager

Centraliza todos os caminhos já usados pelo mod:

- conclusão e interrupção de `ISEatFoodAction`;
- bebidas do sistema de fluidos;
- ação rápida de beber de um recipiente;
- água bebida diretamente de objetos do mundo;
- comprimidos e itens consumidos por `ISTakePillAction`.

O contexto oferece:

| Campo | Conteúdo |
|---|---|
| `kind` | `food`, `fluid` ou `pill` |
| `source` | caminho vanilla que consumiu o conteúdo |
| `portion` | fração real de um alimento, entre 0 e 1 |
| `liters` | volume real removido do recipiente/fonte |
| `itemSnapshot` | propriedades do item antes de ele desaparecer |
| `fluidSnapshot` | fluido primário, água pura, álcool e nutrientes |
| `completed` | ação concluída normalmente |
| `interrupted` | porção consumida ao interromper a ação |

`Comfort Eater` pode ser declarado assim:

```lua
L.ConsumptionManager.registerRule({
    id = "hikitraits:comfort_eater:food",
    traitId = "hikitraits:comfort_eater",
    kinds = L.ConsumptionManager.Kind.FOOD,
    effects = function(context)
        return {
            L.Effects.removeStat(
                CharacterStat.STRESS,
                0.015 * context.portion
            ),
        }
    end,
})
```

Uma condição de fluido não precisa voltar a investigar as classes da B42:

```lua
when = function(context)
    return L.ConsumptionManager.isPlainWater(context.fluidSnapshot)
end
```

No multiplayer, o cliente mede o consumo real e envia somente o snapshot
serializável. O servidor confirma personagem, trait, limites e aplica as regras
autoritativas. O servidor dedicado não carrega classes de timed action à toa.

## ClothingManager

Fornece consulta de itens vestidos, grupos extensíveis, partes cobertas e
alteração sincronizada de umidade.

```lua
if L.ClothingManager.hasWornGroup(character, "hearingProtection") then
    return
end
```

O grupo vanilla inicial contém:

- `Base.Hat_EarMuff_Protectors`;
- `Base.Hat_EarMuffs`.

Compatibilidade externa:

```lua
L.ClothingManager.addToGroup(
    "hearingProtection",
    "OutroMod.Protetor"
)
```

Molhar somente roupas escolhidas:

```lua
L.ClothingManager.setWornWetness(
    character,
    100,
    function(item, entry)
        return L.ClothingManager.coversPart(item, "Groin")
    end
)
```

Também existem `findWorn`, `firstWorn`, `selectorByLocations`,
`selectorByCoveredParts`, `setWetness` e `changeWornWetness`.

## NutritionManager

Usa `Nutrition` como fonte da verdade para peso, calorias, carboidratos,
lipídios e proteínas. Aceita os aliases `carbs`, `protein` e `fat`.

```lua
local snapshot = L.NutritionManager.snapshot(character)

local muitaProteina = L.NutritionManager.atLeast("protein", 75)
local pesoNormal = L.NutritionManager.weightTrouble(false)
```

Uma regra periódica já recebe `context.nutrition`:

```lua
L.NutritionManager.registerRule({
    id = "hikitraits:nutrient_driven:carbs",
    traitId = "hikitraits:nutrient_driven",
    metric = "carbohydrates",
    minimum = 75,
    effects = function(context)
        return {
            L.Effects.addStat(CharacterStat.ENDURANCE, 0.0025),
        }
    end,
})
```

Setters nutricionais usam `sendPlayerNutrition` quando executados no servidor.

## ModifierManager

Um canal recebe contribuições de qualquer quantidade de traits. O manager soma
as fontes, lembra exatamente o que aplicou e o remove quando o trait ou sua
condição deixam de valer. Alterações vanilla ou de outros mods são preservadas.

O canal embutido é `maxWeightDelta`:

```lua
L.ModifierManager.registerSource({
    id = "hikitraits:nutrient_driven:protein-capacity",
    traitId = "hikitraits:nutrient_driven",
    channel = "maxWeightDelta",
    value = 2,
    when = L.NutritionManager.atLeast("protein", 75),
})
```

Outros mods podem criar canais com `registerChannel(id, { read, write })`. Para
propriedades aditivas simples, também podem informar `getter` e `setter`.

## InjuryManager

O manager existente agora mora nesta pasta e usa o `Runtime` central. O caminho
antigo continua sendo uma fachada compatível:

```lua
require "HikiTraits/InjuryManager"
```

Handlers mantêm as prioridades:

| Prioridade | Uso |
|---:|---|
| `PREVENTION` | impedir a lesão antes das demais regras |
| `LOCATION_DEFENSE` | defesa específica, como `Neck Reflex` |
| `LIMITED_DEFENSE` | recurso consumível, como `Bitten? No.` |
| `WORSENING` | converter a lesão em algo pior |
| `DEFAULT` | comportamento comum |

O caso simples agora é completamente declarativo:

```lua
L.InjuryManager.registerRule({
    id = "hikitraits:bitten_no:first-bite",
    traitId = "hikitraits:bitten_no",
    priority = L.InjuryManager.PRIORITY.LIMITED_DEFENSE,
    injuries = "bite",
    action = "replace",
    replacement = "cut",
    infectionPolicy = L.InjuryManager.INFECTION_POLICY.PREVIOUS,
    once = true,
})
```

`once` é persistido somente depois de uma transformação bem-sucedida. Regras
especiais continuam podendo usar `registerHandler({ evaluate = ... })`, e
efeitos posteriores podem ser declarados em `effects` ou `onApplied`.

## Mapa de migração

| Código antigo | Destino |
|---|---|
| loops `EveryOneMinute`/`OnTick` | `Runtime`, `Triggers`, `NutritionManager` |
| wrappers de `ISEatFoodAction` | `ConsumptionManager` |
| wrappers de bebidas e comprimidos | `ConsumptionManager` |
| wrappers de `ISBaseTimedAction` e ações específicas | `TimedActionManager` |
| loops de `getWornItems()` | `ClothingManager` |
| getters/setters de `Nutrition` | `NutritionManager` |
| bônus temporário em propriedade do personagem | `ModifierManager` |
| snapshots e transformações de ferimentos | `InjuryManager` |

Depois da migração, os arquivos de trait devem conter parâmetros, listas de IDs
específicas daquele trait e chamadas de registro. A posse de hooks, loops,
sincronização e snapshots pertence à library.

## Migração incluída na v0.3.0

Todos os 21 scripts funcionais dos dois pacotes foram portados. Os maiores
ganhos são:

- todos os traits de comida, bebida e comprimidos compartilham os dez wrappers
  do `ConsumptionManager`;
- `Neck Reflex`, `Bitten? No.` e `Loud When Hurt` compartilham um único scanner
  do `InjuryManager`;
- `Task Fixation`, `Animal Lover` e `Exercise Routine` usam hooks encadeados do
  `TimedActionManager`;
- efeitos periódicos compartilham os dispatchers de minuto, hora e intervalo;
- `Cardiac Patient` agora executa no lado autoritativo;
- o Unhinged declara `HikiTraits` como dependência e reutiliza a mesma library.

Os arquivos dos traits passaram a conter apenas constantes próprias, listas de
compatibilidade e as regras que descrevem seu comportamento.
