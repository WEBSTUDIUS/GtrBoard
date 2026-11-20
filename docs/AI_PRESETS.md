# Пресеты GtrBoard с помощью ИИ

GtrBoard хранит пресеты в открытом JSON. Это значит, что пресет можно
**сгенерировать в любом чате с LLM** — ChatGPT, Claude, DeepSeek, Gemini — а
затем импортировать в приложение. Сам GtrBoard никуда не ходит в интернет и не
требует API-ключей: вы просто копируете JSON в файл.

> Это не «магический» импорт закрытых форматов. Модель пишет обычный
> `.gtrpreset`, а GtrBoard проверяет и клампит все значения при импорте.

## Коротко: три шага

1. Скопируйте промпт ниже в чат и опишите желаемый звук.
2. Сохраните ответ модели в файл `MyTone.gtrpreset` (UTF-8).
3. В GtrBoard: **⌘O** (Import) или **Browse Presets → Import**. Пресет
   появится в библиотеке; дальше его можно назначить в A/B.

Готовый пример: [`examples/ai-british-crunch.gtrpreset`](examples/ai-british-crunch.gtrpreset).

## Промпт

```text
Ты — гитарный звукорежиссёр. Сгенерируй ОДИН пресет для GtrBoard по описанию:
«тёплый британский кранч для хамбакеров, немного середины, лёгкий рум».

Верни ТОЛЬКО валидный JSON без markdown-разметки, комментариев и пояснений:

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
1. В units должны быть ровно 14 объектов kind в этом порядке:
   gate, compressor, boost, overdrive, distortion, fuzz, amp, cabinet,
   chorus, flanger, phaser, tremolo, delay, reverb.
2. Включай только нужные педали через enabled: true/false. Для ненужных
   параметры можно не указывать — возьмутся заводские значения.
3. Значения параметров — в реальных единицах: dB, Hz, ms; проценты 0…1.
   Диапазоны и ключи — в docs/AI_PRESETS.md.
4. Для переключателей используй индексы:
   amp.voicing: 0 Clean, 1 Crunch, 2 Lead, 3 High Gain;
   phaser.stages: 0=4, 1=6, 2=8, 3=12;
   tremolo.shape: 0 Sine, 1 Triangle, 2 Square;
   delay.mode: 0 Digital, 1 Analog, 2 Ping-Pong;
   reverb.mode: 0 Room, 1 Hall, 2 Plate.
5. graphicEQ.gains — ровно 10 чисел в dB, порядок:
   31.5, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Гц.
6. masterVolume: -60…12 dB; outputTrim: -24…24 dB.
7. Не добавляй поля id, createdAt, modifiedAt, isBuiltIn.
8. Никаких markdown-ограждений, только JSON.
```

> Если модель всё-таки обернула ответ в ` ```json ... ``` `, удалите
> ограждения и оставьте только содержимое от `{` до `}`.

## Справочник параметров

Все параметры необязательны: если ключ не указан, GtrBoard подставит
заводское значение. Лишние ключи и значения вне диапазона отбрасываются или
клампятся — «сломать» DSP пресетом нельзя.

### Порядок цепи

```
gate → compressor → boost → overdrive → distortion → fuzz → amp → cabinet
→ chorus → flanger → phaser → tremolo → delay → reverb
```

Порядок в массиве `units` задаёт порядок в цепи. Каждый `kind` должен
встречаться не более одного раза; отсутствующие единицы будут добавлены с
заводскими настройками, поэтому лучше перечислять все 14.

### Педали

| kind | Параметры (диапазон, заводское значение) |
|---|---|
| `gate` | `threshold` −80…−20 dB (−60), `decay` 20…1000 ms (180), `range` 0…80 dB (60) |
| `compressor` | `threshold` −60…0 dB (−24), `ratio` 1…20 (4), `attack` 0.5…100 ms (10), `release` 20…1000 ms (180), `makeup` 0…24 dB (6) |
| `boost` | `gain` 0…30 dB (9), `tone` −12…12 dB (0), `tight` 20…400 Hz (70) |
| `overdrive` | `drive` 0…40 dB (18), `tone` 0…1 (0.55), `level` −30…6 dB (−6), `mid` 0…1 (0.6) |
| `distortion` | `gain` 0…50 dB (26), `tone` 0…1 (0.55), `level` −30…6 dB (−8), `edge` 0…1 (0.5) |
| `fuzz` | `sustain` 0…1 (0.7), `tone` 0…1 (0.5), `level` −30…6 dB (−6), `bias` 0…1 (0.5) |
| `amp` | `gain` 0…40 dB (12), `bass`/`mid`/`treble` −12…12 dB (0), `presence` 0…12 dB (3), `master` −40…6 dB (−8), `voicing` 0…3 (1) |
| `cabinet` | `lowCut` 40…250 Hz (80), `highCut` 2000…12000 Hz (5500), `resonance` 0…12 dB (4) |
| `chorus` | `rate` 0.05…8 Hz (0.8), `depth` 0…1 (0.5), `mix` 0…1 (0.4), `width` 0…1 (0.7) |
| `flanger` | `rate` 0.02…5 Hz (0.25), `depth` 0…1 (0.6), `feedback` −0.95…0.95 (0.35), `mix` 0…1 (0.5), `manual` 0.5…10 ms (2.5) |
| `phaser` | `rate` 0.02…5 Hz (0.35), `depth` 0…1 (0.6), `feedback` 0…0.9 (0.3), `mix` 0…1 (0.5), `stages` 0…3 (1) |
| `tremolo` | `rate` 0.2…12 Hz (4.5), `depth` 0…1 (0.6), `shape` 0…2 (0), `stereo` 0…1 (0) |
| `delay` | `time` 20…1500 ms (380), `feedback` 0…0.95 (0.35), `mix` 0…1 (0.3), `tone` 0…1 (0.55), `mode` 0…2 (1) |
| `reverb` | `size` 0…1 (0.55), `damping` 0…1 (0.45), `mix` 0…1 (0.22), `predelay` 0…120 ms (20), `mode` 0…2 (1) |

