# DotaMind → Android: спецификация для порта

Документ для переноса на Android (Kotlin + Jetpack Compose + Material 3). Логика и данные переносятся 1:1, меняется только оформление. В коде iOS места замены помечены комментариями `// ANDROID (Material 3): …` (или `// ANDROID: …`, где Material 3 ни при чём). Найти все: `grep -rn "ANDROID" DotaMind DotaMindWidget`.

**Пометка «M3»** в таблицах ниже означает: здесь iOS Liquid Glass → компонент Material 3.

---

## 1. Стек

| iOS | Android |
|---|---|
| SwiftUI | Jetpack Compose + Material 3 |
| `@Observable` `PlayerStore` | `ViewModel` + `StateFlow<UiState>`, один на аккаунт (activity-scoped) |
| `async let` / `TaskGroup` | `coroutineScope { async { } }` / `awaitAll` |
| `actor OpenDotaClient` | Ktor или Retrofit + kotlinx.serialization, `Mutex` для кэша |
| `URLCache` + `AsyncImage` | Coil (`AsyncImage`) с дисковым кэшем |
| Keychain | DataStore + Android Keystore (или EncryptedSharedPreferences) |
| `UserDefaults` / `@AppStorage` | DataStore Preferences |
| Swift Charts | Vico (`com.patrykandpatrick.vico:compose-m3`) |
| CoreMotion | `SensorManager`, `TYPE_GRAVITY` |
| Metal-шейдер | AGSL `RuntimeShader` (Android 13+) |
| WidgetKit | Jetpack Glance |
| BGAppRefresh + UserNotifications | WorkManager + `NotificationCompat` |
| `ImageRenderer` + `ShareLink` | `rememberGraphicsLayer().toImageBitmap()` + `Intent.ACTION_SEND` через `FileProvider` |
| `ASWebAuthenticationSession` | Custom Tabs + intent-filter `dotamind://auth/steam` |

## 2. Экраны и M3-компоненты

Нижняя навигация: **Профиль · Матчи · Драфт · Настройки**.

| Место | iOS | Android (Material 3) |
|---|---|---|
| Навигация | `TabView` (стекло, сворачивается при скролле) | **M3** `NavigationBar` на телефоне; `NavigationRail` при `WindowWidthSizeClass.Medium/Expanded` |
| Переключатель режима Turbo/Обычные/Все | сегментированный `Picker` | **M3** `SingleChoiceSegmentedButtonRow` |
| Все «стеклянные» секции (`GlassSection`, `StatTile`, `MetricStrip`, советы) | `.glassEffect` | **M3** `ElevatedCard` / `Card(colors = surfaceContainerHigh)` |
| Полосы винрейта (`WinrateBar`, `GlassFill`) | плоское стекло | **M3** `LinearProgressIndicator(strokeCap = Round)`, трек `surfaceContainerHighest` |
| Победы/поражения | две стеклянные капсулы | два сегмента прогресса (tertiary / error) |
| Плашка «показан снимок» | стекло с золотым тоном | **M3** `Card(containerColor = secondaryContainer)` + иконка `CloudOff` |
| Кнопки (`.glass`, `.glassProminent`) | Liquid Glass | **M3** `FilledTonalButton` / `Button` |
| Листы (сравнение, выбор героя, карточка) | `.sheet` | **M3** `ModalBottomSheet` (на планшете — `Dialog`) |
| Поиск героя | `.searchable` | **M3** `SearchBar` / `DockedSearchBar` |
| Настройки | `Form` | `LazyColumn` из **M3** `ListItem` + `Switch` |
| Тиммейты, сортировка | сегменты | **M3** `SegmentedButton` |
| Слоты драфта | пунктирные плитки | **M3** `OutlinedCard` / `InputChip` с крестиком |
| Причины в драфте («vs Pudge 5–1») | капсулы | **M3** `AssistChip` / `SuggestionChip` |
| Достижения | плитки с «металлом» | **M3** `ElevatedCard`; уровни — tonal-цвета |
| Pull-to-refresh | `.refreshable` | **M3** `PullToRefreshBox` |
| Индикатор обновления в тулбаре | `ProgressView` | `CircularProgressIndicator` в `TopAppBar` |

