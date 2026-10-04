# Очередь по месту сдачи — T007/T008

Статус: T007/T008 приняты root 2026-10-04 после tests-first, отдельного review и независимой проверки: 106 native tests, обе unsigned сборки, пять UI-сценариев на свежем симуляторе и визуальная проверка Queue. Доказательства — в [verification.md](../verification.md). T001–T008 приняты; 20 задач открыты.
Основание: US2, FR-008–012; модель, JSON, Storage и принятый T006 не меняются.

## Pure Core API

Новый `ReturnQueue/Core/ReturnQueueSelector.swift`, только Foundation:

```swift
public enum QueueLocationID: Hashable, Sendable {
  case named(String)
  case notSet
}

public struct ReturnQueueGroup: Identifiable, Equatable, Sendable {
  public let id: QueueLocationID
  public let displayName: String
  public let representativeItemID: UUID
  public let items: [ReturnItem]
}

public enum ReturnQueueSelector {
  public static func groups(from records: [ReturnItem]) -> [ReturnQueueGroup]
  public static func isPastEnteredDate(_ returnBy: CalendarDay?, today: CalendarDay) -> Bool
}
```

Selector принимает записи подтверждённого snapshot с валидными уникальными ID.
Он ничего не сохраняет, не исправляет модель и не получает время/часовой пояс
из системы. Результат производный, не Codable и не часть архива.

- В Queue входят только `.planned`; `.droppedOff`, `.closed`, `.kept` исключены.
- Ключ места: trim `.whitespacesAndNewlines`, затем Foundation folding только
  `.caseInsensitive` с `en_US_POSIX`, затем NFC (`precomposedStringWithCanonicalMapping`).
  NFC делает Unicode-представление ключа детерминированным; диакритика не удаляется.
  Внутренние пробелы, адрес, пунктуация и уточнения не меняются. Нет геокодинга,
  приблизительного сравнения или группировки по merchant.
- Nil и пустое после trim место получают `.notSet` и `Location not set`.
  Введённый текст `Location not set` остаётся именованным местом с отдельным ID.
- Именованные группы идут по UTF-8 ключа лексикографически; `.notSet` последняя.
  Сортировка не зависит от локали устройства или порядка входного массива.
- Display name — trimmed исходное место представителя, с исходным регистром.
  Представитель — запись группы с минимальными `createdAt`, затем ASCII
  `id.uuidString`. Срок не выбирает представителя. Неизвестная группа использует
  фиксированную подпись и такой же выбор представителя для accessibility anchor.
- В каждой группе: известный `returnBy` по возрастанию; nil после известных;
  равные даты (включая два nil) — `createdAt` по возрастанию; полный tie — ASCII
  `id.uuidString` по возрастанию. `CalendarDay` сравнивается напрямую по year/month/day,
  без превращения сохранённого дня в UTC instant.
- Past badge = `returnBy != nil && returnBy < today`. Сегодня и неизвестный срок
  не past. Единственный текст предупреждения: `Past your entered date`.
  Badge не меняет состояние, права на возврат или ожидаемую дату возмещения.

## Presentation bridge

Новый `ReturnQueue/Presentation/QueueViewModel.swift`:

```swift
@MainActor @Observable public final class QueueViewModel {
  public init(
    session: AppSession,
    now: @escaping @MainActor @Sendable () -> Date = { Date() },
    timeZone: @escaping @MainActor @Sendable () -> TimeZone = { .current }
  )
  public var groups: [ReturnQueueGroup] { get }
  public private(set) var today: CalendarDay?
  public func refreshToday()
  public func isPastEnteredDate(_ returnBy: CalendarDay?) -> Bool
}
```

`groups` каждый раз проецирует текущий `session.snapshot?.records ?? []`.
Нет собственного массива записей, reload/save API, изменяемого snapshot или
нового activity gate. Ошибка загрузки и блокировка изменений остаются в AppSession.
Последний подтверждённый snapshot можно показывать рядом с существующей ошибкой;
пустой результат до успешной загрузки не объявляется пустой базой.

`today` вычисляется при создании и `refreshToday()` через Gregorian Calendar,
фиксированную POSIX locale и текущий результат injected timezone provider.
Компоненты year/month/day берутся из injected instant; сохранённые дни не сдвигаются.
Providers вызываются только на MainActor; изменяемый clock fixture также MainActor,
без unsafe/unchecked Sendable или mutable lock boxes.
Если injected instant нельзя представить валидным CalendarDay, today = nil и
past badge не показывается. Проверяются finite instant, Gregorian era = 1 (AD)
и поддержанный диапазон CalendarDay; BCE year 1 не превращается в AD year 1.
Обычные даты устройства находятся в поддержанном диапазоне.

UI вызывает refresh при появлении, возврате в foreground, смене системного времени/
часового пояса и местной полуночи. Эти события меняют только проекцию; записи и архив
не обновляются. Presentation tests отдельно проверяют смену clock/timezone provider.