### Переключатели

| Ключ | Значения |
|---|---|
| `amp.voicing` | `0` Clean · `1` Crunch · `2` Lead · `3` High Gain |
| `phaser.stages` | `0` 4 ступени · `1` 6 · `2` 8 · `3` 12 |
| `tremolo.shape` | `0` Sine · `1` Triangle · `2` Square |
| `delay.mode` | `0` Digital · `1` Analog · `2` Ping-Pong |
| `reverb.mode` | `0` Room · `1` Hall · `2` Plate |

### Глобальные поля

| Поле | Что это |
|---|---|
| `graphicEQ.gains` | 10 полос в dB, −12…12; порядок 31.5…16k Гц |
| `graphicEQ.enabled` | включён ли эквалайзер |
| `masterVolume` | общая громкость пресета, −60…12 dB |
| `outputTrim` | калибровка громкости пресета, −24…24 dB |
| `limiter` | look-ahead лимитер на выходе |
| `bypass` | пропустить обработку (обычно `false`) |

## Пример: что получается

Описание: «тёплый британский кранч для хамбакеров, чуть середины, лёгкий рум».

Модель возвращает JSON, где включены `boost`, `amp`, `cabinet` и `reverb`, а
остальные педали выключены. Полный файл:

[`examples/ai-british-crunch.gtrpreset`](examples/ai-british-crunch.gtrpreset)

Импортируйте его и покрутите **PRESET** в футере, чтобы подогнать уровень под
свою гитару и интерфейс.

## Как получить хороший результат

- **Описывайте звук как инженеру:** жанр, гитара/датчики, усилитель, степень
  гейна, тембр, эффекты, примерные исполнители. Чем конкретнее, тем лучше.
- **Просите несколько вариантов** («сделай 3 версии: меньше гейна, больше
  середины, с дилеем») и импортируйте все — сравните в A/B.
- **Не просите нормализованные 0…1** для громкости/частот: GtrBoard ждёт
  реальные dB/Hz/ms. Проценты (`tone`, `mix`, `depth`) — действительно 0…1.
- **`outputTrim` оставьте 0** при генерации. После импорта подстройте уровень
  ползунком **PRESET** — так громкость не будет прыгать между пресетами.
- **Проверяйте ушами.** Модель не слышит ваш тракт: один и тот же JSON на
  разных гитарах/интерфейсах звучит по-разному.
- **Не вставляйте в промпт секреты/API-ключи.** Генерация идёт во внешнем
  сервисе, а не в GtrBoard.

## Если импорт не сработал

| Симптом | Что проверить |
|---|---|
| «bad JSON» | Уберите ```-ограждения, проверьте двойные кавычки и запятые |
| Пресет пустой/тихий | Включены ли `amp` и `cabinet`; не стоит ли `bypass: true` |
| Слишком громко | Уменьшите `masterVolume`/`outputTrim` или ползунок PRESET |
| Нет эффекта | `enabled: true` у нужной педали и параметры в реальных единицах |
| Не тот порядок | Массив `units` задаёт порядок; перечислите все 14 kind в нужном порядке |

## Исходный формат

Пресет — это конверт:

```json
{
  "format": "com.andreyilin.gtrboard.preset",
  "version": 1,
  "preset": { "name": "...", "settings": { "units": [], "graphicEQ": {}, "masterVolume": -6, "outputTrim": 0, "limiter": true, "bypass": false } }
}
```

Поля `id`, `createdAt`, `modifiedAt`, `isBuiltIn` необязательны. При импорте
GtrBoard создаёт новый `id`, чтобы не перезаписать существующий пресет.
