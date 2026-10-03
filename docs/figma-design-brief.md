# Return Queue — бриф iPhone-макетов

Дата: 2026-10-03. Основание: `../specs/001-free-return-prototype/spec.md` и
`../specs/001-free-return-prototype/contracts/ui.md`. Это проектирование P1, а не
доказательство спроса или работающая сборка. Фото и напоминания относятся к P2.

## Характер и навигация

Спокойный native iOS: светлая системная подложка, белые сгруппированные поверхности,
системная типографика, синий акцент действий, мягкие разделители. Цвет помогает, но
каждый статус и ошибка имеют текст. Без декоративного dashboard, баллов, общей
«экономии», аккаунта и монетизации. Содержание важнее иллюстраций.

Базовый макет — iPhone, 393 × 852 pt с системными safe areas. Это рабочий размер
холста, не ограничение поддержки устройств. Цели нажатия ≥44 pt; длинные названия,
ошибки и увеличенный текст переносятся. Не прятать критические суммы многоточием.

Главные вкладки: **`Queue`**, **`Waiting`**, **`History`**. Заголовок второй:
**`Waiting for refund`**. Верхняя кнопка настроек открывает **`Data & settings`**.
`Add return` доступна из Queue. Детали открываются нажатием строки. Add/Edit —
модальная форма с `Cancel` и `Save`; вложенные формы не требуют новой вкладки.

Подготовить шесть основных макетов ниже. Остальные состояния описать рядом;
при необходимости вынести только два ключевых sheet-макета: запись поступления и
предпросмотр восстановления. Итого максимум восемь основных визуальных макетов.

## 1. Queue

Заголовок `Return Queue`; кнопка `Add return`; активная вкладка `Queue`.
Короткая подпись: `Group returns by drop-off location.`

Группы: `UPS Store — Market St`, `Target — Westgate`, `Location not set`.
В каждой строке название вещи, **магазин покупки**, введённая дата либо
`Return date not set`; сумма необязательна. Две вещи разных магазинов в первой
группе показывают основную пользу продукта. USB-C dock с Oct 5 идёт перед shoes
с Oct 6. Нельзя выдавать одну группу за оптимизированный маршрут.

Для linen shirt показать `Past your entered date` и `Oct 2, 2026`.
Это отметка введённой даты, а не отказ магазина. Для desk lamp нет даты или суммы.

Пустое состояние: `Keep your returns in one place.` и `Add your first return`.
Пустая вкладка Waiting: `No returns waiting for a refund.`

## 2. Add return

Заголовок `Add return`. Только два открытых обязательных поля:
`Item name` и `Merchant`. Примеры ввода: `USB-C dock`, `Amazon`.
Раскрываемая строка `Optional details` содержит:

- `Drop-off location` — свободный текст; подсказка `Include a branch or address to separate locations.`
- `Return by` — изначально `Not set`; дата выбирается явно.
- `Expected refund (USD)` и `Purchase price (USD)` — отдельные пустые поля.
- `Purchase date`, `Expected refund date` — изначально `Not set`.
- `Policy source` — необязательная заметка или ссылка.
- `Notes`.

Под датой: `Enter the date from your return policy.` Никаких автоматически
подставленных сроков, сегодняшней даты или нулей в неизвестных полях.
Фото и напоминания не занимают место в форме P1.

Ошибки: `Enter an item name.`, `Enter a merchant.`,
`Enter a valid USD amount with up to 2 decimal places.` Ошибка рядом с полем;
ввод сохраняется. При ошибке записи форма остаётся открытой:
`Couldn't save your changes. Try again.` и `Try again`.

## 3. Return details — до сдачи

Демо: Running shoes. Заголовок вещи; `Target` отдельной строкой; статус `To return`.
Разделы: `Drop-off location`, `Return by`, `Expected refund`, `Purchase price`,
`Notes`. Дата показана вместе с подсказкой `Date entered by you.`