Голографическая карточка остаётся своей (не Material). Как её перенести:
- **Фольга:** AGSL `RuntimeShader`, код `HoloFoil.metal` переносится почти построчно, параметры `size`, `tilt`, `time`, `strength`. Ниже Android 13 — без фольги.
- **Наклон:** `graphicsLayer { rotationX; rotationY; cameraDistance = 12 * density }`.
- **Рамка:** `Brush.sweepGradient` (радуга из 13 оттенков), анимация через поворот оттенка или угла.
- **Свечение:** `Modifier.blur(18.dp)` под карточкой, рисуется один раз.
- **Переворот по тапу:** `rotationY` 0→180, сторона меняется на 90°.

**Колонки профиля — по ширине окна, не по типу устройства:**
- `< 700dp` — одна колонка;
- `< 1150dp` — две (карточка + рекорды + достижения | сводка + рейтинг + форма + герои);
- иначе — три.

Это же покрывает складные телефоны.

### Тема (`Theme.swift`)

- Только тёмная тема, **Dynamic Color выключить**: у приложения свой бренд.
- `primary` = золото `#FAC25C` (0.98, 0.76, 0.36).
- Победа = изумруд `#3DB385` (0.24, 0.70, 0.52), поражение = гранат `#CC4D57` (0.80, 0.30, 0.34).
- Цвет винрейта (`winrateColor`):
  - ≥ 55 % — изумруд;
  - 50–55 % — изумруд, смешанный с 30 % белого;
  - 45–50 % — серебро `#B8B8B8`;
  - < 45 % — гранат.
- Атрибуты героев: сила `#ED5240`, ловкость `#4DD973`, интеллект `#4D9EFF`, универсальные `#D999FF`.
- Шрифт: системный (Roboto / Roboto Flex), цифры табличные (`fontFeatureSettings = "tnum"`).
- Фон экранов: почти чёрный `#0A0A12`. Сверху размытый арт главного героя: blur 60, прозрачность 32 %, высота 480. Вниз градиент в тёмный.

---

## 3. OpenDota API

База: `https://api.opendota.com/api`. Без ключа ~60 запросов в минуту, при превышении отвечает `429`.

### ⚠️ Главное: Turbo и `significant`

Эндпоинты игрока по умолчанию считают только «significant» матчи, **Turbo к ним не относится**. Без `significant=0` запрос `game_mode=23` вернёт 0 игр.

| Режим | Параметры |
|---|---|
| Turbo | `game_mode=23&significant=0` |
| Обычные | (ничего — дефолт OpenDota) |
| Все | `significant=0` |

### Идентификаторы

- `account_id` (он же Friend ID) = SteamID64 − `76561197960265728`.
- Вход: SteamID64, Friend ID или ссылка `steamcommunity.com/profiles/<id64>` / `opendota.com/players/<id>`. Короткие ссылки `/id/имя` не поддерживаются.

### Запросы (`{q}` — параметры режима)

| Что | Запрос | Где |
|---|---|---|
| Профиль | `players/{id}` | ник, аватар, `rank_tier` |
| Победы/поражения | `players/{id}/wl?{q}` | карточка, сводка |
| Герои | `players/{id}/heroes?{q}` | список, советы, драфт |
| Герои за 30 дней | `…/heroes?{q}&date=30` | совет «в форме» |
| Средние | `players/{id}/totals?{q}` | K/D/A, GPM, XPM, длительность (`sum/n`) |
| Стороны | `players/{id}/counts?{q}` → `is_radiant["1"/"0"]` | совет Radiant/Dire |
| Последние матчи | `players/{id}/matches?{q}&limit=100` | вкладка «Матчи» |
| Тиммейты | `players/{id}/peers?{q}` | напарники, сравнение |
| Соло/пати | `players/{id}/wl?{q}&party_size=1…5` | напарники (размер пати известен ~у трети матчей) |
| Форма | `…/matches?{q}&date=84&project=start_time` | график по неделям |
| Рекорды | `…/matches?{q}&sort=<поле>&limit=1&project=<поле>&project=hero_id&project=start_time` | поля: kills, assists, gold_per_min, hero_damage, last_hits, duration |
| Турбо-история | `…/matches?game_mode=23&significant=0&project=average_rank&project=start_time` | турбо-рейтинг, серия (~400 КБ) |
| Страница героя | `totals`, `matches&limit=20`, `heroes` — всё с `&hero_id=X` | средние, игры, противники/союзники |
| Предметы на герое | `…/matches?{q}&hero_id=X&limit=100&project=item_0…item_5` | «с чем ты выигрываешь» |
| Бенчмарки | `benchmarks?hero_id=X` | «ты против всех» (не в Turbo!) |
| Драфт | `…/heroes?{q}&against_hero_id=E` / `&with_hero_id=A` — по запросу на героя | драфт |
| Матч | `matches/{match_id}` | детали матча |
| Разбор матча | `POST request/{match_id}` | кнопка «Разобрать» |
| Обновить историю | `POST players/{id}/refresh` | настройки |
| Справочник героев | `heroStats` (~1 МБ, кэш 7 дней) | имена, картинки, атрибуты |
| Справочник предметов | `constants/items` (~350 КБ, кэш 7 дней; ключ — имя, внутри `id`) | иконки предметов |

