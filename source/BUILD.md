# Сборка / Building

[Русский](#русский) · [English](#english)

## Русский

- `!00_AIM_WARMUP.map` — редактируемая карта для Hammer. `aim_warmup.wad` содержит её текстуры. Добавь WAD в настройки текстур Hammer перед открытием карты.
- `build_round_arena.py` создаёт карту и WAD из кода. Если ты отредактировал карту в Hammer, пропусти генерацию и собери свою версию из сохранённых MAP и WAD.
- `embed_textures.py` встраивает WAD в скомпилированную карту и проверяет кнопки, места ботов и привязку текстур.
- `aim_warmup.sma` — логика ботов, оружия, таймера и режимов. `plugins-!00_AIM_WARMUP.ini` включает её только на этой карте.

Нужны Python 3.10 или новее, компиляторы Hammer из Steam Half-Life SDK и `amxxpc.exe` из AMX Mod X 1.10.0-git5476. Отредактируй три пути в начале [команд сборки](#commands--команды). Для ручной правки замени отмеченную команду генерации копированием своих MAP и WAD в папку сборки под именами `aim_warmup.map` и `aim_warmup.wad`.

Для запуска скопируй содержимое папки `dist/cstrike` поверх уже настроенной сборки v4.5 с Metamod-R, AMX Mod X и ReGameDLL_CS. Точные версии и ссылки на их исходники перечислены в [THIRD-PARTY.md](../THIRD-PARTY.md). Готовая пользовательская сборка лежит в [релизе v4.5](https://github.com/pinkmanwest/cs16-warmup/releases/tag/v4.5).

## English

- `!00_AIM_WARMUP.map` is the editable Hammer map. `aim_warmup.wad` contains its textures. Add the WAD in Hammer's texture settings before opening the map.
- `build_round_arena.py` generates the map and WAD from code. If you edited the map in Hammer, skip generation and build from your saved MAP and WAD.
- `embed_textures.py` embeds the WAD in the compiled map and validates the buttons, bot spawn points, and texture orientations.
- `aim_warmup.sma` contains the bot, weapon, timer, and training-mode logic. `plugins-!00_AIM_WARMUP.ini` loads it for this map only.

Use Python 3.10 or newer, the Hammer compilers from the Steam Half-Life SDK, and `amxxpc.exe` from AMX Mod X 1.10.0-git5476. Set the three paths at the top of the [build commands](#commands--команды). To build manual edits, replace the marked generation command with copying your MAP and WAD into the build directory as `aim_warmup.map` and `aim_warmup.wad`.

To play, copy the contents of `dist/cstrike` over a configured v4.5 installation with Metamod-R, AMX Mod X, and ReGameDLL_CS. See [THIRD-PARTY.md](../THIRD-PARTY.md) for their exact versions and upstream source. The ready-to-play build is available in the [v4.5 release](https://github.com/pinkmanwest/cs16-warmup/releases/tag/v4.5).

## Commands / Команды

Run in PowerShell / Запусти в PowerShell.

```powershell
$source = 'C:\path\to\cs16-warmup\source'
$hammer = 'C:\path\to\Half-Life SDK\Hammer Editor\tools'
$amxx = 'C:\path\to\amxmodx\addons\amxmodx\scripting'

$build = Join-Path $PWD ('aim-warmup-build-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $build -ErrorAction Stop | Out-Null
foreach ($script in @('build_round_arena.py', 'embed_textures.py')) {
    Copy-Item -LiteralPath (Join-Path $source $script) -Destination $build -ErrorAction Stop
}

Push-Location $build
try {
    # Skip this step when building a MAP/WAD edited in Hammer.
    python build_round_arena.py
    if ($LASTEXITCODE) { throw 'Map generation failed' }

    foreach ($tool in @('qcsg', 'qbsp2', 'vis', 'qrad')) {
        & (Join-Path $hammer "$tool.exe") aim_warmup
        if ($LASTEXITCODE) { throw "Map compiler failed: $tool" }
    }

    python embed_textures.py
    if ($LASTEXITCODE) { throw 'Embedding textures failed' }
} finally {
    Pop-Location
}

$dist = Join-Path $build 'dist\cstrike'
$maps = Join-Path $dist 'maps'
$plugins = Join-Path $dist 'addons\amxmodx\plugins'
$configs = Join-Path $dist 'addons\amxmodx\configs\maps'
New-Item -ItemType Directory -Path $maps, $plugins, $configs -ErrorAction Stop | Out-Null
Copy-Item -LiteralPath (Join-Path $build 'aim_warmup_embedded.bsp') -Destination (Join-Path $maps '!00_AIM_WARMUP.bsp')
Copy-Item -LiteralPath (Join-Path $source 'plugins-!00_AIM_WARMUP.ini') -Destination $configs

Push-Location $amxx
try {
    .\amxxpc.exe (Join-Path $source 'aim_warmup.sma') "-o$plugins\aim_warmup.amxx"
    if ($LASTEXITCODE) { throw 'Pawn compilation failed' }
} finally {
    Pop-Location
}

$dist
```