## Queue UI и accessibility

`QueueView` строит секции групп внутри существующего native List/NavigationStack;
navigation title — `Return Queue`, native back action использует то же название.
RootView сохраняет Add, navigation destination, формы, loading/error/retry и recovery
с их действующими guards. Merchant виден отдельно от названия вещи и места сдачи.
На карточке есть введённый Return by либо `Return by: Not set`; известная дата
использует existing `DetailFormatting.day` с явно сохранённым годом, поэтому разные
годы не выглядят одинаково. Неизвестная сумма, если показана, не становится $0.00.
Empty Queue показывается только в `.ready`,
когда groups пусты и нет pending recovery cleanup: `No returns yet` при действительно
пустом snapshot, `No items to return` при наличии только других состояний.

Дизайн: Figma `SMVZHX6PVpx83cRfqM6S2o`, Queue `11:105`; context и screenshot
`/private/tmp/returnqueue-t008-figma-context.txt` и `/private/tmp/returnqueue-t008-figma.png`.
Native navigation chrome/
List/NavigationLink chevron, Dynamic Type и текущие asset tokens сохраняются.
Новый exact 16pt pin — `/private/tmp/returnqueue-t008-group-pin.svg` в `QueueGroupPin`
imageset с vector preservation; прежний 24pt DetailPin не подменяет его.
Новый `ColorWarning` = `#9a4c12`. Текст, а не один цвет, обозначает past.
Settings, P2 tabs, Drop-off/Keep/reminders и демонстрационные production записи
не добавляются. Add и переход в детали остаются настоящими действиями.

Стабильные IDs, без текста пользовательского места в identifier:

- `queue.list`, `queue.empty`, существующий `queue.add`.
- `queue.group.<representativeItemID.uuidString>` на label заголовка секции.
  Anchor детерминирован при одинаковом составе группы; перемещение представителя
  в другую группу закономерно меняет anchor. Deadline/edit merchant не меняют его.
- Существующий `queue.item.<itemID.uuidString>` на NavigationLink карточки.
  Сохраняется совместимость четырёх T006 UI tests; внутренняя merchant/date/badge
  семантика читается по тексту/VoiceOver label. Не ставить ID на enclosing Section,
  который может переопределить identifiers потомков SwiftUI.

## Tests-first и приёмка

Отдельный тестовый автор сначала материализует QueueTests и bridge tests по этому API;
отсутствующие новые символы — ожидаемый RED до implementation. После source freeze:

1. Planned-only: валидные записи всех четырёх состояний; остальные не исчезают из
   snapshot/архива. Merchant не разделяет одинаковое место и не заменяет nil location.
2. Trim/case/Unicode: варианты регистра и внешних пробелов объединены независимо от
   локали; composed/decomposed Unicode эквивалентны, разные диакритика/адрес/внутренние
   пробелы остаются отдельными группами. Nil/whitespace отдельны от буквального sentinel.
3. Перестановки входа сохраняют group order, representative label и item order;
   проверяются именованные группы + unknown last и tie по UUID.
4. Known даты ascending, unknown last, одинаковые дни/unknown по createdAt/UUID;
   leap day и смена timezone не меняют порядок сохранённых дней.
5. Yesterday даёт точный past text; today/future/nil — нет. Один instant в разных
   timezone даёт разные today, при этом returnBy неизменен. Midnight refresh меняет
   только badge; locale Calendar устройства не подменяет Gregorian.
6. Bridge видит успешно сохранённые create/edit без копии записей; failed write не
   перемещает карточку, failed load не даёт ложного ready-empty или новых изменений.
7. Один новый UI scenario: реальные Add трёх вещей для двух мест/магазинов, объединение
   вариантов места, dated/unknown order и merchant labels; edit меняет location/date,
   перегруппировка и сортировка сохраняются после terminate/relaunch. Screenshot и
   actual disk inspection подтверждают данные. Test fixtures изолированы; ни одного
   production seed или расширения существующего Debug fixture service.
8. Все существующие 93 package tests + новые Queue/bridge tests; все четыре T006 UI
   tests + Queue scenario; обе unsigned iOS builds; strict lint, harness и final diff.
   Отдельные review, fresh independent QA и root visual comparison предшествуют
   закрытию T007/T008 и root commit/push. Full P1/P2, T015/T016 остаются открытыми.

Ownership после согласования: implementation worker — новый Core selector, новый
QueueViewModel/QueueView, узкая RootView интеграция, DesignTokens и указанные assets.
Отдельный test writer — QueueTests, bridge tests и новый UI scenario. Lead — контракт,
project/metadata integration при необходимости и evidence/docs. Принятые Core model,
wire/Storage, AppSession, editor, detail/recovery behavior и сервисы frozen.