`project=` **заменяет** набор полей ответа. `match_id`, `player_slot`, `radiant_win`, `game_mode` приходят всегда.

Победа игрока: `radiant_win == (player_slot < 128)`.

### Картинки

- Герой: `https://cdn.cloudflare.steamstatic.com` + `img` из heroStats (256×144).
- Предмет: тот же CDN + `img` из constants/items, без `?t=…`.
- Ранг: `https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_{медаль}.png` + звёзды `rank_star_{1…5}.png` поверх. `rank_tier` = медаль×10 + звёзды. Для Immortal (8) звёзд нет.

### Кэш и загрузка

- **Политики:**
  - `normal` — память ≤ 5 мин, иначе сеть;
  - `cacheOnly` — диск любой давности;
  - `reload` — всегда сеть.
- **Если сети нет:** старый диск, потом офлайн-снимок (только в отладке).
- **Порядок запуска:**
  1. Мгновенно показать всё из диска (`cacheOnly`).
  2. Обновить из сети в три этапа:
     - **быстрый:** wl, heroes, matches — после него уже видна карточка;
     - **тяжёлый:** totals, heroes30, counts, peers;
     - **дополнительный:** форма, рекорды, соло/пати, турбо-история.

  Ошибка во 2-м или 3-м этапе не ломает экран.

---

## 4. Формулы

### Советы (`Models/Insights.swift`)

Пороги — минимальная выборка, чтобы не советовать по 2 играм:

| Совет | Условие |
|---|---|
| Серия | ≥ 3 одинаковых результата подряд в последних матчах |
| В форме | герой за 30 дней: ≥ 5 игр, винрейт ≥ 55 % (берём лучший) |
| Сильнейший герой | ≥ 30 игр, винрейт ≥ 52 % |
| Не идёт | ≥ 20 игр, винрейт < 47 % (худший) |
| Неудобный противник | ≥ 30 игр против, винрейт против < 46 % |
| Лучший тиммейт | ≥ 10 игр вместе, винрейт ≥ 50 % |
| Быстрые/затяжные игры | граница «короткой» и «длинной» игры: Turbo 20/30 мин, иначе 30/45; ≥ 8 игр в каждой группе; разница ≥ 8 п.п. |
| Сторона | ≥ 30 игр за каждую, разница ≥ 4 п.п. |

### Турбо-рейтинг (`Models/TurboRating.swift`)

Valve не считает рейтинг в Turbo. Это оценка по системе Elo.

1. Берём Turbo-матчи с `average_rank > 0` (~97 %), сортируем по времени. Нужно минимум 30.
2. Перевод медали в MMR:
   - Herald…Ancient: `(медаль−1)×770 + (звёзды−1)×154 + 77`;
   - Divine: `4620 + (звёзды−1)×200 + 100`;
   - Immortal: `5620`.

   Обратный перевод — в `RankMMR.tier(forMMR:)`.
3. Стартовый рейтинг R = средний MMR лобби первых 20 матчей.
4. Для каждого матча:
   - L = MMR лобби;
   - ожидание E = 1 / (1 + 10^((L − R)/400));
   - K = 40 для первых 100 матчей, дальше 25;
   - R += K × (результат − E), где результат 1 за победу и 0 за поражение.
