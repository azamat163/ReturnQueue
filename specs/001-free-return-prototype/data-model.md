# Модель данных: контракт для реализации

## ReturnItem

- `id`: UUID, уникален; одинаковые названия допустимы.
- `title`, `merchant`: непустой текст после trim, до 120 символов каждое.
- `dropOffLocation`: необязательный текст до 200 символов; пустой после trim => отсутствует.
  Ключ группировки — trim + case-insensitive; адрес является частью текста, не геокодируется.
- `returnBy`, `purchaseDate`, `droppedOffDate`, `expectedRefundDate`: отдельные
  необязательные Gregorian дни `YYYY-MM-DD`, проверяется существование дня.
- `purchasePriceCents`, `expectedRefundCents`: необязательные Int, 0...100_000_000.
  Отсутствует != 0. USD явно хранится как валюта; другие валюты отклоняются в этой версии.
- `state`: planned / droppedOff / closed / kept.
- `closureOutcome`: fullRefund / partialRefund / denied / cancelled; обязателен при closed.
- `closureNote`: пояснение итога; обязательно при закрытии, если известное ожидание отличается от money + storeCredit
  (также при превышении); неизвестное ожидание не превращается в ноль.
- `notes`: текст до 4 000 символов.
- `policyReference`: необязательная заметка/ссылка до 1 000 символов, не открывается сама.
- `createdAt`, `updatedAt`: timestamps для истории и стабильной сортировки.
- `reimbursements`: список событий; их идентификаторы уникальны во всём архиве.
- `attachment`: отсутствует в P1; в P2 ссылка на внутреннюю копию и безопасный media type.

## Reimbursement

`id`, `returnItemID`, `date` (календарный день), `amountCents` (1...100_000_000),
`kind` (money / storeCredit), `note` (до 1 000 символов).
Отрицательные суммы и больше двух десятичных знаков не принимаются.
Ошибочное событие можно исправить или удалить, не добавляя отрицательную транзакцию.

Cash total = сумма только money. Credit total = сумма только storeCredit.
Known unresolved difference = expectedRefund - cash total - credit total; показывать
именно разницу, которая может быть отрицательной. Не называть её банковским долгом.
При неизвестном expectedRefund разница не вычисляется. Итоги поддаются переполнению:
использовать проверяемое целочисленное сложение и отклонять некорректный архив до записи.

## Summary [P2]: производное представление

Экранная подпись счётчика — `Returns reimbursed`: уникальные возвраты с положительной
записью Money или Store credit в периоде; это не число поступлений.

`period`: thisMonth / allTime. This month — текущие календарные год и месяц,
явно отображаемые в UI (demo Oct 2026). Отбор использует `Reimbursement.date`
как Gregorian календарный день, а не timestamp/дату покупки, сдачи или закрытия;
сохранённые дни не преобразуются через UTC при смене часового пояса.

- `moneyReceivedCents`: checked sum `amountCents` только kind=money в периоде.
- `storeCreditCents`: checked sum только kind=storeCredit в периоде.
- `returnsWithReimbursements`: мощность множества `returnItemID` выбранных событий
  с `amountCents > 0`; money и storeCredit одной вещи дают один ID.

События открытых/closed/kept записей участвуют одинаково, пока записи сохранены.
Ожидание, цена покупки и итог закрытия не входят в формулу. Empty period даёт
0/0/0 как отсутствие записанных событий. Нет поля savedMoney, банковского баланса
или финансового итога cash+credit. После добавления/редактирования/удаления события,
удаления вещи или replacement расчёт строится заново из текущих данных.
Summary не является самостоятельной сущностью хранения и не экспортируется как источник.

Контроль demo: allTime money=21_000 cents, credit=8_000 cents, count=4;
Oct 2026 money=16_000 cents, credit=8_000 cents, count=4. Jacket money Sep 30
не входит в October; его credit Oct 2 входит и сохраняет участие jacket в count.

## LocalSettings / Reminder [P2]

