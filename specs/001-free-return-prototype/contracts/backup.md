# Контракт переноса и восстановления

Экранное имя: `Data & backups`; Settings открывается через шестерёнку, а из него
доступен экран копий данных. Дополнительная вкладка для настроек не добавляется.

P1: portable JSON, version=1, records с reimbursement и day-only датами. UTF-8,
ограничение 20 MiB, до 10 000 записей и 10 000 событий; никаких произвольных Swift типов.
Точный ключевой JSON-контракт P1 фиксирован ниже для T002/T003 до первой записи реальных данных.

## Точный JSON v1 и публичный API P1

Машиночитаемая структура: [backup.schema.json](backup.schema.json). JSON Schema
описывает форму; существование календарного дня, уникальность ID, связи и правила
закрытия дополнительно проверяет Swift codec. Все перечисленные ключи обязательны;
неизвестные ключи запрещены на каждом уровне. Неизвестное значение — явный `null`,
не пропущенный ключ, пустая строка, нулевая сумма или автоматически подставленная дата.
Только UTF-8 JSON object без trailing содержимого и повторных ключей object;
глубина JSON ограничена 64 уровнями для безопасного отказа malicious input; числовые поля — JSON integers,
не строки/boolean/fraction/exponent. Превышение лимита проверяется до JSON decode.

Envelope: `format` = `com.azamat163.returnqueue.p1`, `version` = 1, `records` = array.
Маркер формата обязателен: прежний черновик `{version:1,items:[...]}` никогда не
переинтерпретируется как этот v1. Черновик не был выпущен; автоматической миграции нет.
Другой marker или version отклоняет весь архив без записи на диск.

ReturnItem keys: `id`, `title`, `merchant`, `dropOffLocation`, `returnBy`,
`purchaseDate`, `droppedOffDate`, `expectedRefundDate`, `purchasePriceCents`,
`expectedRefundCents`, `currency`, `state`, `closureOutcome`, `closureNote`, `notes`,
`policyReference`, `createdAt`, `updatedAt`, `reimbursements`.
`currency` = `USD`; эта валюта применяется и ко всем событиям записи.
UUID — строка стандартной формы 8-4-4-4-12 hex; регистр hex не меняет идентификатор.
Календарные дни — `YYYY-MM-DD` (Gregorian, годы 0001...9999) либо `null`.
Суммы цены/ожидания — 0...100000000 либо `null`; текстовые необязательные значения
location/policy/closureNote — непустые строки после trim либо `null`.
Состояния `planned`, `droppedOff`, `closed`, `kept`; closure outcomes
`fullRefund`, `partialRefund`, `denied`, `cancelled` либо `null`.

Reimbursement keys: `id`, `returnItemID`, `date`, `amountCents`, `kind`, `note`.
Дата обязательна; amount 1...100000000; kind `money` или `storeCredit`; note — строка,
включая пустую. `returnItemID` должен совпадать с родительским record.id; event IDs
уникальны во всём архиве. Record IDs также уникальны, но принадлежат отдельному
пространству идентификаторов от event IDs. До 10000 records и 10000 events суммарно.

`createdAt`/`updatedAt` — signed Unix milliseconds, от -62135596800000 до
253402300799999 включительно. Их порядок не ограничивается: часы устройства
могут корректироваться. Это реальные instants,
календарные дни через них не кодируются. Domain inputs `Date` после проверки
finite/range нормализуются к ближайшей миллисекунде; архив содержит целые milliseconds.
Текстовые лимиты считаются Swift String.count (extended grapheme clusters), после trim:
120 title/merchant, 200 location, 4000 notes, 1000 policy/closureNote/event note.
`validated()` нормализует ввод формы (внешние whitespace/newlines, empty optional -> nil);
encoder пишет нормализованные значения. Decoder принимает только такую каноническую
форму, отклоняет whitespace/empty optional вместо молчаливого исправления импорта.

При `closed` outcome обязателен. Если expectation известен и отличается от суммы
money + storeCredit (включая превышение), closureNote обязательна. Неизвестное
expectation остаётся `nil`, полнота не выводится; outcome выбирается вручную.
Во всех остальных состояниях closureOutcome = null; прежняя closureNote может
оставаться как история после коррекции состояния. События при смене состояния
не удаляются. `droppedOffDate` остаётся optional; команды будущего T010 назначат
её при сдаче. В этой задаче нет автоматических переходов или подтверждения excess.

Публичный Swift контракт для пакета `ReturnQueueCore`:

