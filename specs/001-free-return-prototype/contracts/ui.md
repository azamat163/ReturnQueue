# Контракт экранов и действий

## P1

1. **Queue**: пустое состояние, Add, группы мест; карточка с названием, магазином,
   введённой датой и понятным неизвестным значением. Сортировка spec FR-008/010.
2. **Waiting for refund**: сданные активные вещи, раздельные cash/credit и известная
   разница. Никаких индикаторов проверки банком или ложной просрочки.
3. **History**: closed/kept, итог и даты; доступно исправление и удаление с подтверждением.
4. **Detail / Add / Edit**: одни и те же определения полей; Save проверяет и сохраняет,
   Cancel не меняет объект. Сдача/закрытие — явные действия с датой/итогом.
5. **Data & backups**: export, preview restore, confirm replace, delete all;
   описание локального хранения и бесплатного режима.

Ошибка сохранения не закрывает форму как успешно сохранённую. Неизвестные данные
не маскируются нулём/сегодняшним числом. При ошибке чтения обычные изменения заблокированы,
можно повторить чтение или экспортировать исходный файл.

Статусы имеют текст и значок, поддерживают VoiceOver/Dynamic Type. Экран не запрашивает
карту, адрес пользователя, банковский логин или email. Основные цели нажатия — не менее
44pt; объём текста не обрезает критические значения и ошибки.

## P2

Фото выбирается конкретно, preview/remove не изменяет оригинал Photos. Напоминания
настраиваются после интереса пользователя, а не при первом запуске. Уведомление:
`You have a return to check. Open Return Queue for details.` Без деталей покупки.
Состояние разрешений показывается правдиво; отказ не блокирует журнал.

### Summary [US7]

Доступна из навигации P2; переключатель `This month` / `All time`. Для This month
явно подписан текущий календарный месяц, demo `Oct 2026`. Три независимых значения:
`Money received`, `Store credit`, `Returns reimbursed`. Подпись:
`Based on reimbursements you've recorded.` Не показывать прогноз, банковский баланс
или единый денежный итог money+credit.

Отбор — календарный `Date received` события, не дата покупки/сдачи/закрытия.
Число — distinct ReturnItem IDs с положительным событием выбранного периода,
включая активные и завершённые записи; credit-only тоже считается. Unknown expected
не мешает включению записанного события. После edits/deletes/restore результат обновляется.
Пустой период: $0.00 / $0.00 / 0, `No reimbursements recorded for this period.`

Контроль demo: All time $210.00 money + $80.00 credit / 4 returns;
This month Oct 2026 $160.00 money + $80.00 credit / 4 returns. Jacket Money $50 Sep 30
исключается из октября; его Store credit $30 Oct 2 остаётся.

### Settings и локальный профиль [US6]

P2 нижняя панель содержит **ровно четыре вкладки**: `Queue`, `Waiting`, `History`,
`Summary`. `Settings` открывается через шестерёнку; пятой вкладки нет.
Settings не вводит login/account: раздел `Local profile`, подпись
`On this iPhone. No account or sync.` Без auth/email/avatar/backend.
Ссылка `Data & backups` открывает существующий P1 экран копий и удаления.

Раздел `Reminders`: общий switch `Enable reminders` (default off), отдельно
`Device permission` с реальным состоянием, `Default time` (9:00 AM local),
`Default timing` (1 day before; альтернатива On return date). Defaults применяются
к новым явно включаемым напоминаниям, уже выбранные параметры вещи не меняются молча.
При отказе есть `Open iPhone Settings`; switch сам не утверждает получение разрешения.
Global off отменяет расписание, сохраняя switches вещей; global on учитывает текущие
разрешения, состояния и только будущие даты. Первый запрос разрешения — после opt-in.

`Upcoming reminders` показывает item name, Return by или Not set, дату и local time,
`Scheduled` / `Not scheduled` и причину. При global off, missing date, denied,
past target или неверном state нет ложной активной строки. Статус Scheduled относится
к созданному системному запросу и не гарантирует delivery; подпись
`Delivery depends on your iPhone settings.` Это внутриприкладной preview, не lock screen.

### Item reminder [US6]

Из деталей вещи доступно `Item reminder`; switch `Remind me about this item`
(default off), тип `Return reminder` / `Check refund` по применимому состоянию.
Relative Return reminder требует вручную заполненный Return by и To return:
`Remind me` — `1 day before` / `On return date`, `Time` — редактируемое local time.
Без дедлайна `Add a return date first.` и возможность перейти к редактированию,
но никакой придуманной даты. Refund check в Waiting требует отдельного поля
`Check date`; его не выводят из дедлайна или Expected refund date.

Preview: item name, `Return by`, `Reminder date`, `Time`, правдивый статус и причина;
`Cancel` не меняет конфигурацию, `Save` сохраняет выбор с актуальным расписанием.
Правки срока/времени/типа, сдача/closure/delete, toggles, permission, travel и restore
пересогласуют будущие события; заданные календарные дни и wall-clock время сохраняют
свой смысл. Нажатие notification открывает точные детали по ID, а при недоступном
объекте — безопасную Queue. При закрытии нет старых уведомлений, при путешествии нет
потока catch-up. OS permission не переносится с архивом.
