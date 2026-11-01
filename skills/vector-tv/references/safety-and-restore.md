# Стоп-список, причины и порядок отката

Знание собрано из скриптов `Gathin23/cleanyourtv` и их комментариев с номерами issue: у проекта
нет явной лицензии (GitHub показывает NOASSERTION), поэтому код и тексты оттуда НЕ переносятся.
Ниже — перечень имён пакетов и причин, изложенный заново: имена пакетов — факты об Android,
причины — по номерам issue, куда и надо смотреть за деталями.

## Пакеты, которые не отключаются никогда

| Пакет | Почему нельзя |
|---|---|
| `android` | сам фреймворк |
| `android.ext.services`, `android.ext.shared` | AOSP-имена тех же ext-служб (на части прошивок без префикса) — #1711 |
| `com.android.sdksandbox` | защищён: причина падения загрузки не подтверждена — #2557 |
| `com.android.location.fused` | TCL 43S5400A ушёл в цикл загрузки в recovery — #2803 |
| `com.android.systemui` | системный интерфейс: без него нет экрана |
| `com.android.shell` | оболочка, через неё же идёт сам ADB |
| `com.android.phone` | телефония/сеть |
| `com.android.settings`, `com.android.tv.settings` | настройки: без них не вернуть ничего |
| `com.android.permissioncontroller`, `com.google.android.permissioncontroller` | Mi TV Stick не загрузился — #884 |
| `com.android.packageinstaller`, `com.google.android.packageinstaller` | установка и удаление приложений — #884 |
| `com.android.ext.services`, `com.android.ext.shared`, `com.google.android.ext.services`, `com.google.android.ext.shared` | расширенные службы Android — #884 |
| `com.google.android.modulemetadata`, `com.android.modulemetadata` | метаданные модулей — #884 |
| `com.google.android.overlay.modules.*` | mainline-оверлеи: с ними система теряет ресурсы — #884 |
| `com.android.providers.*` | контент-провайдеры; исключение ниже |
| `com.cltv.mal` | MediaTek MAL: Haier H50H5F ушёл в цикл перезагрузок — #1578 |
| `com.mediatek.tis`, `com.mediatek.tv.service`, `com.mediatek.tv.agent` | middleware телевизора — #1578 |

Можно отключать только эти провайдеры — ими не пользуется ни одна функция ТВ:
`com.android.providers.calendar`, `.contacts`, `.userdictionary`, `.blockednumber`.

## Что случалось у людей

| № | Пакет | Что было |
|---|---|---|
| #884 | permission controller, package installer, ext services, module metadata, mainline overlays | оригинальный Mi TV Stick больше не загрузился |
| #1578 | `com.cltv.mal` | Haier H50H5F в цикле перезагрузок; список AQUA MatrixTV держит все четыре `mediatek`-пакета |
| #2803 | `com.android.location.fused` | TCL 43S5400A (V325) в цикле загрузки в recovery |
| #1711 | `android.ext.services`, `android.ext.shared` | часть прошивок ставит их под голыми именами AOSP |
| #239 | пакет, отвечающий HOME | HOME нажимается — стартовать нечему; на Google TV setup wizard забирает категорию и роняет system_server |
| #2557 | `com.android.sdksandbox` | причина падения загрузки не подтверждена, пакет защищён |

## Порядок отключения (безопасный)

1. Бэкап (`tv-inventory.sh inventory`) — список включённых, отключённых, HOME, анимации, свойства.
2. Один пакет за раз: `pm disable-user --user 0 <pkg>`, затем посмотреть на телевизор.
3. После каждого десятка — перезагрузка и проверка: сеть, пульт, HOME, звук.
4. Лончер: новый поставить и проверить, старый отключить последним.
5. Отладку выключить последней.

## Порядок отката

```bash
# всё, что было включено до работы, включается обратно; отключённое ранее — не трогается
scripts/tv-inventory.sh restore <ip> tv-inventory-<метка>
```

Ручной минимум:

```bash
adb -s <ip>:5555 shell pm enable --user 0 <pkg>            # вернуть пакет
adb -s <ip>:5555 shell pm list packages -d                 # что сейчас отключено
adb -s <ip>:5555 shell 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
```

Если штатный лончер отключён, а свой не работает — включить штатный (`pm enable --user 0
com.google.android.tvlauncher`), перезагрузить, и только потом разбираться с новым.

## Уровни риска по типам пакетов

| Тип | Примеры | Риск |
|---|---|---|
| Реклама и рекомендации | `*.recommend*`, `*.ads*`, `*.promo*` | низкий, возвращается без последствий |
| Аналитика и телеметрия | `*.analytics*`, `*.telemetry*`, `*.tracker*` | низкий |
| Предзагруженный контент | магазины, игры, музыка, новости бренда | низкий-средний: часть приложений могла быть куплена по подписке |
| Системные службы вендора | `*.service*`, `*.agent*`, `*.mal`, `*.tis` | **высокий**: цикл загрузки |
| Ядро Android | стоп-список выше | **запрещено** |