Основное действие `Mark as dropped off`; вторичное `Keep item`; в меню `Edit`,
`Correct status`, `Delete return`. Неизвестные значения — `Not set`.
При неполных данных основные действия остаются доступными.

Sheet сдачи: `Mark as dropped off`, поле `Drop-off date` с сегодняшней датой,
которую можно изменить; `Cancel`, `Confirm drop-off`.
Подсказка: `This records your drop-off. It doesn't confirm merchant acceptance.`
После подтверждения запись находится во вкладке Waiting, а не пропадает.

## 4. Waiting for refund / журнал поступлений

Полноценная вкладка показывает две демо-записи: Denim jacket и Coffee grinder.
У каждой видны магазин, `Dropped off` с датой, `Money received` и `Store credit`.
Без прогресса банковской проверки или автоматически объявленной просрочки.

Вариант деталей Denim jacket содержит:

- `Expected refund` — `$100.00`.
- `Money received` — `$50.00`.
- `Store credit` — `$30.00`.
- `Difference from expected` — `$20.00`.
- Подсказка `Based on amounts you've recorded.`
- Раздел `Recorded reimbursements`: две отдельные строки с типом, датой и суммой;
  каждую можно открыть для `Edit` / `Delete`.
- Действия `Record reimbursement` и `Close return`.

Sheet поступления: `Record reimbursement`, выбор `Money` / `Store credit`,
поля `Amount (USD)`, `Date received`, `Note (optional)`; `Cancel`, `Save`.
Дата по умолчанию сегодня и редактируется. Это ручная запись, не банковская проверка.

Для Coffee grinder ожидаемая сумма `Not set`: показывать записанные `$30.00`
денег, но **не** остаток, процент, «полный возврат» или прогресс-бар.

Sheet закрытия: `Close return`, выбор `Refund received`, `Partial refund`,
`Denied`, `Cancelled`; необязательная поясняющая `Note`; `Cancel`, `Confirm close`.
При известной разнице показать суммы до подтверждения. При неизвестном ожидании
пользователь выбирает итог сам, полнота не вычисляется.

## 5. History

Заголовок `History`; четыре записи из таблицы демо. Строка содержит название,
магазин, текст итога и дату закрытия. Детали сохраняют даты, заметки и все поступления;
доступны `Edit`, `Correct status`, `Delete return`.

Для Duvet cover показать `Refund received`, `$50.00 money` и `$50.00 store credit`
раздельно: нельзя подписывать их как `$100.00 money received`.
Для Travel bag — `Partial refund`, ожидание `$100.00`, деньги `$80.00`,
разница `$20.00`, заметка о комиссии. Для Wireless mouse — `Denied`, без
выдуманного поступления. Для Water bottle — `Keeping item`.

Пустое состояние: `Completed returns will appear here.` Исправление состояния
сохраняет записанные поступления; пользователь видит их и после возвращения в Waiting.

## 6. Data & settings — копии данных

Раздел `Your data`: `Stored on this iPhone. No account or sync.`
Действия `Export backup`, `Restore backup`; отдельно разрушительное `Delete all data`.
Под экспортом: `Backups may contain purchase details and personal information.`
Не размещать настройки уведомлений и фото в P1.

Предпросмотр выбранного валидного файла: `Restore backup`, `10 returns`,
`6 reimbursements`, `This will replace the returns currently on this iPhone.`
Действия `Export current backup`, `Replace current data`, `Cancel`.
После замены: `Backup restored.` Экспорт использует системное меню сохранения/шаринга.
Выбор файла — системный picker, без макета облачного аккаунта.

Состояние ошибки: `Couldn't restore this backup. Your current data hasn't changed.`
Состояние повреждённой базы: `Couldn't read your data.`; действия `Try again`,
`Export original data`. Обычные изменения недоступны до успешного чтения.

## Подтверждения и дополнительные состояния