Локальный профиль — настройки устройства, без user account, email, avatar или backend.
`LocalSettings` сохраняет `remindersGloballyEnabled` (default false),
`defaultHour`/`defaultMinute` (09:00), `defaultLeadDays` (1; доступно 0 или 1).
Defaults копируются в новый явно включённый Reminder; прежние параметры вещи
не меняются без явного редактирования. OS permission хранится/читается устройством
отдельно и не входит в transferable settings.

Reminder принадлежит `returnItemID` и содержит `enabled` (default false),
`kind` (returnReminder / refundCheck), `hour`/`minute` местного wall-clock времени
(hour 0...23, minute 0...59). Для returnReminder: `leadDays` (0/1), цель —
`returnBy - leadDays` календарных дней; Return by обязателен, применимо только planned.
Для refundCheck: отдельно введённый `checkDate` Gregorian CalendarDay, применимо
только droppedOff; не выводится автоматически из returnBy/expectedRefundDate.
При смене kind предыдущий запланированный запрос отменяется; конфигурация всегда
соответствует одному выбранному типу, автоматической смены типа после сдачи нет.

Выбор `enabled` сохраняется при global off, отказе устройства или отсутствии даты,
но `Scheduled` — производное состояние: оба opt-in включены, фактическое разрешение
допускает уведомления, тип соответствует state, дата существует, время ещё впереди
и системный запрос успешно создан. Ошибка планирования не выдаётся за Scheduled.
UI показывает Not scheduled с причиной, а не стирает предпочтения пользователя.
Removal Return by при прежнем opt-in отменяет планирование; включить новый relative
reminder без даты нельзя. Закрытие/kept/delete отменяет уведомления вещи.

Дедлайн хранится как CalendarDay и не сдвигается при travel; заданные 09:00 остаются
09:00 в текущем местном часовом поясе. Правки и travel/restore обновляют будущую цель,
прошедшие не воспроизводятся. Preview включает item title, deadline или Not set,
дату/local time и причину отсутствия расписания. Notification payload связывает ID
для открытия деталей; видимый текст нейтрален. При отсутствующей/недоступной записи
открывается Queue. Scheduled не гарантирует delivery OS.

## Состояния и исправления

planned -> droppedOff -> closed. Из planned/droppedOff можно выбрать kept.
Закрытие не происходит автоматически. Коррекция состояния возможна из любого состояния;
данные не исчезают. При повторном открытии closureOutcome больше не является активным
итогом, прежняя заметка сохраняется как история/заметка. Reimbursement не удаляется.
Сдача не означает подтверждения магазином; для MVP отдельного состояния accepted нет.

## Backup

Версия формата независима от версии приложения. P1 содержит JSON всех поддерживаемых
полей; P2 — полный контейнер со снимками, manifest и безопасными относительными путями,
LocalSettings и Reminder-параметрами вещей. Permission и OS request IDs не переносятся;
Summary пересчитывается после restore. Старые уведомления отменяются после replacement,
новые будущие цели зависят от восстановленного выбора и текущего разрешения устройства.
Старая версия не теряет данные при открытии нового архива: неподдерживаемая версия
отклоняется. Миграция описывается отдельно, когда появляется новый формат.

Рабочие лимиты: до 10 000 записей, 10 000 reimbursement events суммарно; P1 JSON до 20 MiB.
P2 один декодируемый снимок до 15 MiB на запись, полный архив до 100 MiB. Эти лимиты
защищают от случайного гигантского импорта, не являются платными ограничениями.

## Первый P1 slice

Прежний черновик с обязательными Date/location, одним amountCents и требованием
полного refund не является совместимым форматом. Точный P1 JSON v1 и Swift API
фиксированы в [backup contract](contracts/backup.md); старый draft v1 отклоняется
по marker/полям, не мигрирует молча. Первые Core/codec тесты проверяют эту модель
независимо от UI. Filesystem draft вынесен в Services/ReturnQueueStorageDraft;
его наличие не завершает T005 или полное atomic replacement acceptance.
Модель принята после независимых review и native XCTest (49/49 PASS);
это не доказывает готовность UI/storage или всего iOS-приложения.