- `CalendarDay`: immutable year/month/day, `init(year:month:day:) throws`,
  `init(iso8601:) throws`, `iso8601: String`, `Comparable`, `Codable` single string.
- `ReturnState`, `ClosureOutcome`, `ReimbursementKind`: string enums указанного набора.
- `ReturnItem`: Codable/Equatable/Sendable value с mutable полями выше;
  init требует только title/merchant, default state planned, optional fields nil,
  notes/events empty; Date inputs default now/createdAt. `validated() throws -> ReturnItem`.
- `Reimbursement`: Codable/Equatable/Sendable value; init требует returnItemID,
  date, amountCents, kind; id default UUID, note empty; `validated() throws -> Reimbursement`.
- `Money.cents(from:)` использует строгий decimal парсинг и диапазон 0...100000000;
  `Money.formatted(_:)` форматирует cents (включая отрицательную разницу);
  `Money.validate(cents:currency:allowsZero:) throws` и `Money.adding(_:_:) throws`
  проверяют валюту/диапазон и арифметическое переполнение.
- `ReturnItem.moneyReceivedCents() throws`, `storeCreditCents() throws`,
  `unresolvedDifferenceCents() throws -> Int?` используют только events;
  nil expectation даёт nil difference, excess — отрицательную разницу.
- `ReturnArchive`: format/version/records; `init(records:)` задаёт marker/version.
  `ArchiveCodec.encode(_ records: [ReturnItem]) throws -> Data` и
  `decode(_ data: Data) throws -> [ReturnItem]` проверяют весь архив. Errors typed;
  никакой filesystem операции или частичного результата внутри codec.

P2 fields (attachment/reminder/settings/summary) не входят в v1 и отклоняются как
unknown fields. Filesystem draft отделяется в `ReturnQueueStorageDraft` target;
его прежние load/save не доказывают T005 corrupt-save blocking/atomic replacement.

Проверка всего содержимого: структура, версия, уникальные ID, связи событий, известные
enum, реальные даты, допустимые текст/суммы/валюта. Если хотя бы один объект недопустим,
нет частичного восстановления или молчаливого пропуска. Новые версии не декодируются
как старые с потерей незнакомых полей.

Пользователь видит preview количества записей и предупреждение: текущие записи будут
заменены. Cancel не меняет файл. Перед подтверждением доступен экспорт текущей базы.
После подтверждения: полная проверка -> временное хранилище -> атомарная замена ->
обновление UI. Если операция не закончилась, прежняя база остаётся восстановимой.
Восстановление того же архива дважды даёт тот же состав, не добавляет дубликаты.

Если исходная база повреждена, обычный Save заблокирован; экспортируется исходный файл
для восстановления. Пользователь выбирает валидный archive и подтверждает replacement.
Ошибка чтения текущего файла не выдаётся за «у вас нет возвратов».

P2: новый поддерживаемый формат содержит сами фото и переносимые настройки. Проверяются manifest, размер,
media type, наличие файлов и безопасные относительные пути; absolute/.. пути и символические
ссылки не допускаются. Missing media/zip bomb/oversized archive отклоняются до замены.
Лимиты P2 и миграция из v1 фиксируются в T017. Экспортированный архив чувствителен;
копии вне приложения контролирует сам пользователь.

P2 переносит LocalSettings: global enable, default local hour/minute и lead day;
а также per-item enabled/kind, выбранный lead day либо ручную checkDate и local time.
OS permission, системные request IDs и производное Scheduled не переносятся.
Профиль — эти локальные настройки, без user account/email/avatar/backend.
Значения и связи с ReturnItem проверяются до replacement; невозможный час/минута,
неизвестный type, недопустимый lead day или несуществующая checkDate отклоняют архив.
Наличие пользовательского opt-in при удалённом deadline допустимо как Not scheduled,
а не основание подставить новую дату. Корректный P1 импорт в P2 получает settings
по умолчанию (global и per-item off), без запроса разрешения только из-за restore.

После успешной замены отменяется старое расписание; новое создаётся только для будущих
применимых событий с восстановленным выбором, общим разрешением пользователя и
текущим device permission. Устройство с denied не считается разрешившим уведомления.
Отказ/ошибка планирования отображается отдельно и не выдаётся за Scheduled.
После неуспешного восстановления ни база, ни прежний выбор настроек не заменяются.

Итоги Summary не входят в архив как самостоятельные финансовые значения: после
restore они пересчитываются из Reimbursement.date, amountCents, kind и returnItemID.
Roundtrip обязан сохранять результаты обоих периодов; правка/удаление события после
restore меняет Summary без отдельного редактирования итогов.