| Событие | Заголовок / текст | Действия |
|---|---|---|
| Удаление записи | `Delete this return?` / `This deletes the return and its recorded reimbursements.` | `Cancel`, `Delete return` |
| Удаление всей базы | `Delete all data?` / `This deletes all returns on this iPhone. Backups you've saved aren't deleted.` | `Cancel`, `Delete all data` |
| Решение оставить | `Keep this item?` / `This moves the return to History. Recorded reimbursements will stay.` | `Cancel`, `Keep item` |
| Неполное закрытие jacket | `Close with a difference?` / `You've recorded $50.00 in money and $30.00 in store credit against $100.00 expected. The difference is $20.00.` | `Cancel`, `Confirm close` |
| Поступления выше ожидания | `Recorded amount exceeds expected` / `Save the amount you've entered?` | `Cancel`, `Save amount` |
| Неизвестное ожидание при закрытии | `Choose the outcome` / `The expected amount isn't set. Choose the outcome based on your records.` | Выбор итога, `Cancel`, `Confirm close` |

Восстановление: показывать проверку файла до кнопки замены; ошибка не выглядит успехом.
При сохранении не закрывать форму до подтверждения результата. В развёрнутом тексте
состояний нет обещаний права на возврат, доставки уведомлений или подтверждения банка.
Исправление статуса — существующее действие; не превращать его в новую систему этапов.

## Единые демо-данные

Точка времени всех макетов — **Oct 3, 2026**. Даты и условия — вымышленные
пользовательские записи; названия магазинов не означают их реальную политику возврата.
Всего **10 записей: 4 Queue, 2 Waiting, 4 History; 6 поступлений**.

| Item / Merchant | Состояние | Drop-off location | Return by | Purchase / Expected | Поступления и завершение |
|---|---|---|---|---|---|
| USB-C dock / Amazon | To return | UPS Store — Market St | Oct 5, 2026 | $39.99 / $39.99 | Нет |
| Running shoes / Target | To return | UPS Store — Market St | Oct 6, 2026 | $89.99 / $79.99 | Нет; заметка `Return shipping may be deducted.` |
| Linen shirt / Target | To return | Target — Westgate | Oct 2, 2026 | $34.00 / $34.00 | Нет; отметка `Past your entered date` |
| Desk lamp / Walmart | To return | Not set | Not set | Not set / Not set | Нет |
| Denim jacket / Nordstrom | Waiting for refund | Nordstrom — Downtown | Oct 1, 2026 | $100.00 / $100.00 | Сдан Sep 28; Money $50.00 Sep 30; Store credit $30.00 Oct 2; разница $20.00 |
| Coffee grinder / Amazon | Waiting for refund | UPS Store — Market St | Not set | $59.99 / Not set | Сдан Sep 30; Money $30.00 Oct 2; без вычисленного остатка |
| Duvet cover / Target | Closed: Refund received | Target — Westgate | Sep 30, 2026 | $100.00 / $100.00 | Сдан Sep 25; Money $50.00 Oct 1; Store credit $50.00 Oct 2; закрыт Oct 2 |
| Travel bag / REI | Closed: Partial refund | REI — Downtown | Sep 28, 2026 | $100.00 / $100.00 | Сдан Sep 24; Money $80.00 Oct 1; закрыт Oct 1; `Store deducted a $20 return fee.` |
| Wireless mouse / Amazon | Closed: Denied | UPS Store — Market St | Sep 28, 2026 | $29.99 / $29.99 | Сдан Sep 26; без поступлений; закрыт Sep 29; `Merchant declined the return.` |
| Water bottle / Target | Keeping item | Not set | Not set | $24.00 / Not set | Без сдачи/поступлений; закрыт Sep 27; `Decided to keep it.` |

Для демонстрации sheet частичного закрытия использовать копию состояния Denim jacket
до закрытия, итог `Partial refund`, заметку `Accepted $80 total; $20 return fee.`
Не показывать эту копию вторым объектом в основной базе или считать её дополнительным
поступлением. Для ошибок и превышения ожидания также использовать отдельные состояния
макета, не менять базовые суммы и счётчики.
