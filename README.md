<div align="center">

<img src="docs/icon-256.png" width="112" alt="GtrBoard">

# GtrBoard

**Гитарный борд для macOS — без плагина, без DAW, без задержки на подумать.**

Низколатентный standalone-тракт: гитара → 15 педалей → усилитель → кабинет →
IR-кабинет → 10-полосный EQ → запись. 30 заводских пресетов, свои пресеты в открытом JSON,
A/B-банки, кроссфейд между пресетами и меню-бар.

[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](#build)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](#build)
[![Tests](https://img.shields.io/badge/tests-906%20passing-2ea043)](#tests)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.4.0-8b5cf6)](CHANGELOG.md)
[![CI](https://github.com/WEBSTUDIUS/GtrBoard/actions/workflows/ci.yml/badge.svg)](https://github.com/WEBSTUDIUS/GtrBoard/actions/workflows/ci.yml)

<p><b>Русский</b> · <a href="README.en.md">🇬🇧 English</a></p>

[Быстрый старт](#quickstart) · [Пресеты с ИИ](#ai-presets) · [Запись](#record) ·
[Сборка](#build) · [Архитектура](#architecture)

</div>

![GtrBoard](docs/screenshot.png)

> **Хочешь свой звук?** Опиши его словами в любом чате с ИИ и получи готовый
> `.gtrpreset` — GtrBoard импортирует его как обычный пресет. Подробности:
> [**Пресеты с помощью ИИ**](#ai-presets).

---

## <a id="contents"></a>Содержание

- [Что это](#what)
- [Быстрый старт](#quickstart)
- [Сигнальная цепь](#signal)
- [Педали](#pedals)
- [Усилитель, кабинет и EQ](#amp-eq)
- [Подавитель обратной связи](#feedback-guard)
- [Пресеты](#presets)
- [🤖 Пресеты с помощью ИИ](#ai-presets)
- [Запись и DAW](#record)
- [Сборка](#build)
- [Плагин в DAW (AUv3)](#plugin)
- [Архитектура](#architecture)
- [Тесты](#tests)
- [Если что-то не так](#trouble)
- [Ограничения и планы](#limits)
- [Лицензия](#license)

## <a id="what"></a>Что это

GtrBoard — самостоятельное macOS-приложение для гитары. Оно открывает
аудиоинтерфейс напрямую, обрабатывает сигнал в реальном времени и выводит его
на выбранные колонки или наушники. Это **не AU/VST-плагин**: DAW не нужен,
чтобы просто играть.

- **Низкая задержка.** Приватный aggregate-девайс, HAL AudioUnit, буфер
  64–512 сэмплов. Задержка видна в интерфейсе.
- **15 педалей в настоящей цепи.** Порядок меняется стрелками; каждая педаль
  включается футсвитчем или LED.
- **Усилитель и кабинет.** Clean / Crunch / Lead / High Gain, gain, темброблок,
  presence, master, sag; кабинет с low/high cut и резонансом.
- **IR-кабинет.** 12 готовых импульсов (V30 4×12 SM57 и 57+121, Mesa OS,
  Marshall G12T-75 и V30, Diezel, ENGL, Orange PPC, 5150, Fredman 57/57,
  Djent tight, modern scoop) и импорт своего WAV: low/high cut, mix, level,
  переключение импульса без щелчка. IR-пресеты: Enter Sandman IR,
  Enter Sandman IR · EQ, Modern Metal, Djent, Swedish Chainsaw, Doom Wall.
- **Подавитель обратной связи.** Перед цепью стоит автоматический guard:
  ловит вой в гитарной полосе **от 2 кГц** и сетевую наводку 50/60 Гц, ставит
  узкие нотчи, а если петля всё равно держится — выключает вход и показывает
  **MUTED** (клик по индикатору возвращает звук). Выключатель **GUARD** —
  в футере, рядом с LIMIT, и в меню-баре. Затухающая нота и удерживаемый
  аккорд не глохнут.
- **Драйвы с 4× oversampling.** Overdrive, distortion и fuzz с разным
  характером клиппинга.
- **Модуляция и время.** Chorus, Flanger, Phaser, Tremolo, Delay (digital /
  analog / ping-pong), Reverb (room / hall / plate).
- **10-полосный графический EQ** 31.5 Гц – 16 кГц, ±12 дБ, в конце цепи.
- **Пресеты.** 30 заводских ригов, свои пресеты, поиск, импорт/экспорт JSON,
  A/B-банки и переключение пробелом.
- **Кроссфейд.** Две независимые цепи: новый пресет подмешивается за 50 мс —
  без щелчка, паузы и скачка уровня.
- **Запись.** WAV 24-bit PCM (по умолчанию) или 32-bit float в
  `~/Music/GtrBoard`.
- **Меню-бар.** Окно можно закрыть — обработка и быстрый доступ остаются.
- **Вход можно отключить.** Режим **No Input** работает только на выход, без
  микрофона и без запроса доступа.

## <a id="quickstart"></a>Быстрый старт

### 1. Соберите приложение

> **Готовая сборка:** [GtrBoard 0.4.0 для macOS (Apple Silicon), zip](https://github.com/WEBSTUDIUS/GtrBoard/releases/latest).
> Распакуйте `.app` и откройте. Сборка ad-hoc; если Gatekeeper ругается —
> правый клик → **Open**.

```bash
git clone git@github.com:WEBSTUDIUS/GtrBoard.git
cd GtrBoard
./build.sh
open dist/GtrBoard.app
```

Готовое приложение — `dist/GtrBoard.app`. Сборка подписана ad-hoc; если
Gatekeeper блокирует копию в `/Applications`, откройте её через правый клик →
**Open**.

Ещё команды:

```bash
./run.sh       # собрать и открыть
./install.sh   # установить в /Applications (~/Applications как fallback)
./test.sh      # DSP/пресет self-tests (906 проверок)
```

### 2. Подключите гитару

1. Подключите аудиоинтерфейс и наушники/мониторы.
2. В футере выберите **вход** (гитарный интерфейс) и **выход**.
3. Буфер: **64–128** сэмплов для игры, **256–512** если компьютер загружен.
4. Нажмите кнопку питания в правом верхнем углу. macOS попросит доступ к
   микрофону — разрешите. Сигнал обрабатывается локально и никуда не уходит.
5. Играйте. Вход регулируется на интерфейсе, выход — ручкой **MASTER**.

> **Без гитары?** Выберите **No Input** в меню входа — движок запустится
> только на выход, без микрофона и без разрешения. Удобно для проверки
> выхода и записи, когда гитара не подключена.

> Не выбирайте встроенные микрофон и колонки одновременно для игры — будет
> акустическая обратная связь. Для проверки тракта используйте наушники.

## <a id="signal"></a>Сигнальная цепь

```
Guitar → Interface ─┐
                    ├─ private aggregate device (drift compensation)
Speakers/Phones ←───┘
                                 │
                    HAL AudioUnit (Float32, non-interleaved)
                                 │
                    BoardProcessor (audio thread)
                      Feedback / hum guard → Gate → Compressor → Boost
                      → Overdrive → Distortion → Fuzz → Amplifier
                      → Cabinet → IR Cabinet → Chorus → Flanger
                      → Phaser → Tremolo → Delay → Reverb
                      → 10-band Graphic EQ → Master → Look-ahead Limiter
                                 │
                    выбранный выход
```

## <a id="pedals"></a>Педали

| Педаль | Параметры | Характер |
|---|---|---|
| Noise Gate | threshold, decay, range | гистерезисный гейт с удержанием |
| Compressor | threshold, ratio, attack, release, makeup | feed-forward, soft knee, стерео-связанный |
| Clean Boost | gain, tilt, tight | прозрачный буст с обрезом низа |
| Overdrive | drive, tone, level, mid | Tube Screamer: HP перед клиппером, mid-горб |
| Distortion | gain, tone, level, edge | смешанный soft/hard клиппинг, злее овердрайва |
| Fuzz | sustain, tone, level, bias | Big Muff: два каскада, LP/HP-блендинг |
| Amplifier | gain, bass, mid, treble, presence, master, voicing | четырёхголосный преамп + sag |
| Cabinet | low cut, high cut, resonance | 4×12, резонанс 110 Гц, presence 2.6 кГц |
| IR Cabinet | model, mix, low cut, high cut, level | 12 готовых импульсов + свой WAV, свёртка без задержки сверх одного блока |
| Chorus | rate, depth, mix, width | два модулированных голоса, стерео-LFO |
| Flanger | rate, depth, feedback, mix, manual | короткая линия с резонансной ОС |
| Phaser | rate, depth, feedback, mix, stages | 4–12 all-pass ступеней |
| Tremolo | rate, depth, shape, stereo | sine / triangle / square |
| Delay | time, feedback, mix, tone, mode | Digital / Analog / Ping-Pong |
| Reverb | size, damping, mix, pre-delay, mode | Room / Hall / Plate |

Ручки: тяните вверх/вниз, двойной клик — сброс. Стрелки `‹ ›` на карточке
меняют порядок, **Reset chain** возвращает заводской.

## <a id="amp-eq"></a>Усилитель, кабинет и EQ

- **Amplifier** — четыре голоса: Clean, Crunch, Lead, High Gain. Асимметричный
  триодный клип, sag по огибающей, пассивный темброблок.
- **Cabinet** — 24 дБ/окт low/high cut, резонанс 110 Гц, presence 2.6 кГц.
- **IR Cabinet** — колоночный импульс вместо аналогового кабинета. 12
  синтезированных кабинетов с уклоном в металл; меню на педали открывает
  **Import WAV…** и подхватывает сторонний IR (PCM 8/16/24/32 и float,
  моно/стерео). Импорт копируется в `~/Library/Application Support/GtrBoard/IRs`,
  ресемплится под частоту сессии и нормализуется по энергии; пользовательский
  импульс обрезается до 170 мс. IR-педаль добавляет 64 сэмпла задержки — она
  учитывается в индикаторе latency. Импорт перезапускает аудио на полсекунды,
  переключение встроенных кабинетов — без разрыва (8 мс фейд). При включении
  IR аналоговый Cabinet выключается автоматически, чтобы два кабинета не
  складывались; вручную можно включить оба.
- **Graphic EQ** — 10 полос: 31.5, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Гц;
  ±12 дБ, Q ≈ 1.41. Стоит после педалей, перед master и лимитером. **Flat**
  сбрасывает полосы, переключатель **EQ** выключает секцию.
- **Limiter** — прозрачный look-ahead ~1.5 мс, всегда в цепи, поэтому его
  включение/выключение не меняет задержку и не щёлкает.

### Enter Sandman: две версии

Обе версии используют Mesa OS · SM57 IR, один и тот же гейт, буст, Recto-подобный
High Gain, low/high cut 90/7 кГц и короткий рум:

| Пресет | Эквализация | Для чего |
|---|---|---|
| **Enter Sandman IR** | графический EQ плоский | честный IR-риг без дополнительной окраски |
| **Enter Sandman IR · EQ** | блэкальбомная кривая | ближе к ритм-тону с альбома; A/B с первой версией |

Кривая второй версии: `31.5` 0, `63` +1, `125` +0.5, `250` −2.5, `500` −3,
`1k` −1.5, `2k` +1.5, `4k` +2, `8k` −2.5, `16k` −5 дБ. Низкая середина
вычищена, presence добавлен, песок срезан. Уровни обеих версий откалиброваны
до общего RMS, поэтому переключение не прыгает по громкости.

Это приближение, а не клон: усилитель и кабинет в GtrBoard свои, IR
синтезирован, а альбомный тон — это ещё и дабл-трек со студийной обработкой.
Для более точного попадания импортируйте свой Mesa IR через **Import WAV…**.

## <a id="feedback-guard"></a>Подавитель обратной связи

Guard стоит **до** педалей и работает в два слоя:

- **Нотчи.** Автоматически ставит узкие нотчи (Q 20) на растущие пики в
  полосе **2–12 кГц** — там живёт акустический вой гитарного тракта. Отдельно
  ловит наводку 50/60 Гц и её гармоники узкими нотчами Q 40: сценарий
  «висящий конец джека».
- **MUTED.** Если доминирующий пик стабильно выше 2 кГц, спектр стационарен
  около секунды, а выход громкий — петля не разрывается нотчами. Тогда guard
  выключает вход на −60 дБ и показывает **MUTED**. Клик по бейджу или смена
  пресета возвращают звук; сам guard при этом остаётся включённым.

Переключатель **GUARD** — в футере рядом с LIMIT и в меню-баре
(`Enable/Disable Feedback Guard`). Затухающие ноты, удерживаемые аккорды и
низкий B рядом с 50/60 Гц не глохнут — на это есть отдельные тесты.

> Встроенный микрофон и колонки с хайгейном всё равно будут ловить петлю —
> физику не обмануть. Guard не даст заводиться бесконечно, но для игры нужны
> наушники или аудиоинтерфейс.

## <a id="presets"></a>Пресеты

Пресет — полный снимок борда: порядок и параметры всех 15 педалей, EQ,
master volume, output trim, limiter и bypass.

### Заводские риги

<details>
<summary><b>30 заводских пресетов — развернуть</b></summary>

| Пресет | Ориентир | Теги |
|---|---|---|
| Studio Clean | чистый ламповый усилитель, компрессор, рум | clean, studio |
| Sultans of Swing | Strat → Vibrolux, компрессор | clean, blues |
| Little Wing | чистый Fender + медленный phaser | clean, hendrix |
| Texas Flood | TS-808 → чистый Fender | blues, lead |
| Slow Dancing | низкий OD + аналоговый дилей | blues, mayer |
| Plexi Crunch | Marshall Plexi, 4×12 | crunch, classic-rock |
| Back in Black | JCM800, минимум эффектов | crunch, acdc |
| Purple Haze | Fuzz Face → Plexi | fuzz, hendrix |
| Comfortably Numb | Big Muff → Electric Mistress → Hiwatt + дилей | lead, floyd |
| Smells Like Teen Spirit | DS-1 → чистый Fender + chorus | alternative, grunge |
| Master of Puppets | TS-буст → Mark-подобный high gain, гейт | metal, thrash |
| Enter Sandman | Recto-подобный high gain, гейт, рум | metal |
| Enter Sandman IR | тот же Recto-риг через Mesa OS 4×12 IR | metal, metallica, ir |
| Enter Sandman IR · EQ | тот же IR-риг + блэкальбомная EQ-кривая | metal, metallica, ir, eq |
| Killing in the Name | JCM800 на громкости, drop D | metal, rap-rock |
| Seven Nation Army | Big Muff + тёмный чистый | fuzz, riff |
| Streets Have No Name | доттед-8-дилей + chorus + чистый | ambient, u2 |
| Everlong | distortion + chorus + аналоговый дилей | alternative, rock |
| Only Shallow | тремоло + длинный реверб, shoegaze | shoegaze, mbv |
| Ambient Swell | медленное тремоло, длинные дилей и холл | ambient, texture |
| Djent Tight | гейт + буст + высокий gain + low-cut | metal, djent |
| Funk Clean | быстрый компрессор, яркий чистый | funk, clean |
| Garage Rock | OD в разогнанный усилитель, рум | rock, garage |
| Ain't Talkin' 'Bout Love | Phase 90 → Plexi | crunch, van-halen |
| Whole Lotta Love | Tone Bender → Vox-подобный край | fuzz, zeppelin |
| Modern Lead | high gain + цифровой дилей + холл | lead, metal |
| Modern Metal IR | буст → high gain → V30 4×12 IR (SM57) | metal, rhythm, ir |
| Djent IR | tight-буст → 5150-подобный head → Djent IR | metal, djent, ir |
| Swedish Chainsaw IR | hard-clip → high gain → Fredman 57/57 IR | metal, death, ir |
| Doom Wall IR | Big Muff → тёмный усилитель → Orange PPC IR | metal, doom, ir |

</details>

Заводские пресеты **откалиброваны по громкости**: разброс RMS около 1 дБ,
поэтому «Studio Clean → Enter Sandman» не выстреливает. Калибровка живёт в
`outputTrim` — ползунок **PRESET** в футере. Двойной клик по значению — 0 дБ.

### Пресеты в репозитории

В папке [`Presets/`](Presets/) лежат готовые пользовательские пресеты — их можно
импортировать через **⌘O** или **Browse Presets → Import**. Первый:
[`Enter Sandman GPT.json`](Presets/Enter%20Sandman%20GPT.json) — ритм в духе
Metallica *Black Album*: гейт, тугой overdrive-буст, high gain, закрытый 4×12,
scooped-EQ и маленький рум. Рядом лежат два Linkin Park:
[`Hybrid Theory`](Presets/Linkin%20Park%20-%20Hybrid%20Theory.json) (drop D,
плотный high gain, больше верхней середины, сухо) и
[`Faint / Given Up`](Presets/Linkin%20Park%20-%20Faint.json) (злее, быстрее
гейт, ярче presence).

### Сохранение и обмен

- **Save Preset** (⌘S) — имя, gear, теги, заметки; файл `.gtrpreset` пишется в
  `~/Library/Application Support/GtrBoard/Presets/`.
- **Browse Presets** (⇧⌘P) — поиск, предпросмотр цепи, загрузка, экспорт,
  дублирование, удаление.
- **Import** (⌘O) / **Export** (⌘E) — обмен JSON-файлами.
- Импортированный пресет получает новый `id` и не перезаписывает существующий.

### A/B и пробел

**A** и **B** в шапке — два полных снимка борда.

- пустой слот по клику сохраняет текущий борд;
- заполненный — загружает снимок;
- правый клик — переназначить, загрузить или очистить;
- **пробел** переключает A↔B, если назначены оба; иначе включает/выключает
  bypass;
- переключение идёт через **кроссфейд 50 мс** между двумя цепями — без
  щелчков и провалов.

### Формат `.gtrpreset`

Открытый JSON с конвертом версии. Минимальный пример:

```json
{
  "format": "com.andreyilin.gtrboard.preset",
  "version": 1,
  "preset": {
    "name": "My Tone",
    "author": "you",
    "gear": "Tele → clean Fender",
    "tags": ["clean"],
    "notes": "…",
    "settings": {
      "units": [
        { "kind": "amp", "enabled": true, "params": { "gain": 8, "master": -8, "voicing": 0 } },
        { "kind": "cabinet", "enabled": true },
        { "kind": "reverb", "enabled": true, "params": { "mix": 0.15, "mode": 0 } }
      ],
      "graphicEQ": { "enabled": true, "gains": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
      "masterVolume": -6,
      "outputTrim": 0,
      "limiter": true,
      "feedbackGuard": true,
      "bypass": false
    }
  }
}
```

Параметры — в реальных единицах (dB, Hz, ms, 0…1). Недостающие ключи
заполняются заводскими значениями, лишние отбрасываются, всё клампится в
допустимые диапазоны. Поэтому старые и чужие пресеты не могут «сломать» DSP.

## <a id="ai-presets"></a>🤖 Пресеты с помощью ИИ

> **Коротко:** GtrBoard не вызывает нейросети сам. Вы просите любой чат с LLM
> (ChatGPT, Claude, DeepSeek, Gemini) описать борд в JSON, сохраняете ответ
> как `.gtrpreset` и импортируете. Никаких API-ключей, аккаунтов и отправки
> телеметрии из приложения.

Это работает потому, что формат пресета — обычный читаемый JSON, а не
проприетарный бинарник. Модель пишет **структуру борда**, а GtrBoard проверяет
и применяет значения.

### 1. Скопируйте промпт

```text
Ты — гитарный звукорежиссёр. Сгенерируй ОДИН пресет для GtrBoard по описанию:
«тёплый британский кранч для хамбакеров, немного середины, лёгкий рум».

Верни ТОЛЬКО валидный JSON без markdown, комментариев и пояснений:

{
  "format": "com.andreyilin.gtrboard.preset",
  "version": 1,
  "preset": {
    "name": "...",
    "author": "AI + <твоё имя>",
    "gear": "...",
    "tags": ["..."],
    "notes": "...",
    "settings": {
      "units": [
        {"kind": "gate", "enabled": false},
        {"kind": "compressor", "enabled": false},
        {"kind": "boost", "enabled": false},
        {"kind": "overdrive", "enabled": false},
        {"kind": "distortion", "enabled": false},
        {"kind": "fuzz", "enabled": false},
        {"kind": "amp", "enabled": true},
        {"kind": "cabinet", "enabled": true},
        {"kind": "ir", "enabled": false},
        {"kind": "chorus", "enabled": false},
        {"kind": "flanger", "enabled": false},
        {"kind": "phaser", "enabled": false},
        {"kind": "tremolo", "enabled": false},
        {"kind": "delay", "enabled": false},
        {"kind": "reverb", "enabled": true}
      ],
      "graphicEQ": {"enabled": true, "gains": [0,0,0,0,0,0,0,0,0,0]},
      "masterVolume": -6,
      "outputTrim": 0,
      "limiter": true,
      "bypass": false
    }
  }
}

Правила:
1. В units ровно 15 kind в этом порядке: gate, compressor, boost, overdrive,
   distortion, fuzz, amp, cabinet, ir, chorus, flanger, phaser, tremolo,
   delay, reverb. Включай нужные через enabled.
2. Параметры можно опускать — возьмутся заводские. Если указываешь — реальные
   единицы: dB, Hz, ms; проценты 0…1.
3. Переключатели: amp.voicing 0 Clean / 1 Crunch / 2 Lead / 3 High Gain;
   phaser.stages 0=4 / 1=6 / 2=8 / 3=12; tremolo.shape 0 Sine / 1 Triangle /
   2 Square; delay.mode 0 Digital / 1 Analog / 2 Ping-Pong; reverb.mode
   0 Room / 1 Hall / 2 Plate.
4. graphicEQ.gains — 10 чисел в dB, порядок 31.5…16k Гц.
5. masterVolume −60…12 dB; outputTrim −24…24 dB.
6. Не добавляй id, createdAt, modifiedAt, isBuiltIn. Только JSON.
```

### 2. Сохраните ответ

Скопируйте JSON в файл, например `MyTone.gtrpreset` (UTF-8). Если модель
обернула ответ в ` ```json ` — удалите ограждения, оставьте только `{ … }`.

### 3. Импортируйте

В GtrBoard: **⌘O** (Import) или **Browse Presets → Import**. Пресет появится
в библиотеке. Дальше его можно назначить в **A/B**, крутить ручки и сохранить
свою версию.

### Что важно знать

- **Оставляйте `outputTrim: 0`** при генерации. После импорта подстройте
  громкость ползунком **PRESET** — так пресеты не будут прыгать по уровню.
- **Все 15 `kind` лучше перечислять явно.** Если единицу не указать, GtrBoard
  добавит её с заводскими настройками (amp, cabinet и reverb по умолчанию
  включены) — можно получить неожиданный реверб.
- **Модель не слышит ваш тракт.** Один и тот же JSON на разных гитарах и
  интерфейсах звучит по-разному; правьте ушами.
- **Просите несколько вариантов** («меньше гейна», «больше середины», «с
  дилеем») и сравнивайте в A/B.
- **Не вставляйте секреты.** Генерация идёт во внешнем сервисе.

📚 **Полный справочник параметров, диапазоны, индексы переключателей и готовый
пример** — в [`docs/AI_PRESETS.md`](docs/AI_PRESETS.md)
([English version](docs/AI_PRESETS.en.md)). Пример файла:
[`docs/examples/ai-british-crunch.gtrpreset`](docs/examples/ai-british-crunch.gtrpreset).

## <a id="record"></a>Запись и DAW

### WAV

**REC** в футере (или ⇧⌘R) пишет обработанный выход в:

```
~/Music/GtrBoard/GtrBoard-YYYY-MM-DD-HHMMSS.wav
```

- 2 канала, частота устройства (обычно 48 кГц);
- **24-bit PCM** по умолчанию или **32-bit float** — переключатель рядом с REC;
- запись идёт после усилителя, кабинета, EQ, master и лимитера — ровно то,
  что слышно;
- аудиопоток пишет в lock-free кольцо, фоновый поток сливает на диск: без
  локов и аллокаций в render-callback, без провалов и щелчков;
- повторное нажатие REC останавливает запись, файл сразу готов;
- правый клик по REC → **Reveal Last Recording in Finder**.

### Живой вход в DAW через BlackHole

1. Установите бесплатный **BlackHole 2ch**.
2. В GtrBoard выберите выход **BlackHole 2ch**.
3. В Logic/Reaper/Ableton создайте трек с входом **BlackHole 2ch**.
4. Слушайте себя через выход интерфейса/наушники, не через BlackHole, иначе
   получится петля.

Задержка складывается из буферов GtrBoard и DAW. Для записи это нормально;
для живого мониторинга лучше играть через выход интерфейса.

> AUv3-плагин, чтобы DAW сам хостил GtrBoard, — в дорожной карте. Пока
> BlackHole/WAV — честный способ отдать звук в DAW.

## <a id="build"></a>Сборка

### Требования

- macOS **14.0+** (проверено на macOS 27.2, Apple Silicon);
- Swift 6 / Command Line Tools; полный Xcode не обязателен;
- аудиоинтерфейс (или встроенный микрофон для экспериментов).

```bash
git clone git@github.com:WEBSTUDIUS/GtrBoard.git
cd GtrBoard
./build.sh
open dist/GtrBoard.app
```

- `./build.sh` собирает release и `.app` в `dist/`.
- `./run.sh` — собрать и открыть.
- `./install.sh` — установить в `/Applications` (fallback `~/Applications`).
- `./test.sh` — self-tests.

> **Command Line Tools и SwiftUI-макросы.** В SDK macOS 27 макросы SwiftUI
> объявлены, но плагин `SwiftUIMacros` в CLT не поставляется. `build.sh`
> автоматически собирает с SDK 26.5, если он есть; переопределить можно через
> `GTRBOARD_SDK=/path/to/MacOSX.sdk ./build.sh`.

## <a id="plugin"></a>Плагин в DAW (AUv3)

GtrBoard собирается и как **AUv3-эффект** для Logic и GarageBand — с тем же
движком `BoardCore`, тем же бордом и тем же звуком, что и standalone.

```bash
brew install xcodegen   # один раз
./plugin-build.sh       # собрать extension + host, поставить в /Applications
```

Скрипт собирает `GtrBoard Plugin Host.app`, кладёт его в `/Applications`,
регистрирует AUv3 и прогоняет `auval`. Дальше в DAW:

**Audio FX → Audio Units → Andrey Ilin → GtrBoard**

В окне плагина — весь борд: 15 педалей, графический EQ, master, limiter,
bypass и feedback guard. Все ручки проброшены в параметры хоста для
автоматизации, состояние борда сохраняется вместе с проектом. Пресеты
выбираются в шапке плагина.

Ограничения: нужен полный Xcode и `xcodegen`; сборка ad-hoc и arm64. Свой WAV
для IR-кабинета импортируется только в standalone-приложении — AU не может
пересобрать свёртку во время рендера хоста. Подробности:
[`Plugin/README.md`](Plugin/README.md).

## <a id="architecture"></a>Архитектура

```
Sources/
  BoardCore/              # без Core Audio/AppKit: DSP, модели, пресеты
    DSP/                  # узлы эффектов, oversampler, reverb, limiter
    BoardSettings.swift   # полный снимок борда
    BuiltInPresets.swift  # 30 заводских ригов
  GtrBoard/
    Audio/                # HAL, aggregate-девайс, render callback, рекордер
    UI/                   # SwiftUI: педалборд, EQ, пресеты, футер
    AppModel.swift        # состояние, персистентность, импорт/экспорт
Tests/GtrBoardSelfTest/   # headless-проверки DSP и пресетов
```

**Real-time правила:** UI пишет снимок настроек в lock-protected буферы;
аудиопоток забирает его через `trylock`, без блокировок и аллокаций в
`process`. Все линии задержки и состояния фильтров выделяются в
`prepare(sampleRate:)`. Параметры сглаживаются; коэффициенты биквадов
интерполируются по сэмплам.

**Кроссфейд пресетов:** в процессоре две полные цепи (свои фильтры, EQ,
master, limiter). При смене пресета вторая цепь готовится и 50 мс
перекрёстно подмешивается; текущая цепь продолжает звучать и плавно уходит.

## <a id="tests"></a>Тесты

```bash
./test.sh
```

Проверяется:

- каталог эффектов и нормализация параметров;
- сериализация всех 30 заводских пресетов и tolerant-декодирование;
- запись/чтение/экспорт/импорт `.gtrpreset`;
- АЧХ биквадов и графического EQ;
- рендер всех заводских ригов: конечность, отсутствие клиппинга, сигнал;
- gate, compressor, drives, amp, delay, reverb, modulation;
- IR: библиотека кабинетов, свёртка против прямой конволюции, импорт WAV
  16/24/32-bit и float, живое переключение импульса;
- feedback guard: вой, сетевая наводка, низкий B рядом с 50/60 Гц, тишина,
  замкнутая акустическая петля и latched-мьют;
- bypass, master, limiter;
- кроссфейд: нет щелчка, нет провала в тишину, уровень не прыгает;
- валидность AI-примера из `docs/examples/`;
- пропускная способность: полный high-gain борд рендерится в ~60 раз быстрее
  реального времени на Apple Silicon.

Текущий прогон: **906 проверок**, все проходят.

## <a id="trouble"></a>Если что-то не так

| Симптом | Что сделать |
|---|---|
| Нет звука | Выберите вход и выход, нажмите питание; проверьте **No Input** и master |
| Щелчки/треск | Увеличьте буфер до 256–512; закройте тяжёлые приложения |
| Микрофон не разрешён | System Settings → Privacy & Security → Microphone → GtrBoard |
| Эхо/свист | Не используйте встроенные микрофон и колонки одновременно; наденьте наушники |
| Пресет не импортируется | Проверьте JSON: кавычки, запятые, нет ```-ограждений |
| Пресет тихий/громкий | Ползунок **PRESET** в футере; `outputTrim` в JSON |
| Устройство пропало | **Refresh Devices** в меню или перезапустите аудио питанием |
| Смена sample rate в Audio MIDI Setup | Перезапустите аудио кнопкой питания |

## <a id="limits"></a>Ограничения и планы

- нет AU/VST/AUv3 — только standalone;
- нет загрузчика IR/кабинетных импульсов; кабинет синтезирован фильтрами;
- нет тюнера, метронома, MIDI и scene/snapshot-слоя;
- вход обрабатывается как моно (первый канал);
- пресеты других вендоров не импортируются;
- ad-hoc подпись: для распространения нужен Developer ID и notarization.

Ближайшие планы: AUv3-обёртка, IR-загрузчик, тюнер, MIDI-педаль, scene-слой,
drag-and-drop педалей.

## <a id="license"></a>Лицензия

MIT. См. [LICENSE](LICENSE).

---

<div align="center">
<sub>Сделано для гитары, macOS и тишины между пресетами.</sub>
</div>