5. Дополнительно считаем:
   - изменение за 30 дней;
   - средний MMR лобби последних 100 игр;
   - лучшую серию побед;
   - историю по неделям (последнее значение недели, 26 недель).

Пример (аккаунт 1251170799): ≈ 1428, это Guardian 5, по 3282 матчам.

### Драфт (`Models/Draft.swift`)

1. Сглаживание к 50 % через «виртуальные» игры, prior = 10:
   `base = (wins + 10×0.5) / (games + 10)`.
2. Для каждого выбранного врага E (запрос `against_hero_id=E`) и союзника A (`with_hero_id=A`) берём твою запись на кандидате:
   - `vs = (wins + 10×base) / (games + 10)`;
   - `delta = vs − base`.
3. `score = base + Σ delta`, ограничен диапазоном 0…1.
4. Кандидаты: от 5 игр, не занятые в драфте. Сортировка по score, показываем топ-10.

### Предметы на герое

- Последние 100 матчей на герое, итоговые 6 слотов, без повторов.
- Только предметы с ценой ≥ 1000. Справочник предметов загрузить **до** подсчёта: на iOS здесь был баг гонки.
- Минимум игр с предметом: max(3, число_матчей/10).
- Из 8 самых частых — сортировка по винрейту.

### Бенчмарки (не для Turbo: золото и опыт там ×2)

- Твои значения: gold_per_min, xp_per_min, last_hits_per_min, hero_damage_per_min, kills_per_min. «В минуту» = среднее / (средняя длительность / 60).
- Медиана — точка с percentile ≥ 0.5.
- Твой перцентиль — последняя точка, где value ≤ твоего значения.

### Достижения (`Models/Achievements.swift`)

Четыре уровня: бронза, серебро, золото, легенда.

| Достижение | Значение | Пороги |
|---|---|---|
| Ветеран | матчей | 500 / 1000 / 2500 / 5000 |
| Победитель | побед | 250 / 500 / 1000 / 2500 |
| Мастер героя | игр на самом частом герое | 50 / 100 / 250 / 500 |
| Коллекционер | разных героев | 25 / 50 / 100 / 120 |
| В огне | лучшая серия побед (Turbo — вся история; иначе — последние 100) | 5 / 7 / 10 / 15 |
| Убийца | рекорд убийств | 15 / 20 / 30 / 40 |
| Миллионер | лучший GPM | 800 / 1200 / 1800 / 2500 |
| Марафонец | самый долгий матч, мин | 45 / 60 / 75 / 90 |
| Восхождение (только Turbo) | турбо-рейтинг | 1540 / 2310 / 3080 / 3850 |

### График формы

- Группировка по ISO-неделям за 12 недель.
- Шкала Y — по разбросу: `[min−8 п.п., max+8 п.п.]`, всегда включает 50 %, округление до 5 %.
- Площадь графика — от нижней границы шкалы, не от нуля.

---

## 5. Фоновые задачи и виджет

### Уведомление после матча

- Раз в ≥ 15 мин (WorkManager) запрашиваем `players/{id}/matches?significant=0&limit=5`.
- Новые = `match_id` больше сохранённого. Первый запуск только запоминает последний матч.
- Текст: «Победа · Troll Warlord», ниже «12/3/9 · Turbo · 24:10».
- Если среди новых есть Turbo: пересчитываем турбо-рейтинг и добавляем «Турбо-рейтинг ≈1440 (+12)».
- Не больше 3 уведомлений за раз.

### Виджет (Glance)

- Размеры small и medium: режим, винрейт, W–L, точки последних 10 игр, в medium ещё 4 последних матча.
- Friend ID и режим задаются в конфигурационной Activity. На iOS тоже так: нет общей группы с приложением.
- Обновление раз в 30 минут.

---

## 6. Что не доделано на iOS (учесть в порте)

- **Вход через Steam OpenID** — заглушка, всегда один аккаунт. Steam может не принять кастомную схему в `openid.return_to`; тогда нужен https-редирект. Для продакшена проверять подпись через `check_authentication`.
- **Гироскоп, виджет и фоновые уведомления** на реальном устройстве не проверены.
- **Офлайн-снимок** (`DotaMind/DemoData`, `Scripts/make_demo_data.py`) — отладочный инструмент, в релиз не попадает. Скрипт пригодится и для Android-тестов: те же JSON-ответы.
